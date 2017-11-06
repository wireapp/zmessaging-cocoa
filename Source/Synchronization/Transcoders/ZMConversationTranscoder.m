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


@import WireSystem;
@import WireUtilities;
@import WireTransport;
@import WireDataModel;
@import WireRequestStrategy;

#import "ZMConversationTranscoder.h"
#import "ZMAuthenticationStatus.h"
#import "ZMSimpleListRequestPaginator.h"
#import <WireSyncEngine/WireSyncEngine-Swift.h>

static NSString *const ConversationsPath = @"/conversations";
static NSString *const ConversationIDsPath = @"/conversations/ids";

NSUInteger ZMConversationTranscoderListPageSize = 100;
const NSUInteger ZMConversationTranscoderDefaultConversationPageSize = 32;

static NSString *const UserInfoTypeKey = @"type";
static NSString *const UserInfoUserKey = @"user";
static NSString *const UserInfoAddedValueKey = @"added";
static NSString *const UserInfoRemovedValueKey = @"removed";

static NSString *const ConversationTeamKey = @"team";
static NSString *const ConversationTeamIdKey = @"teamid";
static NSString *const ConversationTeamManagedKey = @"managed";

@interface ZMConversationTranscoder () <ZMSimpleListRequestPaginatorSync>

@property (nonatomic) ZMUpstreamModifiedObjectSync *modifiedSync;
@property (nonatomic) ZMUpstreamInsertedObjectSync *insertedSync;

@property (nonatomic) ZMDownstreamObjectSync *downstreamSync;
@property (nonatomic) ZMRemoteIdentifierObjectSync *remoteIDSync;
@property (nonatomic) ZMSimpleListRequestPaginator *listPaginator;

@property (nonatomic, weak) SyncStatus *syncStatus;
@property (nonatomic, weak) id<PushMessageHandler> localNotificationDispatcher;

@end


@interface ZMConversationTranscoder (DownstreamTranscoder) <ZMDownstreamTranscoder>
@end


@interface ZMConversationTranscoder (UpstreamTranscoder) <ZMUpstreamTranscoder>
@end


@interface ZMConversationTranscoder (PaginatedRequest) <ZMRemoteIdentifierObjectTranscoder>
@end


@implementation ZMConversationTranscoder

- (instancetype)initWithManagedObjectContext:(NSManagedObjectContext *)moc applicationStatus:(id<ZMApplicationStatus>)applicationStatus;
{
    Require(NO);
    self = [super initWithManagedObjectContext:moc applicationStatus:applicationStatus];
    NOT_USED(self);
    self = nil;
    return self;
}

- (instancetype)initWithManagedObjectContext:(NSManagedObjectContext *)managedObjectContext
                           applicationStatus:(id<ZMApplicationStatus>)applicationStatus
                 localNotificationDispatcher:(id<PushMessageHandler>)localNotificationDispatcher
                                  syncStatus:(SyncStatus *)syncStatus;
{
    self = [super initWithManagedObjectContext:managedObjectContext applicationStatus:applicationStatus];
    if (self) {
        self.localNotificationDispatcher = localNotificationDispatcher;
        self.syncStatus = syncStatus;
        self.modifiedSync = [[ZMUpstreamModifiedObjectSync alloc] initWithTranscoder:self entityName:ZMConversation.entityName updatePredicate:nil filter:nil keysToSync:self.keysToSync managedObjectContext:self.managedObjectContext];
        self.insertedSync = [[ZMUpstreamInsertedObjectSync alloc] initWithTranscoder:self entityName:ZMConversation.entityName managedObjectContext:self.managedObjectContext];
        NSPredicate *conversationPredicate =
        [NSPredicate predicateWithFormat:@"%K != %@ AND (connection == nil OR (connection.status != %d AND connection.status != %d) ) AND needsToBeUpdatedFromBackend == YES",
         [ZMConversation remoteIdentifierDataKey], nil,
         ZMConnectionStatusPending,  ZMConnectionStatusIgnored
         ];
         
        self.downstreamSync = [[ZMDownstreamObjectSync alloc] initWithTranscoder:self entityName:ZMConversation.entityName predicateForObjectsToDownload:conversationPredicate managedObjectContext:self.managedObjectContext];
        self.listPaginator = [[ZMSimpleListRequestPaginator alloc] initWithBasePath:ConversationIDsPath
                                                                           startKey:@"start"
                                                                           pageSize:ZMConversationTranscoderListPageSize
                                                               managedObjectContext:self.managedObjectContext
                                                                    includeClientID:NO
                                                                         transcoder:self];
        self.conversationPageSize = ZMConversationTranscoderDefaultConversationPageSize;
        self.remoteIDSync = [[ZMRemoteIdentifierObjectSync alloc] initWithTranscoder:self managedObjectContext:self.managedObjectContext];
    }
    return self;
}

- (ZMStrategyConfigurationOption)configuration
{
    return ZMStrategyConfigurationOptionAllowsRequestsDuringSync
         | ZMStrategyConfigurationOptionAllowsRequestsDuringEventProcessing
         | ZMStrategyConfigurationOptionAllowsRequestsDuringNotificationStreamFetch;
}

- (NSArray<NSString *> *)keysToSync
{
    NSArray *keysWithRef = @[
             ZMConversationArchivedChangedTimeStampKey,
             ZMConversationSilencedChangedTimeStampKey];
    NSArray *allKeys = [keysWithRef arrayByAddingObjectsFromArray:self.keysToSyncWithoutRef];
    return allKeys;
}

