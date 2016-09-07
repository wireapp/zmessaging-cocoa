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

#import "ZMMissingUpdateEventsTranscoder+Internal.h"
#import "ZMSingleRequestSync.h"
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

- (void)appendPotentialGapSystemMessageIfNeededWithResponse:(ZMTransportResponse *)response;

@end


@interface ZMMissingUpdateEventsTranscoder (Pagination) <ZMSimpleListRequestPaginatorSync>
@end


@implementation ZMMissingUpdateEventsTranscoder

- (instancetype)initWithSyncStrategy:(ZMSyncStrategy *)strategy
{
    self = [super initWithManagedObjectContext:strategy.syncMOC];
    if(self) {
        _syncStrategy = strategy;
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
    return [((NSString *)[self.managedObjectContext persistentStoreMetadataForKey:LastUpdateEventIDStoreKey]) UUID];
}

- (void)setLastUpdateEventID:(NSUUID *)lastUpdateEventID
{
    NSUUID *previousUUID = self.lastUpdateEventID;
    if(
       previousUUID.isType1UUID && lastUpdateEventID.isType1UUID && // both are type 1 (or I can't compare)
       [previousUUID compareWithType1:lastUpdateEventID] != NSOrderedAscending // and I'm not setting to a new one
       ) {
        // only set if more recent
        return;
    }
    [self.managedObjectContext setPersistentStoreMetadata:lastUpdateEventID.UUIDString forKey:LastUpdateEventIDStoreKey];
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
+ (NSUUID *)processUpdateEventsAndReturnLastNotificationIDFromPayload:(id<ZMTransportData>)payload syncStrategy:(ZMSyncStrategy *)syncStrategy {
    
    ZMSTimePoint *tp = [ZMSTimePoint timePointWithInterval:10 label:NSStringFromClass(self)];
    NSArray *eventsDictionaries = [self eventDictionariesFromPayload:payload];
    
    NSMutableArray *parsedEvents = [NSMutableArray array];
    NSMutableDictionary *lastCallStateEvents = [NSMutableDictionary dictionary];
    NSUUID *latestEventId = nil;
    
    for(NSDictionary *eventDict in eventsDictionaries) {
        NSArray *events = [ZMUpdateEvent eventsArrayFromPushChannelData:eventDict];
        for (ZMUpdateEvent *event in events) {
            [event appendDebugInformation:@"From missing update events transcoder, processUpdateEventsAndReturnLastNotificationIDFromPayload"];

            if (event.type == ZMUpdateEventCallState) {
                lastCallStateEvents[event.conversationUUID] = event;
            }
            else {
                [parsedEvents addObject:event];
            }
            latestEventId = event.uuid;
        }
    }
    
    [syncStrategy processUpdateEvents:parsedEvents ignoreBuffer:YES];
    [syncStrategy processUpdateEvents:lastCallStateEvents.allValues ignoreBuffer:NO];
    
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


@end




@implementation ZMMissingUpdateEventsTranscoder (Pagination)

- (NSUUID *)nextUUIDFromResponse:(ZMTransportResponse *)response forListPaginator:(ZMSimpleListRequestPaginator *)paginator
{
    NOT_USED(paginator);
    
    NSUUID *latestEventId = [ZMMissingUpdateEventsTranscoder processUpdateEventsAndReturnLastNotificationIDFromPayload:response.payload syncStrategy:self.syncStrategy];
    if (latestEventId != nil) {
        self.lastUpdateEventID = latestEventId;
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
    return NO;
}

@end
