// 
// Wire
// Copyright (C) 2016 Wire Swiss GmbH
// 
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
// 
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License
// along with this program. If not, see http://www.gnu.org/licenses/.
// 


@import WireUtilities;
@import WireTransport;
@import WireRequestStrategy;

#import "ZMMissingUpdateEventsTranscoder+Internal.h"
#import "ZMSyncStrategy+EventProcessing.h"
#import <WireSyncEngine/WireSyncEngine-Swift.h>
#import "ZMSimpleListRequestPaginator.h"


static NSString * const LastUpdateEventIDStoreKey = @"LastUpdateEventID";
static NSString * const NotificationsKey = @"notifications";
static NSString * const NotificationsPath = @"/notifications";
static NSString * const StartKey = @"since";

NSUInteger const ZMMissingUpdateEventsTranscoderListPageSize = 500;

@interface ZMMissingUpdateEventsTranscoder ()

@property (nonatomic, readonly, weak) ZMSyncStrategy *syncStrategy;
@property (nonatomic, weak) id<PreviouslyReceivedEventIDsCollection> previouslyReceivedEventIDsCollection;
@property (nonatomic, weak) id <ZMApplication> application;
@property (nonatomic) BackgroundAPNSPingBackStatus *pingbackStatus;
@property (nonatomic) EventsWithIdentifier *notificationEventsToCancel;
@property (nonatomic, weak) SyncStatus* syncStatus;
@property (nonatomic, weak) OperationStatus* operationStatus;
@property (nonatomic, weak) id<ClientRegistrationDelegate> clientRegistrationDelegate;

- (void)appendPotentialGapSystemMessageIfNeededWithResponse:(ZMTransportResponse *)response;

@end


@interface ZMMissingUpdateEventsTranscoder (Pagination) <ZMSimpleListRequestPaginatorSync>
@end


@implementation ZMMissingUpdateEventsTranscoder


- (instancetype)initWithSyncStrategy:(ZMSyncStrategy *)strategy
previouslyReceivedEventIDsCollection:(id<PreviouslyReceivedEventIDsCollection>)eventIDsCollection
                         application:(id <ZMApplication>)application
        backgroundAPNSPingbackStatus:(BackgroundAPNSPingBackStatus *)backgroundAPNSPingbackStatus
                          syncStatus:(SyncStatus *)syncStatus
{
    self = [super initWithManagedObjectContext:strategy.syncMOC applicationStatus:strategy.applicationStatusDirectory];
    if(self) {
        _syncStrategy = strategy;
        self.application = application;
        self.previouslyReceivedEventIDsCollection = eventIDsCollection;
        self.pingbackStatus = backgroundAPNSPingbackStatus;
        self.syncStatus = syncStatus;
        self.operationStatus = strategy.applicationStatusDirectory.operationStatus;
        self.listPaginator = [[ZMSimpleListRequestPaginator alloc] initWithBasePath:NotificationsPath
                                                                           startKey:StartKey
                                                                           pageSize:ZMMissingUpdateEventsTranscoderListPageSize
                                                                managedObjectContext:self.managedObjectContext
                                                                    includeClientID:YES
                                                                         transcoder:self];
    }
    return self;
}

- (ZMStrategyConfigurationOption)configuration
{
    return ZMStrategyConfigurationOptionAllowsRequestsDuringSync
         | ZMStrategyConfigurationOptionAllowsRequestsWhileInBackground
         | ZMStrategyConfigurationOptionAllowsRequestsDuringEventProcessing
         | ZMStrategyConfigurationOptionAllowsRequestsDuringNotificationStreamFetch;
}

- (BOOL)isDownloadingMissingNotifications
{
    return self.listPaginator.hasMoreToFetch;
}

- (BOOL)isFetchingStreamForAPNS
{
    return self.pingbackStatus.status == BackgroundNotificationFetchStatusInProgress;
}