- (NSArray<NSString *>*)keysToSyncWithoutRef
{
    // Some keys don't have or are a time reference
    // These keys will always be over written when updating from the backend
    // They might be overwritten in a way that they don't create requests anymore whereas they previously did
    // To avoid crashes or unneccessary syncs, we should reset those when refetching the conversation from the backend
    
    return @[ZMConversationUserDefinedNameKey,
             ZMConversationUnsyncedInactiveParticipantsKey,
             ZMConversationUnsyncedActiveParticipantsKey,
             ZMConversationIsSelfAnActiveMemberKey];
    
}

- (NSUUID *)nextUUIDFromResponse:(ZMTransportResponse *)response forListPaginator:(ZMSimpleListRequestPaginator *)paginator
{
    NOT_USED(paginator);
    
    NSDictionary *payload = [response.payload asDictionary];
    NSArray *conversationIDStrings = [payload arrayForKey:@"conversations"];
    NSArray *conversationUUIDs = [conversationIDStrings mapWithBlock:^id(NSString *obj) {
        return [obj UUID];
    }];
    NSSet *conversationUUIDSet = [NSSet setWithArray:conversationUUIDs];
    [self.remoteIDSync addRemoteIdentifiersThatNeedDownload:conversationUUIDSet];
    
    
    if (response.result == ZMTransportResponseStatusPermanentError && self.isSyncing) {
        [self.syncStatus failCurrentSyncPhaseWithPhase:self.expectedSyncPhase];
    }
    
    [self finishSyncIfCompleted];
    
    return conversationUUIDs.lastObject;
}

- (void)finishSyncIfCompleted
{
    if (!self.listPaginator.hasMoreToFetch && self.remoteIDSync.isDone && self.isSyncing) {
        [self.syncStatus finishCurrentSyncPhaseWithPhase:self.expectedSyncPhase];
    }
}

- (SyncPhase)expectedSyncPhase
{
    return SyncPhaseFetchingConversations;
}

- (BOOL)isSyncing
{
    return self.syncStatus.currentSyncPhase == self.expectedSyncPhase;
}

- (ZMTransportRequest *)nextRequestIfAllowed
{
    if (self.isSyncing && self.listPaginator.status != ZMSingleRequestInProgress && self.remoteIDSync.isDone) {
        [self.listPaginator resetFetching];
        [self.remoteIDSync setRemoteIdentifiersAsNeedingDownload:[NSSet set]];
    }
    
    return [self.requestGenerators nextRequest];
}

- (NSArray *)contextChangeTrackers
{
    return @[self.downstreamSync, self.insertedSync, self.modifiedSync];
}

- (NSArray *)requestGenerators;
{
    if (self.isSyncing) {
        return  @[self.listPaginator, self.remoteIDSync];
    } else {
        return  @[self.downstreamSync, self.insertedSync, self.modifiedSync];
    }
}

- (ZMConversation *)createConversationFromTransportData:(NSDictionary *)transportData
                                        serverTimeStamp:(NSDate *)serverTimeStamp
{
    // If the conversation is not a group conversation, we need to make sure that we check if there's any existing conversation without a remote identifier for that user.
    // If it is a group conversation, we don't need to.
    
    NSNumber *typeNumber = [transportData numberForKey:@"type"];
    VerifyReturnNil(typeNumber != nil);
    ZMConversationType const type = [ZMConversation conversationTypeFromTransportData:typeNumber];
    if (type == ZMConversationTypeGroup || type == ZMConversationTypeSelf) {
        return [self createGroupOrSelfConversationFromTransportData:transportData serverTimeStamp:serverTimeStamp];
    } else {
        return [self createOneOnOneConversationFromTransportData:transportData type:type serverTimeStamp:serverTimeStamp];
    }
}

- (ZMConversation *)createGroupOrSelfConversationFromTransportData:(NSDictionary *)transportData
                                                   serverTimeStamp:(NSDate *)serverTimeStamp
{
    NSUUID * const convRemoteID = [transportData uuidForKey:@"id"];
    if(convRemoteID == nil) {
        ZMLogError(@"Missing ID in conversation payload");
        return nil;
    }
    BOOL conversationCreated = NO;
    ZMConversation *conversation = [ZMConversation conversationWithRemoteID:convRemoteID createIfNeeded:YES inContext:self.managedObjectContext created:&conversationCreated];
    [conversation updateWithTransportData:transportData serverTimeStamp:serverTimeStamp];
    
    if (conversation.conversationType != ZMConversationTypeSelf && conversationCreated) {
        // we just got a new conversation, we display new conversation header
        [conversation appendNewConversationSystemMessageIfNeeded];
        [self.managedObjectContext enqueueDelayedSave];
    }
    return conversation;
}

