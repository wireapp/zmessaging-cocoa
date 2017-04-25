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
@property (nonatomic, weak) ZMOperationStatus* operationStatus;
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
    return ZMStrategyConfigurationOptionAllowsRequestsDuringSync | ZMStrategyConfigurationOptionAllowsRequestsDuringEventProcessing | ZMStrategyConfigurationOptionAllowsRequestsWhileInBackground;
}

- (BOOL)isDownloadingMissingNotifications
{
    return self.listPaginator.hasMoreToFetch;
}

- (BOOL)isFetchingStreamForAPNS
{
    return self.application.applicationState == UIApplicationStateBackground &&
           self.pingbackStatus.status == PingBackStatusInProgress &&
           self.pingbackStatus.hasNotificationIDs;
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
                timestamp = [conversation.lastModifiedDate dateByAddingTimeInterval:offset];
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
    NSMutableDictionary *lastCallStateEvents = [NSMutableDictionary dictionary];
    NSUUID *latestEventId = nil;
    
    for(NSDictionary *eventDict in eventsDictionaries) {
        NSUUID *sourceThreshold = self.notificationEventsToCancel.identifier;
        NSArray *events = [ZMUpdateEvent eventsArrayFromPushChannelData:eventDict pushStartingAt:sourceThreshold];

        for (ZMUpdateEvent *event in events) {
            [event appendDebugInformation:@"From missing update events transcoder, processUpdateEventsAndReturnLastNotificationIDFromPayload"];

            if (event.type == ZMUpdateEventCallState) {
                lastCallStateEvents[event.conversationUUID] = event;
            }
            else {
                [parsedEvents addObject:event];
            }
            
            if (!event.isTransient) {
                latestEventId = event.uuid;
            }
        }
    }

    if (self.isFetchingStreamForAPNS && self.notificationEventsToCancel != nil) {
        // In case we are fetching the stream because we have received a push notification we need to forward them to the pingback status
        // The status will forward them to the operationloop and check if the received notification was contained in this batch.
        NSArray <ZMUpdateEvent *> *events = [parsedEvents arrayByAddingObjectsFromArray:lastCallStateEvents.allValues];
        [self.pingbackStatus didReceiveEncryptedEvents:events originalEvents:self.notificationEventsToCancel hasMore:self.listPaginator.hasMoreToFetch];
        if (!self.listPaginator.hasMoreToFetch) {
            self.notificationEventsToCancel = nil;
        }
    } else {
        [syncStrategy processUpdateEvents:parsedEvents ignoreBuffer:YES];
        [syncStrategy processUpdateEvents:lastCallStateEvents.allValues ignoreBuffer:NO];
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
    BOOL fetchingStream = self.isFetchingStreamForAPNS || self.isFetchingStreamInBackground || self.isSyncing;
    
    // If we receive an APNS while fetching the notification stream we cancel the previous request
    // and start another one.
    if (self.pingbackStatus.hasNotificationIDs) {
        EventsWithIdentifier *newEvents = self.pingbackStatus.nextNotificationEventsWithID;

        if (nil != newEvents && ![newEvents isEqual:self.notificationEventsToCancel]) {
            self.notificationEventsToCancel = newEvents;
            [self.listPaginator resetFetching];
        }
    }

    // We want to create a new request if we are either currently fetching the paginated stream
    // or if we have a new notification ID that requires a pingback.
    if (fetchingStream) {
        if (self.listPaginator.status != ZMSingleRequestInProgress) {
            [self.listPaginator resetFetching];
        }
        
        ZMTransportRequest *request = [self.listPaginator nextRequest];
        
        if (self.notificationEventsToCancel != nil) {
            [request forceToVoipSession];
        }
                
        return request;
    } else {
        return nil;
    }
}

- (BOOL)isSyncing
{
    return self.syncStatus.currentSyncPhase == SyncPhaseFetchingMissedEvents;
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
    ZMOperationStatus *operationStatus = self.operationStatus;
    
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
        [syncStatus failCurrentSyncPhase];
    }
    
    if (!self.listPaginator.hasMoreToFetch && self.lastUpdateEventID != nil && self.isSyncing) {
        
        // The fetch of the notification stream was initiated after the push channel was established
        // so we must restart the fetching to be sure that we haven't missed any notifications.
        if (syncStatus.pushChannelEstablishedDate.timeIntervalSinceReferenceDate < self.listPaginator.lastResetFetchDate.timeIntervalSinceReferenceDate) {
            [syncStatus finishCurrentSyncPhase];
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