- (BOOL)isFetchingStreamInBackground
{
    return self.operationStatus.operationState == SyncEngineOperationStateBackgroundFetch;
}

- (NSUUID *)lastUpdateEventID
{
    return self.managedObjectContext.zm_lastNotificationID;
}

- (void)setLastUpdateEventID:(NSUUID *)lastUpdateEventID
{
    self.managedObjectContext.zm_lastNotificationID = lastUpdateEventID;
}

- (void)appendPotentialGapSystemMessageIfNeededWithResponse:(ZMTransportResponse *)response
{
    // A 404 by the BE means we can't get all notifications as they are not stored anymore
    // and we want to issue a system message. We still might have a payload with notifications that are newer
    // than the commissioning time, the system message should be inserted between the old messages and the potentional
    // newly received ones in the payload.
    if (response.HTTPStatus == 404) {
        NSDate *timestamp = nil;
        const NSTimeInterval offset = 0.1f;
        
        NSArray *eventsDictionaries = [ZMMissingUpdateEventsTranscoder eventDictionariesFromPayload:response.payload];
        if (nil != eventsDictionaries && nil != eventsDictionaries.firstObject) {
            ZMUpdateEvent *event = [ZMUpdateEvent eventsArrayFromPushChannelData:eventsDictionaries.firstObject].firstObject;
            // In case we receive a payload together with the 404 we set the timestamp of the system message
            // to be 1/10th of a second older than the oldest received notification for it to appear above it.
            timestamp = [event.timeStamp dateByAddingTimeInterval:-offset];
        }
        
        NSArray <ZMConversation *> *conversations = [self.syncStrategy.syncMOC executeFetchRequestOrAssert:[ZMConversation sortedFetchRequest]];
        for (ZMConversation *conversation in conversations) {
            if (nil == timestamp) {
                // In case we did not receive a payload we will add 1/10th to the last modified date of
                // the conversation to make sure it appears below the last message
                timestamp = [conversation.lastModifiedDate dateByAddingTimeInterval:offset] ?: [NSDate date];
            }
            [conversation appendNewPotentialGapSystemMessageWithUsers:conversation.activeParticipants.set
                                                            timestamp:timestamp];
        }
    }
}

- (void)updateServerTimeDeltaWithTimestamp:(NSString *)timestamp {
    NSDate *serverTime = [NSDate dateWithTransportString:timestamp];
    NSTimeInterval serverTimeDelta = [serverTime timeIntervalSinceNow];
    self.managedObjectContext.serverTimeDelta = serverTimeDelta;
}

+ (NSArray<NSDictionary *> *)eventDictionariesFromPayload:(id<ZMTransportData>)payload
{
    return [payload.asDictionary optionalArrayForKey:@"notifications"].asDictionaries;
}

- (NSUUID *)processUpdateEventsAndReturnLastNotificationIDFromPayload:(id<ZMTransportData>)payload syncStrategy:(ZMSyncStrategy *)syncStrategy
{
    ZMSTimePoint *tp = [ZMSTimePoint timePointWithInterval:10 label:NSStringFromClass(self.class)];
    NSArray *eventsDictionaries = [self.class eventDictionariesFromPayload:payload];
    
    NSMutableArray *parsedEvents = [NSMutableArray array];
    NSUUID *latestEventId = nil;
    
    for(NSDictionary *eventDict in eventsDictionaries) {
        NSUUID *sourceThreshold = self.notificationEventsToCancel.identifier;
        NSArray *events = [ZMUpdateEvent eventsArrayFromPushChannelData:eventDict pushStartingAt:sourceThreshold];

        for (ZMUpdateEvent *event in events) {
            [event appendDebugInformation:@"From missing update events transcoder, processUpdateEventsAndReturnLastNotificationIDFromPayload"];
            [parsedEvents addObject:event];
            
            if (!event.isTransient) {
                latestEventId = event.uuid;
            }
        }
    }

    if (nil != self.notificationEventsToCancel) {
        // In case we are fetching the stream because we have received a push notification we need to forward them to the pingback status
        // The status will forward them to the operationloop and check if the received notification was contained in this batch.
        [self.pingbackStatus didReceiveEncryptedEvents:parsedEvents originalEvents:self.notificationEventsToCancel hasMore:self.listPaginator.hasMoreToFetch];
        if (!self.listPaginator.hasMoreToFetch) {
            self.notificationEventsToCancel = nil;
        }
    } else {
        [syncStrategy processUpdateEvents:parsedEvents ignoreBuffer:YES];
    }

    [tp warnIfLongerThanInterval];
    return latestEventId;
}