- (ZMConversation *)createOneOnOneConversationFromTransportData:(NSDictionary *)transportData
                                                           type:(ZMConversationType const)type
                                                serverTimeStamp:(NSDate *)serverTimeStamp;
{
    NSUUID * const convRemoteID = [transportData uuidForKey:@"id"];
    if(convRemoteID == nil) {
        ZMLogError(@"Missing ID in conversation payload");
        return nil;
    }
    
    // Get the 'other' user:
    NSDictionary *members = [transportData dictionaryForKey:@"members"];
    
    NSArray *others = [members arrayForKey:@"others"];

    if ((type == ZMConversationTypeConnection) && (others.count == 0)) {
        // But be sure to update the conversation if it already exists:
        ZMConversation *conversation = [ZMConversation conversationWithRemoteID:convRemoteID createIfNeeded:NO inContext:self.managedObjectContext];
        if ((conversation.conversationType != ZMConversationTypeOneOnOne) &&
            (conversation.conversationType != ZMConversationTypeConnection))
        {
            conversation.conversationType = type;
        }
        
        // Ignore everything else since we can't find out which connection it belongs to.
        return nil;
    }
    
    VerifyReturnNil(others.count != 0); // No other users? Self conversation?
    VerifyReturnNil(others.count < 2); // More than 1 other user in a conversation that's not a group conversation?
    
    NSUUID *otherUserRemoteID = [[others[0] asDictionary] uuidForKey:@"id"];
    VerifyReturnNil(otherUserRemoteID != nil); // No remote ID for other user?
    
    ZMUser *user = [ZMUser userWithRemoteID:otherUserRemoteID createIfNeeded:YES inContext:self.managedObjectContext];
    ZMConversation *conversation = user.connection.conversation;
    
    BOOL conversationCreated = NO;
    if (conversation == nil) {
        // if the conversation already exist, it will pick it up here and hook it up to the connection
        conversation = [ZMConversation conversationWithRemoteID:convRemoteID createIfNeeded:YES inContext:self.managedObjectContext created:&conversationCreated];
        RequireString(conversation.conversationType != ZMConversationTypeGroup,
                      "Conversation for connection is a group conversation: %s",
                      convRemoteID.transportString.UTF8String);
        user.connection.conversation = conversation;
    } else {
        // check if a conversation already exists with that ID
        [conversation mergeWithExistingConversationWithRemoteID:convRemoteID];
        conversationCreated = YES;
    }
    
    conversation.remoteIdentifier = convRemoteID;
    [conversation updateWithTransportData:transportData serverTimeStamp:serverTimeStamp];
    return conversation;
}


- (BOOL)shouldProcessUpdateEvent:(ZMUpdateEvent *)event
{
    switch (event.type) {
        case ZMUpdateEventConversationMessageAdd:
        case ZMUpdateEventConversationClientMessageAdd:
        case ZMUpdateEventConversationOtrMessageAdd:
        case ZMUpdateEventConversationOtrAssetAdd:
        case ZMUpdateEventConversationKnock:
        case ZMUpdateEventConversationAssetAdd:
        case ZMUpdateEventConversationMemberJoin:
        case ZMUpdateEventConversationMemberLeave:
        case ZMUpdateEventConversationRename:
        case ZMUpdateEventConversationMemberUpdate:
        case ZMUpdateEventConversationCreate:
        case ZMUpdateEventConversationConnectRequest:
            return YES;
        default:
            return NO;
    }
}

- (ZMConversation *)conversationFromEventPayload:(ZMUpdateEvent *)event conversationMap:(ZMConversationMapping *)prefetchedMapping
{
    NSUUID * const conversationID = [event.payload optionalUuidForKey:@"conversation"];
    
    if (nil == conversationID) {
        return nil;
    }
    
    if (nil != prefetchedMapping[conversationID]) {
        return prefetchedMapping[conversationID];
    }
    
    ZMConversation *conversation = [ZMConversation conversationWithRemoteID:conversationID createIfNeeded:NO inContext:self.managedObjectContext];
    if (conversation == nil) {
        conversation = [ZMConversation conversationWithRemoteID:conversationID createIfNeeded:YES inContext:self.managedObjectContext];
        // if we did not have this conversation before, refetch it
        conversation.needsToBeUpdatedFromBackend = YES;
    }
    return conversation;
}

- (void)updatePropertiesOfConversation:(ZMConversation *)conversation fromEvent:(ZMUpdateEvent *)event
{
    NSDate *timeStamp = event.timeStamp;
    
    BOOL isMessageEvent = (event.type == ZMUpdateEventConversationOtrMessageAdd) ||
                          (event.type == ZMUpdateEventConversationOtrAssetAdd);
    
    // Message events already update the conversation on insert. There is no need to do it here, since different message types (e.g. edit and delete) might have a different effect on the lastModifiedDate and unreadCount
    if (timeStamp != nil && !isMessageEvent) {
        [conversation updateLastServerTimeStampIfNeeded:timeStamp];
        if ([self shouldUnarchiveOrUpdateLastModifiedWithEvent:event]) {
            conversation.lastModifiedDate = [NSDate lastestOfDate:conversation.lastModifiedDate and:timeStamp];
        }
    }
    
    // Unarchive conversations when applicable
    // Message events are parsed separately since they might contain "invisible" messages
    if (!isMessageEvent && [self shouldUnarchiveOrUpdateLastModifiedWithEvent:event]) {
        [conversation unarchiveConversationFromEvent:event];
    }
}

- (BOOL)shouldUnarchiveOrUpdateLastModifiedWithEvent:(ZMUpdateEvent *)event
{
    switch (event.type) {
        case ZMUpdateEventConversationMemberUpdate:
        case ZMUpdateEventConversationMemberLeave:
        case ZMUpdateEventConversationRename:
            return NO;

        default:
            return YES;
    }
}

- (void)updatePropertiesOfConversation:(ZMConversation *)conversation withPostPayloadEvent:(ZMUpdateEvent *)event
{
    BOOL senderIsSelfUser = ([event.senderUUID isEqual:[ZMUser selfUserInContext:self.managedObjectContext].remoteIdentifier]);
    BOOL selfUserLeft = (event.type == ZMUpdateEventConversationMemberLeave) && senderIsSelfUser;
    if (selfUserLeft && conversation.clearedTimeStamp != nil && [conversation.clearedTimeStamp isEqualToDate:conversation.lastServerTimeStamp]) {
        [conversation updateClearedFromPostPayloadEvent:event];
    }
    
    // Self generated messages shouldn't generate unread dots
    [conversation updateLastReadFromPostPayloadEvent:event];
}

- (BOOL)isSelfConversationEvent:(ZMUpdateEvent *)event;
{
    NSUUID * const conversationID = event.conversationUUID;
    return [conversationID isSelfConversationRemoteIdentifierInContext:self.managedObjectContext];
}

