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


@import ZMUtilities;
@import ZMTransport;
@import WireRequestStrategy;

#import "ZMMissingUpdateEventsTranscoder+Internal.h"
#import "ZMSyncStrategy.h"
#import <zmessaging/zmessaging-Swift.h>
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

- (void)appendPotentialGapSystemMessageIfNeededWithResponse:(ZMTransportResponse *)response;

@end


@interface ZMMissingUpdateEventsTranscoder (Pagination) <ZMSimpleListRequestPaginatorSync>
@end


@implementation ZMMissingUpdateEventsTranscoder

- (instancetype)initWithSyncStrategy:(ZMSyncStrategy *)strategy
previouslyReceivedEventIDsCollection:(id<PreviouslyReceivedEventIDsCollection>)eventIDsCollection
                         application:(id <ZMApplication>)application
        backgroundAPNSPingbackStatus:(BackgroundAPNSPingBackStatus *)backgroundAPNSPingbackStatus
{
    self = [super initWithManagedObjectContext:strategy.syncMOC];
    if(self) {
        _syncStrategy = strategy;
        self.application = application;
        self.previouslyReceivedEventIDsCollection = eventIDsCollection;
        self.pingbackStatus = backgroundAPNSPingbackStatus;
        self.listPaginator = [[ZMSimpleListRequestPaginator alloc] initWithBasePath:NotificationsPath
                                                                           startKey:StartKey
                                                                           pageSize:ZMMissingUpdateEventsTranscoderListPageSize
                                                                managedObjectContext:self.managedObjectContext
                                                                    includeClientID:YES
                                                                         transcoder:self];
    }
    return self;
}

- (BOOL)isDownloadingMissingNotifications
{
    return self.listPaginator.hasMoreToFetch;
}

- (BOOL)isFetchingStreamForAPNS
{
    return self.application.applicationState == UIApplicationStateBackground &&
           self.pingbackStatus.status == PingBackStatusInProgress;
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

    if (self.isFetchingStreamForAPNS) {
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

- (BOOL)isSlowSyncDone
{
    return self.lastUpdateEventID != nil && !self.listPaginator.hasMoreToFetch;
}

- (void)setNeedsSlowSync
{
    // no op
}

- (ZMTransportRequest *)nextRequest
{
    BOOL fetchingStream = self.isFetchingStreamForAPNS;
    BOOL hasNewNotification = self.pingbackStatus.hasNotificationIDs;
    BOOL inProgress = self.listPaginator.status == ZMSingleRequestInProgress;

    // We want to create a new request if we are either currently fetching the paginated stream
    // or if we have a new notification ID that rewuires a pingback.
    BOOL shouldCreateRequest = inProgress || hasNewNotification;

    if (fetchingStream && shouldCreateRequest) {
        EventsWithIdentifier *newEvents = self.pingbackStatus.nextNotificationEventsWithID;

        if (nil != newEvents && ![newEvents isEqual:self.notificationEventsToCancel]) {
            self.notificationEventsToCancel = newEvents;
            [self.listPaginator resetFetching];
        }

        if (nil != self.notificationEventsToCancel) {
            ZMTransportRequest *request = self.listPaginator.nextRequest;
            [request forceToVoipSession];
            return request;
        }
    }

    return nil;
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
    
    NSString *timestamp = ((NSString *) response.payload.asDictionary[@"time"]);
    if (timestamp) {
        [self updateServerTimeDeltaWithTimestamp:timestamp];
    }
    
    NSUUID *latestEventId = [self processUpdateEventsAndReturnLastNotificationIDFromPayload:response.payload syncStrategy:self.syncStrategy];
    if (latestEventId != nil) {
        self.lastUpdateEventID = latestEventId;
    }
    
    BOOL hasMore = ((NSNumber *) response.payload.asDictionary[@"has_more"]).boolValue;
    if(!hasMore) {
        [self.previouslyReceivedEventIDsCollection discardListOfAlreadyReceivedPushEventIDs];
    }
    [self appendPotentialGapSystemMessageIfNeededWithResponse:response];
    return self.lastUpdateEventID;
}

- (NSUUID *)startUUID
{
    return self.lastUpdateEventID;
}

- (BOOL)shouldParseErrorResponseForStatusCode:(NSInteger)statusCode;
{
    if (statusCode == 404) {
        return YES;
    }

    if (nil != self.notificationEventsToCancel) {
        [self.pingbackStatus didFailDownloadingOriginalEvents:self.notificationEventsToCancel];
        self.notificationEventsToCancel = nil;
    }

    return NO;
}

@end