- (void)updateBackgroundFetchResultWithResponse:(ZMTransportResponse *)response {
    UIBackgroundFetchResult result;
    if (response.result == ZMTransportResponseStatusSuccess) {
        if ([self.class eventDictionariesFromPayload:response.payload].count > 0) {
            result = UIBackgroundFetchResultNewData;
        } else {
            result = UIBackgroundFetchResultNoData;
        }
    } else {
        result = UIBackgroundFetchResultFailed;
    }
    
    [self.operationStatus finishBackgroundFetchWithFetchResult:result];
}

- (BOOL)hasLastUpdateEventID
{
    return self.lastUpdateEventID != nil;
}

- (void)startDownloadingMissingNotifications
{
    [self.listPaginator resetFetching];
}

- (NSArray *)contextChangeTrackers
{
    return @[];
}

- (NSArray *)requestGenerators;
{
    return @[self.listPaginator];
}

- (void)processEvents:(NSArray<ZMUpdateEvent *> *)events
           liveEvents:(BOOL)liveEvents
       prefetchResult:(__unused ZMFetchRequestBatchResult *)prefetchResult;
{
    
    if(!liveEvents) {
        return;
    }
    
    for(ZMUpdateEvent *event in events) {
        if(event.uuid != nil && ! event.isTransient && event.source != ZMUpdateEventSourcePushNotification) {
            self.lastUpdateEventID = event.uuid;
        }
    }
}

- (ZMTransportRequest *)nextRequestIfAllowed
{
    /// There are multiple scenarios in which this class will create a new request:
    ///
    /// 1.) We received a push notification and want to fetch the notification stream.
    ///     If this case we want to include the `cancel_fallback` query parameter to cancel fallback alert pushes.
    ///     This is the case if the `BackgroundAPNSPingBackStatus` has notification IDs.
    /// 2.) The OS awoke the application to perform a background fetch (the operation state will indicate this).
    /// 3.) The application came to the foreground and is performing a quick-sync (c.f. `isSyncing`).

    // The only reason we get the current value of this flag is ease testing this.
    // Otherwise each call to `self.isFetchingStreamForAPNS` needs a corresponding call to mock this flag in tests.
    BOOL fetchingForAPNS = self.isFetchingStreamForAPNS;
    BOOL fetchingStream = fetchingForAPNS || self.isFetchingStreamInBackground || self.isSyncing;

    // We want to create a new request if we are either currently fetching the paginated stream
    // or if we have a new notification ID that requires a pingback.
    if (fetchingStream) {
        // We only reset the paginator if it is neither in progress nor has more pages to fetch.
        if (self.listPaginator.status != ZMSingleRequestInProgress && !self.listPaginator.hasMoreToFetch) {
            [self.listPaginator resetFetching];
        }

        // We need to add the id before asking the list paginator for a request,
        // as it will ask us for additional query items.
        // Also we need to ensure that we will be able to generate a request (checking hasMoreToFetch),
        // to avoid setting the notificationEventsToCancel when we're unable to create a request.
        if (nil == self.notificationEventsToCancel && fetchingForAPNS && self.listPaginator.hasMoreToFetch) {
            self.notificationEventsToCancel = self.pingbackStatus.nextNotificationEventsWithID;
        }

        ZMTransportRequest *request = [self.listPaginator nextRequest];

        if (fetchingForAPNS && nil != request) {
            [request forceToVoipSession];
        }
                
        return request;
    } else {
        return nil;
    }
}