- (void)createConversationFromEvent:(ZMUpdateEvent *)event {
    NSDictionary *payloadData = [event.payload dictionaryForKey:@"data"];
    if(payloadData == nil) {
        ZMLogError(@"Missing conversation payload in ZMUpdateEventConversationCreate");
        return;
    }
    NSDate *serverTimestamp = [event.payload dateForKey:@"time"];
    [self createConversationFromTransportData:payloadData serverTimeStamp:serverTimestamp];
}

- (void)processEvents:(NSArray<ZMUpdateEvent *> *)events
           liveEvents:(BOOL)liveEvents
       prefetchResult:(ZMFetchRequestBatchResult *)prefetchResult;
{
    for(ZMUpdateEvent *event in events) {
        
        if (event.type == ZMUpdateEventConversationCreate) {
            [self createConversationFromEvent:event];
            continue;
        }
        
        if ([self isSelfConversationEvent:event]) {
            continue;
        }
        
        ZMConversation *conversation = [self conversationFromEventPayload:event
                                                          conversationMap:prefetchResult.conversationsByRemoteIdentifier];
        if (conversation == nil) {
            continue;
        }
        [self markConversationForDownloadIfNeeded:conversation afterEvent:event];
        
        if (![self shouldProcessUpdateEvent:event]) {
            continue;
        }
        NSDate * const currentLastTimestamp = conversation.lastServerTimeStamp;
        [self updatePropertiesOfConversation:conversation fromEvent:event];
        
        if (liveEvents) {
            [self processUpdateEvent:event forConversation:conversation previousLastServerTimestamp:currentLastTimestamp];
        }
    }
}

- (NSSet<NSUUID *> *)conversationRemoteIdentifiersToPrefetchToProcessEvents:(NSArray<ZMUpdateEvent *> *)events
{
    return [NSSet setWithArray:[events mapWithBlock:^NSUUID *(ZMUpdateEvent *event) {
        return [event.payload optionalUuidForKey:@"conversation"];
    }]];
}


- (void)markConversationForDownloadIfNeeded:(ZMConversation *)conversation afterEvent:(ZMUpdateEvent *)event {
    
    switch(event.type) {
        case ZMUpdateEventConversationOtrAssetAdd:
        case ZMUpdateEventConversationOtrMessageAdd:
        case ZMUpdateEventConversationRename:
        case ZMUpdateEventConversationMemberLeave:
        case ZMUpdateEventConversationKnock:
        case ZMUpdateEventConversationMessageAdd:
        case ZMUpdateEventConversationTyping:
        case ZMUpdateEventConversationAssetAdd:
        case ZMUpdateEventConversationClientMessageAdd:
            break;
        default:
            return;
    }
    
    BOOL isConnection = conversation.connection.status == ZMConnectionStatusPending
        || conversation.connection.status == ZMConnectionStatusSent
        || conversation.conversationType == ZMConversationTypeConnection; // the last OR should be covered by the
                                                                      // previous cases already, but just in case..
    if (isConnection || conversation.conversationType == ZMConversationTypeInvalid) {
        conversation.needsToBeUpdatedFromBackend = YES;
        conversation.connection.needsToBeUpdatedFromBackend = YES;
    }
}

- (void)processUpdateEvent:(ZMUpdateEvent *)event forConversation:(ZMConversation *)conversation previousLastServerTimestamp:(NSDate *)previousLastServerTimestamp
{
    switch (event.type) {
        case ZMUpdateEventConversationRename: {
            [self processConversationRenameEvent:event forConversation:conversation];
            break;
        }
        case ZMUpdateEventConversationMemberJoin:
        {
            [self processMemberJoinEvent:event forConversation:conversation];
            break;
        }
        case ZMUpdateEventConversationMemberLeave:
        {
            [self processMemberLeaveEvent:event forConversation:conversation];
            break;
        }
        case ZMUpdateEventConversationMemberUpdate:
        {
            [self processMemberUpdateEvent:event forConversation:conversation previousLastServerTimeStamp:previousLastServerTimestamp];
            break;
        }
        case ZMUpdateEventConversationConnectRequest:
        {
            [self appendSystemMessageForUpdateEvent:event inConversation:conversation];
            break;
        }
        default: {
            break;
        }
    }
}

- (void)processConversationRenameEvent:(ZMUpdateEvent *)event forConversation:(ZMConversation *)conversation
{
    NSDictionary *data = [event.payload dictionaryForKey:@"data"];
    NSString *newName = [data stringForKey:@"name"];
    
    if (![conversation.userDefinedName isEqualToString:newName] || [conversation.modifiedKeys containsObject:ZMConversationUserDefinedNameKey]) {
        [self appendSystemMessageForUpdateEvent:event inConversation:conversation];
    }
    
    conversation.userDefinedName = newName;
}

- (void)processMemberJoinEvent:(ZMUpdateEvent *)event forConversation:(ZMConversation *)conversation
{
    NSSet *users = [event usersFromUserIDsInManagedObjectContext:self.managedObjectContext createIfNeeded:YES];
    
    ZMUser *selfUser = [ZMUser selfUserInContext:self.managedObjectContext];
    
    if (![users isSubsetOfSet:conversation.activeParticipants.set]
        || (selfUser && [users intersectsSet:[NSSet setWithObject:selfUser]])
        || [conversation.modifiedKeys intersectsSet:[NSSet setWithObjects:ZMConversationIsSelfAnActiveMemberKey, ZMConversationUnsyncedActiveParticipantsKey, nil]])
    {
        [self appendSystemMessageForUpdateEvent:event inConversation:conversation];
    }
    
    for (ZMUser *user in users) {
        [conversation internalAddParticipants:[NSSet setWithObject:user] isAuthoritative:YES];
        [conversation synchronizeAddedUser:user];
    }
}

