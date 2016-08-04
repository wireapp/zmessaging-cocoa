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
@import ZMCDataModel;
@import Cryptobox;

#import "ZMMissingUpdateEventsTranscoder+Internal.h"
#import "ZMSingleRequestSync.h"
#import "ZMSyncStrategy.h"
#import <zmessaging/zmessaging-Swift.h>
#import "ZMSimpleListRequestPaginator.h"
#import "CBCryptoBox+UpdateEvents.h"

static NSString * const LastUpdateEventIDStoreKey = @"LastUpdateEventID";
static NSString * const NotificationsKey = @"notifications";
static NSString * const NotificationsPath = @"/notifications";
static NSString * const StartKey = @"since";

NSUInteger const ZMMissingUpdateEventsTranscoderListPageSize = 500;




@interface ZMMissingUpdateEventsTranscoder ()

@property (nonatomic, readonly, weak) ZMSyncStrategy *syncStrategy;
@property (nonatomic, readonly, weak) BackgroundAPNSPingBackStatus *pingBackStatus;
@property (nonatomic) EventsWithIdentifier *notificationEventsToFetch;

- (void)appendPotentialGapSystemMessageIfNeededWithResponse:(ZMTransportResponse *)response;

@end


@interface ZMMissingUpdateEventsTranscoder (Pagination) <ZMSimpleListRequestPaginatorSync>
@end


@implementation ZMMissingUpdateEventsTranscoder

- (instancetype)initWithSyncStrategy:(ZMSyncStrategy *)strategy
                  apnsPingBackStatus:(BackgroundAPNSPingBackStatus*)pingBackStatus
{
    self = [super initWithManagedObjectContext:strategy.syncMOC];
    if(self) {
        _syncStrategy = strategy;
        _pingBackStatus = pingBackStatus;
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

+ (NSArray<NSDictionary *> *)eventDictionariesFromPayload:(id<ZMTransportData>)payload
{
    return [payload.asDictionary optionalArrayForKey:@"notifications"].asDictionaries;
}

- (NSArray<ZMUpdateEvent *>*)processAndReturnUpdateEventsFromPayload:(id<ZMTransportData>)payload
{
    
    ZMSTimePoint *tp = [ZMSTimePoint timePointWithInterval:10 label:NSStringFromClass([self class])];
    NSArray *eventsDictionaries = [[self class] eventDictionariesFromPayload:payload];
    
    NSMutableArray *parsedEvents = [NSMutableArray array];
    NSMutableDictionary *lastCallStateEvents = [NSMutableDictionary dictionary];
    
    NSMutableArray *decryptedEvents = [NSMutableArray array];
    for(NSDictionary *eventDict in eventsDictionaries) {
        NSArray *events = [ZMUpdateEvent eventsArrayFromPushChannelData:eventDict];
        for (ZMUpdateEvent *event in events) {
            [event appendDebugInformation:@"From missing update events transcoder, processUpdateEventsAndReturnLastNotificationIDFromPayload"];
            
            ZMUpdateEvent *decryptedEvent = [self.managedObjectContext.zm_cryptKeyStore.box decryptUpdateEventAndAddClient:event managedObjectContext:self.managedObjectContext];
            if (nil != decryptedEvent) {
                [decryptedEvents addObject:decryptedEvent];
                if (decryptedEvent.type == ZMUpdateEventCallState) {
                    lastCallStateEvents[event.conversationUUID] = decryptedEvent;
                }
                else {
                    [parsedEvents addObject:decryptedEvent];
                }
            }
        }
    }
    ZMSyncStrategy *strongStrategy = self.syncStrategy;
    [strongStrategy processUpdateEvents:parsedEvents ignoreBuffer:YES];
    [strongStrategy processUpdateEvents:lastCallStateEvents.allValues ignoreBuffer:self.isFetchingStreamForAPNS];
    
    [tp warnIfLongerThanInterval];
    return decryptedEvents;
}

- (BOOL)hasLastUpdateEventID
{
    return self.lastUpdateEventID != nil;
}

- (BOOL)isFetchingStreamForAPNS
{
    return ([[UIApplication sharedApplication] applicationState] == UIApplicationStateBackground) &&
           (self.pingBackStatus.status == PingBackStatusFetchingNotificationStream);
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

- (ZMTransportRequest *)nextRequest
{
    BackgroundAPNSPingBackStatus *strongStatus = self.pingBackStatus;
    BOOL systemsReady = ((strongStatus.status == PingBackStatusFetchingNotificationStream) &&
                         (self.listPaginator.status != ZMSingleRequestInProgress));
    BOOL hasNewNotificationID = strongStatus.hasNoticeNotificationIDs;
    BOOL hasNotificationInProgress = (self.notificationEventsToFetch != nil);
    
    ZMTransportRequest *request;
    if (systemsReady && (hasNewNotificationID || hasNotificationInProgress)) {
        EventsWithIdentifier *newEvents = strongStatus.nextNoticeNotificationEventsWithID;
        if (newEvents != nil) {
            self.notificationEventsToFetch = newEvents;
            [self.listPaginator resetFetching];
        }
        
        if (self.notificationEventsToFetch != nil) {
            request = [self.listPaginator nextRequest];
            [request forceToVoipSession];
        }
    }
    return request;
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


@end




@implementation ZMMissingUpdateEventsTranscoder (Pagination)

- (NSUUID *)nextUUIDFromResponse:(ZMTransportResponse *)response forListPaginator:(ZMSimpleListRequestPaginator *)paginator
{
    NSArray<ZMUpdateEvent *> *decryptedEvents = [self processAndReturnUpdateEventsFromPayload:response.payload];
    if (decryptedEvents.count > 0) {
        self.lastUpdateEventID = [decryptedEvents.lastObject uuid];
    }
    [self appendPotentialGapSystemMessageIfNeededWithResponse:response];
    if (self.notificationEventsToFetch != nil) {
        [self.pingBackStatus missingUpdateEventTranscoderWithDidReceiveEvents:decryptedEvents originalEvents:self.notificationEventsToFetch hasMore:paginator.hasMoreToFetch];
        if (!paginator.hasMoreToFetch) {
            self.notificationEventsToFetch = nil;
        }
    }
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
    if (self.notificationEventsToFetch != nil) {
        [self.pingBackStatus missingUpdateEventTranscoderFailedDownloadingEvents:self.notificationEventsToFetch];
        self.notificationEventsToFetch = nil;
    }
    return NO;
}

- (NSDictionary<NSString *,NSString *> *)additionalQueryParameters
{
    if (self.notificationEventsToFetch.identifier != nil) {
        return @{@"cancel_fallback" : self.notificationEventsToFetch.identifier.transportString};
    }
    return nil;
}

@end