- (SyncPhase)expectedSyncPhase
{
    return SyncPhaseFetchingMissedEvents;
}

- (BOOL)isSyncing
{
    return self.syncStatus.currentSyncPhase == self.expectedSyncPhase;
}

- (NSArray <NSURLQueryItem *> *)additionalQueryItems
{
    if (nil == self.notificationEventsToCancel.identifier) {
        return nil;
    }

    return @[[NSURLQueryItem queryItemWithName:@"cancel_fallback" value:self.notificationEventsToCancel.identifier.transportString]];
}

@end


@implementation ZMMissingUpdateEventsTranscoder (Pagination)

- (NSUUID *)nextUUIDFromResponse:(ZMTransportResponse *)response forListPaginator:(ZMSimpleListRequestPaginator *)paginator
{

    NOT_USED(paginator);
    SyncStatus *syncStatus = self.syncStatus;
    OperationStatus *operationStatus = self.operationStatus;
    
    NSString *timestamp = ((NSString *) response.payload.asDictionary[@"time"]);
    if (timestamp) {
        [self updateServerTimeDeltaWithTimestamp:timestamp];
    }
    
    if (operationStatus.operationState == SyncEngineOperationStateBackgroundFetch) {
        [self updateBackgroundFetchResultWithResponse:response];
    }
    
    NSUUID *latestEventId = [self processUpdateEventsAndReturnLastNotificationIDFromPayload:response.payload syncStrategy:self.syncStrategy];
    if (latestEventId != nil) {
        if (response.HTTPStatus == 404 && self.isSyncing) {
            // If we fail during quick sync we need to re-enter slow sync and should not store the lastUpdateEventID until after the slowSync has been completed
            // Otherwise, if the device crashes or is restarted during slow sync, we lose the information that we need to perform a slow sync
            [syncStatus updateLastUpdateEventIDWithEventID:latestEventId];
            // TODO Sabine: What happens when we receive a 404 when we are fetching the notification for a push notification? In theory we would have to enter slow sync as well or at least not store the lastUpdateEventID until the next proper sync in the foreground
        }
        else {
            self.lastUpdateEventID = latestEventId;
        }
    }
    
    if (!self.listPaginator.hasMoreToFetch) {
        [self.previouslyReceivedEventIDsCollection discardListOfAlreadyReceivedPushEventIDs];
    }
    
    [self appendPotentialGapSystemMessageIfNeededWithResponse:response];
    
    if (response.result == ZMTransportResponseStatusPermanentError && self.isSyncing){
        [syncStatus failCurrentSyncPhaseWithPhase:self.expectedSyncPhase];
    }
    
    if (!self.listPaginator.hasMoreToFetch && self.isSyncing) {
        
        // The fetch of the notification stream was initiated after the push channel was established
        // so we must restart the fetching to be sure that we haven't missed any notifications.
        if (syncStatus.pushChannelEstablishedDate.timeIntervalSinceReferenceDate < self.listPaginator.lastResetFetchDate.timeIntervalSinceReferenceDate) {
            [syncStatus finishCurrentSyncPhaseWithPhase:self.expectedSyncPhase];
        }
    }
    
    return self.lastUpdateEventID;
}

- (NSUUID *)startUUID
{
    return self.lastUpdateEventID;
}

- (BOOL)shouldParseErrorForResponse:(ZMTransportResponse *)response
{
    if (response.HTTPStatus == 404) {
        return YES;
    }

    if (nil != self.notificationEventsToCancel) {
        [self.pingbackStatus didFailDownloadingOriginalEvents:self.notificationEventsToCancel];
        self.notificationEventsToCancel = nil;
    }

    return NO;
}

@end