- (void)processMemberLeaveEvent:(ZMUpdateEvent *)event forConversation:(ZMConversation *)conversation
{
    NSUUID *senderUUID = event.senderUUID;
    ZMUser *sender = [ZMUser userWithRemoteID:senderUUID createIfNeeded:YES inContext:self.managedObjectContext];
    NSSet *users = [event usersFromUserIDsInManagedObjectContext:self.managedObjectContext createIfNeeded:YES];
    
    if ([users intersectsSet:conversation.activeParticipants.set] || [conversation.modifiedKeys intersectsSet:[NSSet setWithObjects:ZMConversationIsSelfAnActiveMemberKey, ZMConversationUnsyncedInactiveParticipantsKey, nil]]) {
        [self appendSystemMessageForUpdateEvent:event inConversation:conversation];
    }

    for (ZMUser *user in users) {
        [conversation internalRemoveParticipants:[NSSet setWithObject:user] sender:sender];
        [conversation synchronizeRemovedUser:user];
    }
}

- (void)processMemberUpdateEvent:(ZMUpdateEvent *)event forConversation:(ZMConversation *)conversation previousLastServerTimeStamp:(NSDate *)previousLastServerTimestamp
{
    NSDictionary *dataPayload = [event.payload.asDictionary dictionaryForKey:@"data"];
 
    if(dataPayload) {
        [conversation updateSelfStatusFromDictionary:dataPayload
                                           timeStamp:event.timeStamp
                         previousLastServerTimeStamp:previousLastServerTimestamp];
    }
}

- (void)appendSystemMessageForUpdateEvent:(ZMUpdateEvent *)event inConversation:(ZMConversation *)conversation
{
    ZMSystemMessage *systemMessage = [ZMSystemMessage createOrUpdateMessageFromUpdateEvent:event inManagedObjectContext:self.managedObjectContext];
    
    if (systemMessage != nil) {
        [self.localNotificationDispatcher processMessage:systemMessage];
        [conversation resortMessagesWithUpdatedMessage:systemMessage];
    }
}

@end



@implementation ZMConversationTranscoder (UpstreamTranscoder)

- (BOOL)shouldProcessUpdatesBeforeInserts;
{
    return NO;
}


- (ZMUpstreamRequest *)requestForUpdatingObject:(ZMConversation *)updatedConversation forKeys:(NSSet *)keys;
{
    ZMUpstreamRequest *request = nil;
    if([keys containsObject:ZMConversationUserDefinedNameKey]) {
        request = [self requestForUpdatingUserDefinedNameInConversation:updatedConversation];
    }
    if (request == nil && [keys containsObject:ZMConversationUnsyncedInactiveParticipantsKey]) {
        request = [self requestForUpdatingUnsyncedInactiveParticipantsInConversation:updatedConversation];
    }
    if (request == nil && [keys containsObject:ZMConversationUnsyncedActiveParticipantsKey]) {
        request = [self requestForUpdatingUnsyncedActiveParticipantsInConversation:updatedConversation];
    }
    if (request == nil && (   [keys containsObject:ZMConversationArchivedChangedTimeStampKey]
                           || [keys containsObject:ZMConversationSilencedChangedTimeStampKey])) {
        request = [self requestForUpdatingConversationSelfInfo:updatedConversation];
    }
    if (request == nil && [keys containsObject:ZMConversationIsSelfAnActiveMemberKey] && ! updatedConversation.isSelfAnActiveMember) {
        request = [self requestForLeavingConversation:updatedConversation];
    }
    if (request == nil) {
        ZMTrapUnableToGenerateRequest(keys, self);
    }
    return request;
}

- (ZMUpstreamRequest *)requestForLeavingConversation:(ZMConversation *)conversation
{
    ZMUser *selfUser = [ZMUser selfUserInContext:self.managedObjectContext];
    RequireString(conversation.remoteIdentifier != nil, "ZMConversationTranscoder refuses request to leave conversation - conversation remoteID is nil");
    RequireString(selfUser.remoteIdentifier != nil, "ZMConversationTranscoder refuses request to leave conversation - selfUser remoteID is nil");
    
    NSString *path = [NSString pathWithComponents:@[ ConversationsPath, conversation.remoteIdentifier.transportString, @"members", selfUser.remoteIdentifier.transportString]];
    ZMTransportRequest *request = [ZMTransportRequest requestWithPath:path method:ZMMethodDELETE payload:nil];
    return [[ZMUpstreamRequest alloc] initWithKeys:[NSSet setWithObject:ZMConversationIsSelfAnActiveMemberKey] transportRequest:request userInfo:nil];
}

- (ZMUpstreamRequest *)requestForUpdatingUnsyncedActiveParticipantsInConversation:(ZMConversation *)conversation
{
    NSOrderedSet *unsyncedUserIDs = [conversation.unsyncedActiveParticipants mapWithBlock:^NSString*(ZMUser *unsyncedUser) {
        return unsyncedUser.remoteIdentifier.transportString;
    }];
    
    if (unsyncedUserIDs.count == 0) {
        return nil;
    }
    
    NSString *path = [NSString pathWithComponents:@[ ConversationsPath, conversation.remoteIdentifier.transportString, @"members" ]];
    NSDictionary *payload = @{
                              @"users": unsyncedUserIDs.array,
                              };
    
    ZMTransportRequest *request = [ZMTransportRequest requestWithPath:path method:ZMMethodPOST payload:payload];
    [request expireAfterInterval:ZMTransportRequestDefaultExpirationInterval];
    NSDictionary *userInfo = @{ UserInfoTypeKey : UserInfoAddedValueKey, UserInfoUserKey : conversation.unsyncedActiveParticipants };
    return [[ZMUpstreamRequest alloc] initWithKeys:[NSSet setWithObject:ZMConversationUnsyncedActiveParticipantsKey] transportRequest:request userInfo:userInfo];
}

- (ZMUpstreamRequest *)requestForUpdatingUnsyncedInactiveParticipantsInConversation:(ZMConversation *)conversation
{
    ZMUser *unsyncedUser = conversation.unsyncedInactiveParticipants.firstObject;
    
    if (unsyncedUser == nil) {
        return nil;
    }
    
    NSString *path = [NSString pathWithComponents:@[ ConversationsPath, conversation.remoteIdentifier.transportString, @"members", unsyncedUser.remoteIdentifier.transportString ]];
    
    ZMTransportRequest *request = [ZMTransportRequest requestWithPath:path method:ZMMethodDELETE payload:nil];
    [request expireAfterInterval:ZMTransportRequestDefaultExpirationInterval];
    NSDictionary *userInfo = @{ UserInfoTypeKey : UserInfoRemovedValueKey, UserInfoUserKey : unsyncedUser };
    return [[ZMUpstreamRequest alloc] initWithKeys:[NSSet setWithObject:ZMConversationUnsyncedInactiveParticipantsKey] transportRequest:request userInfo:userInfo];
}


- (ZMUpstreamRequest *)requestForUpdatingUserDefinedNameInConversation:(ZMConversation *)conversation
{
    NSDictionary *payload = @{ @"name" : conversation.userDefinedName };
    NSString *lastComponent = conversation.remoteIdentifier.transportString;
    Require(lastComponent != nil);
    NSString *path = [NSString pathWithComponents:@[ConversationsPath, lastComponent]];
    ZMTransportRequest *request = [ZMTransportRequest requestWithPath:path method:ZMMethodPUT payload:payload];

    [request expireAfterInterval:ZMTransportRequestDefaultExpirationInterval];
    return [[ZMUpstreamRequest alloc] initWithKeys:[NSSet setWithObject:ZMConversationUserDefinedNameKey] transportRequest:request userInfo:nil];
}

- (ZMUpstreamRequest *)requestForUpdatingConversationSelfInfo:(ZMConversation *)conversation
{
    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    NSMutableSet *updatedKeys = [NSMutableSet set];
    
    if ([conversation hasLocalModificationsForKey:ZMConversationSilencedChangedTimeStampKey]) {
        if( conversation.silencedChangedTimestamp == nil) {
            conversation.silencedChangedTimestamp = [NSDate date];
        }
        payload[ZMConversationInfoOTRMutedValueKey] = @(conversation.isSilenced);
        payload[ZMConversationInfoOTRMutedReferenceKey] = [conversation.silencedChangedTimestamp transportString];
        [updatedKeys addObject:ZMConversationSilencedChangedTimeStampKey];
    }
    
    if ([conversation hasLocalModificationsForKey:ZMConversationArchivedChangedTimeStampKey]) {
        if (conversation.archivedChangedTimestamp == nil) {
            conversation.archivedChangedTimestamp = [NSDate date];
        }
        
        payload[ZMConversationInfoOTRArchivedValueKey] = @(conversation.isArchived);
        payload[ZMConversationInfoOTRArchivedReferenceKey] = [conversation.archivedChangedTimestamp transportString];
        [updatedKeys addObject:ZMConversationArchivedChangedTimeStampKey];
    }
    
    if (updatedKeys.count == 0) {
        return nil;
    }
    
    NSString *path = [NSString pathWithComponents:@[ConversationsPath, conversation.remoteIdentifier.transportString, @"self"]];
    ZMTransportRequest *request = [ZMTransportRequest requestWithPath:path method:ZMMethodPUT payload:payload];
    return [[ZMUpstreamRequest alloc] initWithKeys:updatedKeys transportRequest:request userInfo:nil];
}


- (ZMUpstreamRequest *)requestForInsertingObject:(ZMManagedObject *)managedObject forKeys:(NSSet *)keys;
{
    NOT_USED(keys);
    
    ZMTransportRequest *request = nil;
    ZMConversation *insertedConversation = (ZMConversation *) managedObject;
    
    NSArray *participantUUIDs = [[insertedConversation.otherActiveParticipants array] mapWithBlock:^id(ZMUser *user) {
        return [user.remoteIdentifier transportString];
    }];
    
    NSMutableDictionary *payload = [@{ @"users" : participantUUIDs } mutableCopy];
    if(insertedConversation.userDefinedName != nil) {
        payload[@"name"] = insertedConversation.userDefinedName;
    }

    if (insertedConversation.team.remoteIdentifier != nil) {
        payload[ConversationTeamKey] = @{
                             ConversationTeamIdKey: insertedConversation.team.remoteIdentifier.transportString,
                             ConversationTeamManagedKey: @NO // FIXME:
                             };
    }
    
    request = [ZMTransportRequest requestWithPath:ConversationsPath method:ZMMethodPOST payload:payload];
    return [[ZMUpstreamRequest alloc] initWithTransportRequest:request];
}


- (void)updateInsertedObject:(ZMManagedObject *)managedObject request:(ZMUpstreamRequest *__unused)upstreamRequest response:(ZMTransportResponse *)response
{
    ZMConversation *insertedConversation = (ZMConversation *)managedObject;
    NSUUID *remoteID = [response.payload.asDictionary uuidForKey:@"id"];
    
    // check if there is another with the same conversation ID
    if (remoteID != nil) {
        ZMConversation *existingConversation = [ZMConversation conversationWithRemoteID:remoteID createIfNeeded:NO inContext:self.managedObjectContext];
        
        if (existingConversation != nil) {
            [self.managedObjectContext deleteObject:existingConversation];
            insertedConversation.needsToBeUpdatedFromBackend = YES;
        }
    }
    insertedConversation.remoteIdentifier = remoteID;
    [insertedConversation updateWithTransportData:response.payload.asDictionary serverTimeStamp:nil];
}

- (ZMUpdateEvent *)conversationEventWithKeys:(NSSet *)keys responsePayload:(id<ZMTransportData>)payload;
{
    NSSet *keysThatGenerateEvents = [NSSet setWithObjects:ZMConversationUserDefinedNameKey,
                                     ZMConversationUnsyncedInactiveParticipantsKey,
                                     ZMConversationUnsyncedActiveParticipantsKey,
                                     ZMConversationIsSelfAnActiveMemberKey,
                                     nil];
    if (! [keys intersectsSet:keysThatGenerateEvents]) {
        return nil;
        
    }
    ZMUpdateEvent *event = [ZMUpdateEvent eventFromEventStreamPayload:payload uuid:nil];
    return event;
}


- (BOOL)updateUpdatedObject:(ZMConversation *)conversation
            requestUserInfo:(NSDictionary *)userInfo
                   response:(ZMTransportResponse *)response
                keysToParse:(NSSet *)keysToParse
{
    ZMUpdateEvent *event = [self conversationEventWithKeys:keysToParse responsePayload:response.payload];
    if (event != nil) {
        [self updatePropertiesOfConversation:conversation withPostPayloadEvent:event];
        [self processEvents:@[event] liveEvents:YES prefetchResult:nil];
    }
    
    if ([keysToParse isEqualToSet:[NSSet setWithObject:ZMConversationUserDefinedNameKey]]) {
        return NO;
    }
    
    // When participants change, we need to update them based on userInfo, not 'keysToParse'.
    // 'keysToParse' will not contain the participants if they've changed in the meantime, but
    // we need to parse the result anyway.
    NSString * const changeType = userInfo[UserInfoTypeKey];
    BOOL const addedUsers = ([changeType isEqualToString:UserInfoAddedValueKey]);
    BOOL const removedUsers = ([changeType isEqualToString:UserInfoRemovedValueKey]);
    
    if (addedUsers || removedUsers) {
        BOOL needsAnotherRequest = NO;
        if (removedUsers) {
            ZMUser *syncedUser = userInfo[UserInfoUserKey];
            [conversation synchronizeRemovedUser:syncedUser];
            
            needsAnotherRequest = conversation.unsyncedInactiveParticipants.count > 0;
        }
        else if (addedUsers) {
            NSMutableOrderedSet *syncedUsers = userInfo[UserInfoUserKey];
            
            for (ZMUser *syncedUser in syncedUsers) {
                [conversation synchronizeAddedUser:syncedUser];
            }
            
            needsAnotherRequest = NO; // 1 TODO What happens if participants are changed while being updated?
        }
        
        // Reset keys
        if (! needsAnotherRequest && [keysToParse containsObject:ZMConversationUnsyncedInactiveParticipantsKey]) {
            [conversation resetLocallyModifiedKeys:[NSSet setWithObject:ZMConversationUnsyncedInactiveParticipantsKey]];
        }
        if (! needsAnotherRequest && [keysToParse containsObject:ZMConversationUnsyncedActiveParticipantsKey]) {
            [conversation resetLocallyModifiedKeys:[NSSet setWithObject:ZMConversationUnsyncedActiveParticipantsKey]];
        }
        
        return needsAnotherRequest;
    }
    if( keysToParse == nil ||
       [keysToParse isEmpty] ||
       [keysToParse containsObject:ZMConversationSilencedChangedTimeStampKey] ||
       [keysToParse containsObject:ZMConversationArchivedChangedTimeStampKey] ||
       [keysToParse containsObject:ZMConversationIsSelfAnActiveMemberKey])
    {
        return NO;
    }
    ZMLogError(@"Unknown changed keys in request. keys: %@  payload: %@  userInfo: %@", keysToParse, response.payload, userInfo);
    return NO;
}

- (ZMManagedObject *)objectToRefetchForFailedUpdateOfObject:(ZMManagedObject *)managedObject;
{
    if([managedObject isKindOfClass:ZMConversation.class]) {
        return managedObject;
    }
    return nil;
}

- (void)requestExpiredForObject:(ZMConversation *)conversation forKeys:(NSSet *)keys
{
    NOT_USED(keys);
    conversation.needsToBeUpdatedFromBackend = YES;
    [self resetModifiedKeysWithoutReferenceInConversation:conversation];
}

- (BOOL)shouldCreateRequestToSyncObject:(ZMManagedObject *)managedObject forKeys:(NSSet<NSString *> * __unused)keys  withSync:(id)sync;
{
    if (sync == self.downstreamSync || sync == self.insertedSync) {
        return YES;
    }
    // This is our chance to reset keys that should not be set - instead of crashing when we create a request.
    ZMConversation *conversation = (ZMConversation *)managedObject;
    NSMutableSet *remainingKeys = [NSMutableSet setWithSet:keys];
    
    if ([conversation hasLocalModificationsForKey:ZMConversationUserDefinedNameKey] && !conversation.userDefinedName) {
        [conversation resetLocallyModifiedKeys:[NSSet setWithObject:ZMConversationUserDefinedNameKey]];
        [remainingKeys removeObject:ZMConversationUserDefinedNameKey];
    }
    if ([conversation hasLocalModificationsForKey:ZMConversationUnsyncedActiveParticipantsKey] && conversation.unsyncedActiveParticipants.count == 0) {
        [conversation resetLocallyModifiedKeys:[NSSet setWithObject:ZMConversationUnsyncedActiveParticipantsKey]];
        [remainingKeys removeObject:ZMConversationUnsyncedActiveParticipantsKey];
    }
    if ([conversation hasLocalModificationsForKey:ZMConversationUnsyncedInactiveParticipantsKey] && conversation.unsyncedInactiveParticipants.count == 0) {
        [conversation resetLocallyModifiedKeys:[NSSet setWithObject:ZMConversationUnsyncedInactiveParticipantsKey]];
        [remainingKeys removeObject:ZMConversationUnsyncedInactiveParticipantsKey];
    }
    if ([conversation hasLocalModificationsForKey:ZMConversationIsSelfAnActiveMemberKey] && conversation.isSelfAnActiveMember) {
        [conversation resetLocallyModifiedKeys:[NSSet setWithObject:ZMConversationIsSelfAnActiveMemberKey]];
        [remainingKeys removeObject:ZMConversationIsSelfAnActiveMemberKey];
    }
    if (remainingKeys.count < keys.count) {
        [(id<ZMContextChangeTracker>)sync objectsDidChange:[NSSet setWithObject:conversation]];
        [self.managedObjectContext enqueueDelayedSave];
    }
    return (remainingKeys.count > 0);
}

- (BOOL)shouldRetryToSyncAfterFailedToUpdateObject:(ZMConversation *)conversation request:(ZMUpstreamRequest *__unused)upstreamRequest response:(ZMTransportResponse *__unused)response keysToParse:(NSSet * __unused)keys
{
    if (conversation.remoteIdentifier) {
        conversation.needsToBeUpdatedFromBackend = YES;
        [self resetModifiedKeysWithoutReferenceInConversation:conversation];
        [self.downstreamSync objectsDidChange:[NSSet setWithObject:conversation]];
    }
    
    return NO;
}

/// Resets all keys that don't have a time reference and would possibly be changed with refetching of the conversation from the BE
- (void)resetModifiedKeysWithoutReferenceInConversation:(ZMConversation*)conversation
{
    [conversation resetParticipantsBackToLastServerSync];
    [conversation resetLocallyModifiedKeys:[NSSet setWithArray:self.keysToSyncWithoutRef]];
    
    // since we reset all keys, we should make sure to remove the object from the modifiedSync
    // it might otherwise try to sync remaining keys
    [self.modifiedSync objectsDidChange:[NSSet setWithObject:conversation]];
}

@end



@implementation ZMConversationTranscoder (DownstreamTranscoder)

- (ZMTransportRequest *)requestForFetchingObject:(ZMConversation *)conversation downstreamSync:(id<ZMObjectSync>)downstreamSync;
{
    NOT_USED(downstreamSync);
    if (conversation.remoteIdentifier == nil) {
        return nil;
    }
    
    NSString *path = [NSString pathWithComponents:@[ConversationsPath, conversation.remoteIdentifier.transportString]];
    ZMTransportRequest *request = [[ZMTransportRequest alloc] initWithPath:path method:ZMMethodGET payload:nil];
    return request;
}

- (void)updateObject:(ZMConversation *)conversation withResponse:(ZMTransportResponse *)response downstreamSync:(id<ZMObjectSync>)downstreamSync;
{
    NOT_USED(downstreamSync);
    conversation.needsToBeUpdatedFromBackend = NO;
    [self resetModifiedKeysWithoutReferenceInConversation:conversation];
    
    NSDictionary *dictionaryPayload = [response.payload asDictionary];
    VerifyReturn(dictionaryPayload != nil);
    [conversation updateWithTransportData:dictionaryPayload serverTimeStamp:nil];
}

- (void)deleteObject:(ZMConversation *)conversation withResponse:(ZMTransportResponse *)response downstreamSync:(id<ZMObjectSync>)downstreamSync;
{
    if (response.isPermanentylUnavailableError) {
        conversation.needsToBeUpdatedFromBackend = NO;
    }
    NOT_USED(downstreamSync);
}

@end


@implementation ZMConversationTranscoder (PaginatedRequest)

- (NSUInteger)maximumRemoteIdentifiersPerRequestForObjectSync:(ZMRemoteIdentifierObjectSync *)sync;
{
    NOT_USED(sync);
    return self.conversationPageSize;
}


- (ZMTransportRequest *)requestForObjectSync:(ZMRemoteIdentifierObjectSync *)sync remoteIdentifiers:(NSSet *)identifiers;
{
    NOT_USED(sync);
    
    NSArray *currentBatchOfConversationIDs = [[identifiers allObjects] mapWithBlock:^id(NSUUID *obj) {
        return obj.transportString;
    }];
    NSString *path = [NSString stringWithFormat:@"%@?ids=%@", ConversationsPath, [currentBatchOfConversationIDs componentsJoinedByString:@","]];

    return [[ZMTransportRequest alloc] initWithPath:path method:ZMMethodGET payload:nil];
}


- (void)didReceiveResponse:(ZMTransportResponse *)response remoteIdentifierObjectSync:(ZMRemoteIdentifierObjectSync *)sync forRemoteIdentifiers:(NSSet *)remoteIdentifiers;
{
    NOT_USED(sync);
    NOT_USED(remoteIdentifiers);
    NSDictionary *payload = [response.payload asDictionary];
    NSArray *conversations = [payload arrayForKey:@"conversations"];
    
    for (NSDictionary *rawConversation in [conversations asDictionaries]) {
        ZMConversation *conv = [self createConversationFromTransportData:rawConversation serverTimeStamp:nil];
        conv.needsToBeUpdatedFromBackend = NO;
    }
    
    if (response.result == ZMTransportResponseStatusPermanentError && self.isSyncing) {
        [self.syncStatus failCurrentSyncPhaseWithPhase:self.expectedSyncPhase];
    }
    
    [self finishSyncIfCompleted];
}

@end
