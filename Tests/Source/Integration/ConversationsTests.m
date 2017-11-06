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

@import WireDataModel;
@import WireSyncEngine;
@import WireTransport;
@import WireMockTransport;
@import WireUtilities;
@import WireTesting;

#import "MessagingTest.h"
#import "ZMUserSession.h"
#import "ZMUserSession+Internal.h"
#import "ZMConversationTranscoder+Internal.h"
#import <WireSyncEngine/WireSyncEngine-Swift.h>
#import "ConversationTestsBase.h"
#import "WireSyncEngine_iOS_Tests-Swift.h"


@interface ZMConversationList (ObjectIDs)

@end

@implementation ZMConversationList (ObjectIDs)

- (NSArray <NSManagedObjectID *> *)objectIDs {
    return [self mapWithBlock:^NSManagedObjectID *(ZMConversation *conversation) {
        return conversation.objectID;
    }];
}

@end


@interface ConversationTests : ConversationTestsBase

@property (nonatomic) NSUInteger previousZMConversationTranscoderListPageSize;

@end


#pragma mark - Conversation tests
@implementation ConversationTests

- (void)testThatItCallsInitialSyncDone
{
    XCTAssertTrue([self login]);
}

- (void)testThatAConversationIsResyncedAfterRestartingFromScratch
{
    NSString *conversationName = @"My conversation";
    {
        // Create a UI context
        XCTAssertTrue([self login]);
        // Get the users:
        ZMUser *user1 = [self userForMockUser:self.user1];
        XCTAssertNotNil(user1);
        ZMUser *user2 = [self userForMockUser:self.user2];
        XCTAssertNotNil(user2);
        
        // Create a conversation
        __block ZMConversation *conversation;
        [self.userSession performChanges:^{
            conversation = [ZMConversation insertGroupConversationIntoUserSession:self.userSession withParticipants:@[user1, user2] inTeam:nil];
            conversation.userDefinedName = conversationName;
        }];
        
        // Wait for merge ui->sync to be done
        WaitForAllGroupsToBeEmpty(0.5);
        XCTAssert([self waitOnMainLoopUntilBlock:^BOOL{
            return conversation.lastModifiedDate != nil;
        } timeout:0.5]);
    }
    
    // Tears down context(s) &
    // Re-create contexts
    [self recreateSessionManagerAndDeleteLocalData];

    {
        // Wait for sync to be done
        XCTAssertTrue([self login]);
        
        // Check that conversation is there
        ZMConversation *conversation = [[ZMConversationList conversationsInUserSession:self.userSession] firstObjectMatchingWithBlock:^BOOL(ZMConversation *c) {
            return [c.userDefinedName isEqual:conversationName];
        }];
        XCTAssertNotNil(conversation);
    }
}


- (void)testThatChangeToAConversationNameIsResyncedAfterRestartingFromScratch;
{
    NSString *name = @"My New Name";
    {
        // Create a UI context
        XCTAssertTrue([self login]);
        // Get the group conversation
        ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
        XCTAssertNotNil(conversation);
        // Change the name & save
        conversation.userDefinedName = name;
        [self.userSession saveOrRollbackChanges];
        XCTAssertFalse(conversation.hasChanges, @"Rollback?");
        XCTAssertTrue([conversation hasLocalModificationsForKey:ZMConversationUserDefinedNameKey]);
        
        // Wait for merge ui->sync to be done
        WaitForAllGroupsToBeEmpty(0.5);
        
        XCTAssertFalse([conversation hasLocalModificationsForKey:ZMConversationUserDefinedNameKey]);
    }
    
    // Tears down context(s) &
    // Re-create contexts
    [self recreateSessionManagerAndDeleteLocalData];
    
    // Wait for sync to be done
    XCTAssertTrue([self login]);
    
    // Check that conversation name is updated:
    {
        // Get the group conversation
        ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
        XCTAssertEqualObjects(conversation.userDefinedName, name);
    }
}

- (void)testThatChangeToAConversationNameIsNotResyncedIfNil;
{
    ZMConversation *conversation = nil;
    
    NSString *name = nil;
    NSString *formerName = nil;
    {
        // Create a UI context
        XCTAssertTrue([self login]);
        // Get the group conversation
        [self.mockTransportSession resetReceivedRequests];
        conversation = [self conversationForMockConversation:self.groupConversation];
        
        XCTAssertNotNil(conversation);
        // Change the name & save
        formerName = conversation.userDefinedName;
        conversation.userDefinedName = name;
        [self.userSession saveOrRollbackChanges];
        XCTAssertFalse(conversation.hasChanges, @"Rollback?");
        XCTAssertTrue([conversation hasLocalModificationsForKey:ZMConversationUserDefinedNameKey]);
        
        // Wait for merge ui->sync to be done
        WaitForAllGroupsToBeEmpty(0.5);
        ZMConversation *syncConversation = [self.userSession.syncManagedObjectContext objectWithID:conversation.objectID];
        
        XCTAssertFalse([syncConversation hasLocalModificationsForKey:ZMConversationUserDefinedNameKey]);
        XCTAssertFalse([conversation hasLocalModificationsForKey:ZMConversationUserDefinedNameKey]);
        XCTAssertEqual(self.mockTransportSession.receivedRequests.count, 0lu);
    }
    
    // Tears down context(s) &
    // Re-create contexts
    [self recreateSessionManagerAndDeleteLocalData];
    
    // Wait for sync to be done
    XCTAssertTrue([self login]);
    
    // Check that conversation name is updated:
    {
        // Get the group conversation
        conversation = [self conversationForMockConversation:self.groupConversation];
        XCTAssertEqualObjects(conversation.userDefinedName, formerName);
    }
}


- (void)testThatRemovingParticipantsFromAConversationIsSynchronizedWithBackend
{
    {
        XCTAssertTrue([self login]);
        
        ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
        XCTAssertNotNil(conversation);
        
        ZMUser *user = [self userForMockUser:self.user3];
        
        XCTAssertTrue([conversation.activeParticipants containsObject:user]);
        [self.userSession performChanges:^{
            [conversation removeParticipant:user];

        }];
        XCTAssertFalse([conversation.activeParticipants containsObject:user]);

        // Wait for merge ui->sync to be done
        WaitForAllGroupsToBeEmpty(0.5);
    }

    // Tears down context(s) &
    // Re-create contexts
    [self recreateSessionManagerAndDeleteLocalData];
    XCTAssert([self login]);
    
    {
        ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
        XCTAssertNotNil(conversation);
        ZMUser *user = [self userForMockUser:self.user3];

        XCTAssertFalse([conversation.activeParticipants containsObject:user]);
    }
    
}



- (void)testThatAddingParticipantsToAConversationIsSynchronizedWithBackend
{

    __block MockUser *connectedUserNotInConv;
    {
        [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
            connectedUserNotInConv = [session insertUserWithName:@"Connected user which originally is not in conversation"];
            connectedUserNotInConv.email = @"connectedUserNotInConv@example.com";
            connectedUserNotInConv.phone = @"23498579";
            
            MockConversation *selfToConnectedNotInConvConversation = [session insertOneOnOneConversationWithSelfUser:self.selfUser otherUser:connectedUserNotInConv];
            selfToConnectedNotInConvConversation.creator = self.selfUser;
            
            MockConnection *connectionSelfToConnectedUserNotInConv = [session insertConnectionWithSelfUser:self.selfUser toUser:connectedUserNotInConv];
            connectionSelfToConnectedUserNotInConv.status = @"accepted";
            connectionSelfToConnectedUserNotInConv.lastUpdate = [NSDate dateWithTimeIntervalSinceNow:-3];
            connectionSelfToConnectedUserNotInConv.conversation = selfToConnectedNotInConvConversation;
        }];
        
        XCTAssertTrue([self login]);
        
        ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
        XCTAssertNotNil(conversation);
        
        ZMUser *user = [self userForMockUser:connectedUserNotInConv];
        
        XCTAssertFalse([conversation.activeParticipants containsObject:user]);
        [self.userSession performChanges:^{
            [conversation addParticipant:user];
        }];
        XCTAssertTrue([conversation.activeParticipants containsObject:user]);
        
        // Wait for merge ui->sync to be done
        WaitForAllGroupsToBeEmpty(0.5);
    }
    
    // Tears down context(s) &
    // Re-create contexts
    [self recreateSessionManagerAndDeleteLocalData];
    XCTAssert([self login]);
        
    {
        ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
        XCTAssertNotNil(conversation);
        
        ZMUser *user = [self userForMockUser:connectedUserNotInConv];
        
        XCTAssertTrue([conversation.activeParticipants containsObject:user]);
    }
    
}

@end

@implementation ConversationTests (DisplayName)

- (void)testThatReceivingAPushEventForNameChangeChangesTheConversationName
{
    
    // given
    // Create a UI context
    XCTAssertTrue([self login]);
    // Get the group conversation
    ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
    XCTAssertNotNil(conversation);
    XCTAssertEqualObjects(conversation.userDefinedName, @"Group conversation");
    
    // when
    NSString *newConversationName = @"New Conversation Name";

    ConversationChangeObserver *observer = [[ConversationChangeObserver alloc] initWithConversation:conversation];
    [observer clearNotifications];
    
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> * ZM_UNUSED session) {
        [self.groupConversation changeNameByUser:self.user3 name:newConversationName];
    }];
    
    // then
    XCTAssertTrue([self waitOnMainLoopUntilBlock:^BOOL{
        return observer.notifications.count >= 1;
    } timeout:0.5]);
    
    XCTAssertEqualObjects(conversation.userDefinedName, newConversationName);
}

@end


#pragma mark - Participants
@implementation ConversationTests (Participants)

- (void)testThatParticipantsAreAddedToAConversationWhenTheyAreAddedRemotely
{
    // given
    XCTAssertTrue([self login]);
    
    ZMConversation *groupConversation = [self conversationForMockConversation:self.groupConversation];
    XCTAssertNotNil(groupConversation);
    
    // when
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [self.groupConversation addUsersByUser:session.selfUser addedUsers:@[self.user4]];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    ZMUser *user4 = [self userForMockUser:self.user4];
    XCTAssertTrue([groupConversation.activeParticipants containsObject:user4]);
    XCTAssertEqual(groupConversation.keysThatHaveLocalModifications.count, 0u);
}

- (void)testThatParticipantsAreRemovedFromAConversationWhenTheyAreRemovedRemotely
{
    // given
    XCTAssertTrue([self login]);
    
    ZMUser *user3 = [self userForMockUser:self.user3];
    ZMConversation *groupConversation = [self conversationForMockConversation:self.groupConversation];
    XCTAssertNotNil(groupConversation);
    XCTAssertTrue([groupConversation.activeParticipants containsObject:user3]);
    
    // when
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [self.groupConversation removeUsersByUser:session.selfUser removedUser:self.user3];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertFalse([groupConversation.activeParticipants containsObject:user3]);
    XCTAssertEqual(groupConversation.keysThatHaveLocalModifications.count, 0u);
}


- (void)testThatAddingAndRemovingAParticipantToAConversationSendsOutChangeNotifications
{
    __block MockUser *connectedUserNotInConv;
    {
        [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
            connectedUserNotInConv = [session insertUserWithName:@"Connected user which originally is not in conversation"];
            connectedUserNotInConv.email = @"connectedUserNotInConv@example.com";
            connectedUserNotInConv.phone = @"23498579";
            
            MockConversation *selfToConnectedNotInConvConversation = [session insertOneOnOneConversationWithSelfUser:self.selfUser otherUser:connectedUserNotInConv];
            selfToConnectedNotInConvConversation.creator = self.selfUser;
            
            MockConnection *connectionSelfToConnectedUserNotInConv = [session insertConnectionWithSelfUser:self.selfUser toUser:connectedUserNotInConv];
            connectionSelfToConnectedUserNotInConv.status = @"accepted";
            connectionSelfToConnectedUserNotInConv.lastUpdate = [NSDate dateWithTimeIntervalSinceNow:-3];
            connectionSelfToConnectedUserNotInConv.conversation = selfToConnectedNotInConvConversation;
        }];
        
        XCTAssertTrue([self login]);
        
        ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
        XCTAssertNotNil(conversation);
        
        ZMUser *user = [self userForMockUser:connectedUserNotInConv];
        
        ConversationChangeObserver *observer = [[ConversationChangeObserver alloc] initWithConversation:conversation];
        [observer clearNotifications];
        
        [self.userSession performChanges:^{
            XCTAssertFalse([conversation.activeParticipants containsObject:user]);
            [conversation addParticipant:user];
            XCTAssertTrue([conversation.activeParticipants containsObject:user]);
        }];
        WaitForAllGroupsToBeEmpty(0.5);
        XCTAssertFalse(conversation.hasChanges, @"Rollback?");
        
        // Participants changes and messages changes (System message fot the added user)
        XCTAssertEqual(observer.notifications.count, 2u);
        ConversationChangeInfo *note1 = observer.notifications.firstObject;
        ConversationChangeInfo *note2 = observer.notifications.lastObject;
        XCTAssertEqual(note1.conversation, conversation);
        XCTAssertTrue(note1.participantsChanged);
        XCTAssertEqual(note2.conversation, conversation);
        XCTAssertTrue(note2.messagesChanged);
        [observer.notifications removeAllObjects];
        
        [self.userSession performChanges:^{
            XCTAssertTrue([conversation.activeParticipants containsObject:user]);
            [conversation removeParticipant:user];
            XCTAssertFalse([conversation.activeParticipants containsObject:user]);
        }];
        WaitForAllGroupsToBeEmpty(0.5);
        XCTAssertFalse(conversation.hasChanges, @"Rollback?");
        
        // Participants changes and messages changes (System message fot the added user)
        XCTAssertEqual(observer.notifications.count, 2u);
        ConversationChangeInfo *note3 = observer.notifications.firstObject;
        ConversationChangeInfo *note4 = observer.notifications.lastObject;
        XCTAssertEqual(note3.conversation, conversation);
        XCTAssertTrue(note3.participantsChanged);
        XCTAssertEqual(note4.conversation, conversation);
        XCTAssertTrue(note4.messagesChanged);
        [observer.notifications removeAllObjects];
        
        // Wait for merge ui->sync to be done
        WaitForAllGroupsToBeEmpty(0.5);
        
        XCTAssertFalse([conversation hasLocalModificationsForKey:ZMConversationUnsyncedActiveParticipantsKey]);
    }
}


- (void)testThatWhenLeavingAConversationWeSetAndSynchronizeTheLastReadServerTimestamp
{
    // given
    XCTAssertTrue([self login]);
    
    ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
    XCTAssertNotNil(conversation);
    
    ZMUser *user = [self userForMockUser:self.selfUser];
    
    [self.mockTransportSession resetReceivedRequests];
    
    NSString *lastReadPath = [NSString stringWithFormat:@"/conversations/%@/otr/messages", user.remoteIdentifier.transportString];
    NSString *memberLeavePath = [NSString stringWithFormat:@"/conversations/%@/members/%@", conversation.remoteIdentifier.transportString, user.remoteIdentifier.transportString];
    NSString *archivedPath = [NSString stringWithFormat:@"/conversations/%@/self", conversation.remoteIdentifier.transportString];
    
    __block BOOL didSendLastReadMessage = NO;
    __block BOOL didSendFirstArchivedMessage = NO;
    __block BOOL didSendMemberLeaveRequest = NO;
    __block BOOL didSendSecondArchivedMessage = NO;
    __block NSDate *firstArchivedRef;
    __block BOOL firstIsArchived;
    __block NSDate *secondArchivedRef;
    __block BOOL secondIsArchived;
    ZM_WEAK(self);
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request) {
        ZM_STRONG(self);
        if ([request.path isEqualToString:lastReadPath] && request.method == ZMMethodPOST) {
            didSendLastReadMessage = YES;
        }
        if ([request.path isEqualToString:memberLeavePath] && request.method == ZMMethodDELETE) {
            didSendMemberLeaveRequest = YES;
        }
        if ([request.path isEqualToString:archivedPath] && request.method == ZMMethodPUT) {
            if (!didSendMemberLeaveRequest) {
                didSendFirstArchivedMessage = YES;
                firstArchivedRef = [[request.payload asDictionary] dateForKey:@"otr_archived_ref"];
                firstIsArchived = [request.payload[@"otr_archived"] boolValue];
                XCTAssertEqualObjects(firstArchivedRef, conversation.lastServerTimeStamp);
            } else {
                didSendSecondArchivedMessage = YES;
                secondArchivedRef = [[request.payload asDictionary] dateForKey:@"otr_archived_ref"];
                secondIsArchived = [request.payload[@"otr_archived"] boolValue];
            }
        }
        return nil;
    };
    
    // when
    [self.userSession performChanges:^{
        XCTAssertTrue(conversation.isSelfAnActiveMember);
        [conversation removeParticipant:user];
        XCTAssertFalse(conversation.isSelfAnActiveMember);
    }];

    XCTAssertTrue([conversation hasLocalModificationsForKey:ZMConversationIsSelfAnActiveMemberKey]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertNotNil(conversation.lastReadServerTimeStamp);
    XCTAssertTrue(didSendFirstArchivedMessage);
    XCTAssertTrue(didSendLastReadMessage);
    XCTAssertTrue(didSendMemberLeaveRequest);
    XCTAssertTrue(didSendSecondArchivedMessage);
    XCTAssertTrue(firstIsArchived);
    XCTAssertTrue(secondIsArchived);
    
    XCTAssertTrue([firstArchivedRef compare:secondArchivedRef] == NSOrderedAscending);
    XCTAssertEqualObjects(secondArchivedRef, conversation.lastServerTimeStamp);
    XCTAssertEqualObjects(secondArchivedRef, conversation.lastReadServerTimeStamp);
    
    XCTAssertFalse([conversation hasLocalModificationsForKey:ZMConversationIsSelfAnActiveMemberKey]);
    
    NSUInteger unreadCount = conversation.estimatedUnreadCount;
    
    // and when logging in and out again lastRead is still set
    [self recreateSessionManagerAndDeleteLocalData];
    
    XCTAssertTrue([self login]);
    
    conversation = [self conversationForMockConversation:self.groupConversation];
    XCTAssertNotNil(conversation);
    XCTAssertEqual(conversation.estimatedUnreadCount, unreadCount);
}


- (void)testThatRemovingAndAddingAParticipantToAConversationSendsOutChangeNotifications
{
    
    __block MockUser *connectedUserNotInConv;
    {
        [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
            connectedUserNotInConv = [session insertUserWithName:@"Connected user which originally is not in conversation"];
            connectedUserNotInConv.email = @"connectedUserNotInConv@example.com";
            connectedUserNotInConv.phone = @"23498579";
            
            MockConversation *selfToConnectedNotInConvConversation = [session insertOneOnOneConversationWithSelfUser:self.selfUser otherUser:connectedUserNotInConv];
            selfToConnectedNotInConvConversation.creator = self.selfUser;
            
            MockConnection *connectionSelfToConnectedUserNotInConv = [session insertConnectionWithSelfUser:self.selfUser toUser:connectedUserNotInConv];
            connectionSelfToConnectedUserNotInConv.status = @"accepted";
            connectionSelfToConnectedUserNotInConv.lastUpdate = [NSDate dateWithTimeIntervalSinceNow:-3];
            connectionSelfToConnectedUserNotInConv.conversation = selfToConnectedNotInConvConversation;
        }];
        
        XCTAssertTrue([self login]);
        
        ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
        XCTAssertNotNil(conversation);
        
        ZMUser *user = [self userForMockUser:self.user1];
        
        ConversationChangeObserver *observer = [[ConversationChangeObserver alloc] initWithConversation:conversation];
        [observer clearNotifications];
        
        [self.userSession performChanges:^{
            XCTAssertTrue([conversation.activeParticipants containsObject:user]);
            [conversation removeParticipant:user];
            XCTAssertFalse([conversation.activeParticipants containsObject:user]);
        }];
        XCTAssertFalse(conversation.hasChanges, @"Rollback?");
        
        XCTAssertEqual(observer.notifications.count, 1u);
        ConversationChangeInfo *note1 = observer.notifications.firstObject;
        XCTAssertEqual(note1.conversation, conversation);
        XCTAssertTrue(note1.participantsChanged);
        [observer.notifications removeAllObjects];
        
        [self.userSession performChanges:^{
            XCTAssertFalse([conversation.activeParticipants containsObject:user]);
            [conversation addParticipant:user];
            XCTAssertTrue([conversation.activeParticipants containsObject:user]);
        }];
        XCTAssertFalse(conversation.hasChanges, @"Rollback?");
        
        XCTAssertEqual(observer.notifications.count, 1u);
        ConversationChangeInfo *note2 = observer.notifications.firstObject;
        XCTAssertEqual(note2.conversation, conversation);
        XCTAssertTrue(note2.participantsChanged);
        [observer.notifications removeAllObjects];
        
        // Wait for merge ui->sync to be done
        WaitForAllGroupsToBeEmpty(0.5);
        
        XCTAssertFalse([conversation hasLocalModificationsForKey:ZMConversationUnsyncedActiveParticipantsKey]);
    }
}


- (void)testThatActiveParticipantsInOneOnOneConversationsAreAllParticipants
{
    XCTAssertTrue([self login]);
    
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    XCTAssertNotNil(conversation);
    
    [self.userSession saveOrRollbackChanges];
    
    XCTAssertEqual(conversation.activeParticipants.count, 2u);
}

- (void)testThatActiveParticipantsInOneOnOneConversationWithABlockedUserAreAllParticipants
{
    // given
    
    XCTAssertTrue([self login]);
    
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    XCTAssertNotNil(conversation);
    
    [self.userSession saveOrRollbackChanges];
    
    XCTAssertEqual(conversation.activeParticipants.count, 2u);
    
    // when
    ZMUser *user1 = [self userForMockUser:self.user1];
    XCTAssertFalse(user1.isBlocked);

    [self.userSession performChanges:^{
        [user1 block];
    }];
    
    XCTAssertTrue(user1.isBlocked);
    XCTAssertEqual(conversation.activeParticipants.count, 2u);
}

- (NSArray *)movedIndexPairsForChangeSet:(ConversationListChangeInfo *)note
{
    NSMutableArray *indexes = [NSMutableArray array];
    [note enumerateMovedIndexes:^(NSInteger from, NSInteger to) {
        ZMMovedIndex *index = [[ZMMovedIndex alloc] initFrom:(NSUInteger)from to:(NSUInteger)to];
        [indexes addObject:index];
    }];
    
    return indexes;
}

- (void)testThatNotificationsAreReceivedWhenConversationsAreFaulted
{
    // given
    XCTAssertTrue([self login]);
        
    // I am faulting conversation, will maintain the "message" relations as faulted
    ZMConversationList *conversationList = [ZMConversationList conversationsInUserSession:self.userSession];
    
    XCTAssertEqual(conversationList.count, 4u);
    
    ConversationListChangeObserver *observer = [[ConversationListChangeObserver alloc] initWithConversationList:conversationList];

    // when
    {
        [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> ZM_UNUSED *session) {
            ZMGenericMessage *message = [ZMGenericMessage messageWithText:@"some message" nonce:NSUUID.createUUID.transportString expiresAfter:nil];
            [self.selfToUser1Conversation encryptAndInsertDataFromClient:self.user1.clients.anyObject toClient:self.selfUser.clients.anyObject data:message.data];
        }];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        NSIndexSet *updatedIndexes2 = [NSIndexSet indexSetWithIndex:0];
        XCTAssertEqual(observer.notifications.count, 1u);
        ConversationListChangeInfo *note1 = observer.notifications.lastObject;
        XCTAssertEqualObjects(note1.updatedIndexes, updatedIndexes2);
    }
}

- (void)testThatSelfUserSeesConversationWhenItIsAddedToConversationByOtherUser
{
    // given
    
    XCTAssertTrue([self login]);

    __block MockConversation *groupConversation;
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        groupConversation = [session insertConversationWithCreator:self.user3 otherUsers:@[self.user1, self.user2] type:ZMTConversationTypeGroup];
        [groupConversation changeNameByUser:self.selfUser name:@"Group conversation 2"];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    ZMConversationList *conversationList = [ZMConversationList conversationsInUserSession:self.userSession];
    
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> ZM_UNUSED *session) {
        [groupConversation addUsersByUser:self.user1 addedUsers:@[self.selfUser]];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    [self.userSession.syncManagedObjectContext saveOrRollback];
    WaitForAllGroupsToBeEmpty(0.5);

    //By this moment new conversation should be created and self user should be it's member
    ZMConversation *newConv = [self conversationForMockConversation:groupConversation];
    ZMUser *user = [self userForMockUser:self.selfUser];

    XCTAssertEqualObjects(conversationList.firstObject, newConv);
    XCTAssertTrue([newConv.activeParticipants containsObject:user]);
}


@end

#pragma mark - Conversation Window
@implementation  ConversationTests (ConversationWindow)


- (NSString *)text
{
    return @"";
}

- (void)conversationWindowDidChange:(MessageWindowChangeInfo *)note;
{
    [self.receivedConversationWindowChangeNotifications addObject:note];
}

- (void)testThatItSendsAConversationWindowChangeNotificationsIfAConversationIsChanged
{
    // given
    XCTAssertTrue([self login]);
    MockUserClient *fromClient = self.user2.clients.anyObject, *toClient = self.selfUser.clients.anyObject;
    
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        NOT_USED(session);
        
        for (NSUInteger i=0; i<20; ++i) {
            ZMGenericMessage *message = [ZMGenericMessage messageWithText:[NSString stringWithFormat:@"Message %ld", (unsigned long)i] nonce:NSUUID.createUUID.transportString expiresAfter:nil];
            [self.groupConversation encryptAndInsertDataFromClient:fromClient toClient:toClient data:message.data];
            [NSThread sleepForTimeInterval:0.002]; // SE has milisecond precision
        }
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    
    ZMConversation *groupConversation = [self conversationForMockConversation:self.groupConversation];
    XCTAssertNotNil(groupConversation);
    
    ZMConversationMessageWindow *conversationWindow = [groupConversation conversationWindowWithSize:5];
    id token = [MessageWindowChangeInfo addObserver: self forWindow:conversationWindow];
    
    // correct window?
    XCTAssertEqual(conversationWindow.messages.count, 5u);
    {
        ZMMessage *lastMessage = conversationWindow.messages.firstObject;
        XCTAssertEqualObjects(lastMessage.textMessageData.messageText, @"Message 19");
    }
    
    // when
    NSString *extraMessageText = @"This is an extra message at the end of the window";
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        NOT_USED(session);
        ZMGenericMessage *message = [ZMGenericMessage messageWithText:extraMessageText nonce:NSUUID.createUUID.transportString expiresAfter:nil];
        [self.groupConversation encryptAndInsertDataFromClient:fromClient toClient:toClient data:message.data];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertEqual(self.receivedConversationWindowChangeNotifications.count, 1u);
    MessageWindowChangeInfo *note = self.receivedConversationWindowChangeNotifications.firstObject;
    NSIndexSet *expectedInsertedIndexes = [[NSIndexSet alloc] initWithIndex:0];
    NSIndexSet *expectedDeletedIndexes = [[NSIndexSet alloc] initWithIndex:4];
    XCTAssertEqualObjects(note.insertedIndexes, expectedInsertedIndexes);
    XCTAssertEqualObjects(note.deletedIndexes, expectedDeletedIndexes);
    {
        ZMMessage *lastMessage = conversationWindow.messages.firstObject;
        XCTAssertEqualObjects(lastMessage.textMessageData.messageText, extraMessageText);
    }
    (void)token;
}

- (void)testThatTheMessageWindowIsUpdatedProperlyWithLocalMessages
{
    // given
    NSString *expectedText = @"Last text!";
    MockConversationWindowObserver *observer = [self windowObserverAfterLogginInAndInsertingMessagesInMockConversation:self.groupConversation];
    
    NSOrderedSet *initialMessageSet = observer.computedMessages;
    
    // when
    __block ZMMessage *newMessage;
    [self.userSession performChanges:^{
        newMessage = (id)[observer.window.conversation appendMessageWithText:expectedText];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    NSMutableOrderedSet *expectedMessages = [initialMessageSet mutableCopy];
    [expectedMessages removeObjectAtIndex:expectedMessages.count-1];
    [expectedMessages insertObject:newMessage atIndex:0];
    
    NSOrderedSet *currentMessageSet = observer.computedMessages;
    NSOrderedSet *windowMessageSet = observer.window.messages;
    
    XCTAssertEqualObjects(currentMessageSet, windowMessageSet);
    XCTAssertEqualObjects(currentMessageSet, expectedMessages);
}


- (void)testThatTheMessageWindowIsUpdatedProperlyWithRemoteMessages
{
    // given
    NSString *expectedText = @"Last text!";
    MockConversationWindowObserver *observer = [self windowObserverAfterLogginInAndInsertingMessagesInMockConversation:self.groupConversation];
    
    NSOrderedSet *initialMessageSet = observer.computedMessages;
    
    // when
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session ZM_UNUSED) {
        ZMGenericMessage *message = [ZMGenericMessage messageWithText:expectedText nonce:NSUUID.createUUID.transportString expiresAfter:nil];
        [self.groupConversation encryptAndInsertDataFromClient:self.user1.clients.anyObject toClient:self.selfUser.clients.anyObject data:message.data];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    NSOrderedSet *currentMessageSet = observer.computedMessages;
    NSOrderedSet *windowMessageSet = observer.window.messages;
    
    XCTAssertEqualObjects(currentMessageSet, windowMessageSet);
    
    for(NSUInteger i = 0; i < observer.window.size; ++ i) {
        if(i == 0) {
            XCTAssertEqualObjects([currentMessageSet[i] textMessageData].messageText, expectedText);
        }
        else {
            XCTAssertEqual(currentMessageSet[i], initialMessageSet[i-1]);
        }
    }
}

- (void)testThatTheMessageWindowIsUpdatedProperlyWhenThereAreConflictingChangesOnLocalAndRemote_SavingRemoteFirst
{
    // given
    NSString *expectedTextRemote = @"Last text REMOTE";
    NSString *expectedTextLocal = @"Last text LOCAL";
    MockConversationWindowObserver *observer = [self windowObserverAfterLogginInAndInsertingMessagesInMockConversation:self.groupConversation];
    
    NSOrderedSet *initialMessageSet = observer.computedMessages;
    XCTAssertEqualObjects(observer.computedMessages, observer.window.messages);
    
    // when
    ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
    [conversation appendMessageWithText:expectedTextLocal];
    
    [self.userSession.syncManagedObjectContext performGroupedBlockAndWait:^{
        ZMConversation *syncConversation = [ZMConversation conversationWithRemoteID:[NSUUID uuidWithTransportString:self.groupConversation.identifier] createIfNeeded:NO inContext:self.userSession.syncManagedObjectContext];
        [syncConversation appendMessageWithText:expectedTextRemote];
        [self.userSession.syncManagedObjectContext saveOrRollback];
    }];
    
    [self.userSession.managedObjectContext saveOrRollback];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    NSArray *currentMessageSet = observer.computedMessages.array;
    NSArray *windowMessageSet = observer.window.messages.array ;
    
    NSArray *currentTexts = [currentMessageSet mapWithBlock:^id(id<ZMConversationMessage> obj) {
        return [[obj textMessageData] messageText];
    }];
    NSArray *windowTexts = [windowMessageSet mapWithBlock:^id(id<ZMConversationMessage> obj) {
        return [[obj textMessageData] messageText];
    }];    
    
    XCTAssertEqualObjects(currentTexts, windowTexts);
    
    NSArray *originalFirstPart = [initialMessageSet.array subarrayWithRange:NSMakeRange(0, observer.window.size - 2)];
    NSArray *currentFirstPart = [currentMessageSet subarrayWithRange:NSMakeRange(2, observer.window.size - 2)];
    
    XCTAssertEqualObjects(originalFirstPart, currentFirstPart);
    NSString *messageText1 = [[(id<ZMConversationMessage>)currentMessageSet[0] textMessageData] messageText];
    NSString *messageText2 = [[(id<ZMConversationMessage>)currentMessageSet[1] textMessageData] messageText];

    // The order is not defined
    XCTAssertTrue([messageText1 isEqualToString:expectedTextLocal] || [messageText2 isEqualToString:expectedTextLocal]);
    XCTAssertTrue([messageText1 isEqualToString:expectedTextRemote] || [messageText2 isEqualToString:expectedTextRemote]);
}

@end

#pragma mark - Conversation list
@implementation ConversationTests (ConversationStatusAndOrder)

- (void)testThatTheConversationListOrderIsUpdatedAsWeReceiveMessages
{
    XCTAssertTrue([self login]);

    // given
    __block MockConversation *mockExtraConversation;
    
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        mockExtraConversation = [session insertGroupConversationWithSelfUser:self.selfUser otherUsers:@[self.user1, self.user2]];
        [mockExtraConversation changeNameByUser:self.selfUser name:@"Extra conversation"];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    ZMConversation *extraConversation = [self conversationForMockConversation:mockExtraConversation];
    ZMConversation *groupConversation = [self conversationForMockConversation:self.groupConversation];

    // then
    ZMConversationList *conversations = [ZMConversationList conversationsInUserSession:self.userSession];
    XCTAssertEqual(conversations.firstObject, extraConversation);
    
    ConversationListChangeObserver *observer = [[ConversationListChangeObserver alloc] initWithConversationList:conversations];

    // when
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        NOT_USED(session);
        ZMGenericMessage *message = [ZMGenericMessage messageWithText:@"Bla bla bla" nonce:NSUUID.createUUID.transportString expiresAfter:nil];
        MockUser *fromUser = self.groupConversation.activeUsers.lastObject;
        [self.groupConversation encryptAndInsertDataFromClient:fromUser.clients.anyObject toClient:self.selfUser.clients.anyObject data:message.data];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(conversations.firstObject, groupConversation);

    XCTAssertGreaterThanOrEqual(observer.notifications.count, 1u);
    
    NSInteger updatesCount = 0;
    NSMutableArray *moves = [@[] mutableCopy];
    for (ConversationListChangeInfo *note in observer.notifications) {
        updatesCount += note.updatedIndexes.count;
        //should be no deletions
        XCTAssertEqual(note.deletedIndexes.count, 0u);
        [moves addObjectsFromArray:note.zm_movedIndexPairs];
        
    }
    XCTAssertEqual(updatesCount, 1);
    XCTAssertEqual(moves.count, 1u);
    XCTAssertEqual([(ZMMovedIndex *)moves.firstObject from], 1u);
    XCTAssertEqual([(ZMMovedIndex *)moves.firstObject to], 0u);
}

- (void)testThatAConversationListListenerOnlyReceivesNotificationsForTheSpecificListItSignedUpFor
{
    // given
    XCTAssertTrue([self login]);
    ZMConversationList *convList1 = [ZMConversationList conversationsInUserSession:self.userSession];
    ZMConversationList *convList2 = [ZMConversationList archivedConversationsInUserSession:self.userSession];
    
    ConversationListChangeObserver *convListener1 = [[ConversationListChangeObserver alloc] initWithConversationList:convList1];
    ConversationListChangeObserver *convListener2 = [[ConversationListChangeObserver alloc] initWithConversationList:convList2];
    
    // when
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        NOT_USED(session);
        [session insertConversationWithSelfUser:self.selfUser creator:self.selfUser otherUsers:@[self.user1, self.user2] type:ZMTConversationTypeGroup];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    [self spinMainQueueWithTimeout:0.1];
    
    // then
    XCTAssertGreaterThanOrEqual(convListener1.notifications.count, 0u);
    XCTAssertEqual(convListener2.notifications.count, 0u);
}


- (void)testThatLatestConversationIsAlwaysOnTop
{
    // given
    XCTAssertTrue([self login]);
    
    ZMConversationList *conversationList = [ZMConversationList conversationsInUserSession:self.userSession];
    ZMConversation *conversation1 = [self conversationForMockConversation:self.selfToUser1Conversation];
    (void) conversation1.messages; // Make sure we've faulted in the messages
    ZMConversation *conversation2 = [self conversationForMockConversation:self.selfToUser2Conversation];
    (void) conversation2.messages; // Make sure we've faulted in the messages
    
    MockUserClient *toClient = self.selfUser.clients.anyObject;

    XCTAssertNotNil(conversation1);
    XCTAssertNotNil(conversation2);
    
    NSString *messageText1 = @"some message";
    NSString *messageText2 = @"some other message";
    NSString *messageText3 = @"some third message";
    
    
    NSUUID *nonce1 = [NSUUID createUUID];
    NSUUID *nonce2 = [NSUUID createUUID];
    NSUUID *nonce3 = [NSUUID createUUID];
    
    
    // when
    ConversationListChangeObserver *observer = [[ConversationListChangeObserver alloc] initWithConversationList:conversationList];
    [observer clearNotifications];
    
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> ZM_UNUSED *session) {
        ZMGenericMessage *message = [ZMGenericMessage messageWithText:messageText1 nonce:nonce1.transportString expiresAfter:nil];
        [self.selfToUser1Conversation encryptAndInsertDataFromClient:self.user1.clients.anyObject toClient:toClient data:message.data];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    NSIndexSet *expectedIndexes2 = [NSIndexSet indexSetWithIndex:0];
    
    XCTAssertEqual(conversationList[0], conversation1);
    
    XCTAssertGreaterThanOrEqual(observer.notifications.count, 1u);
    ConversationListChangeInfo *note1 = observer.notifications.lastObject;
    XCTAssertNotNil(note1);
    XCTAssertEqualObjects(note1.updatedIndexes, expectedIndexes2);
    
    ZMMessage *receivedMessage1 = conversation1.messages.lastObject;
    XCTAssertEqualObjects(receivedMessage1.textMessageData.messageText, messageText1);
    
    // send second message
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> ZM_UNUSED *session) {
        ZMGenericMessage *message = [ZMGenericMessage messageWithText:messageText2 nonce:nonce2.transportString expiresAfter:nil];
        [self.selfToUser2Conversation encryptAndInsertDataFromClient:self.user1.clients.anyObject toClient:toClient data:message.data];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    NSIndexSet *expectedIndexes3 = [NSIndexSet indexSetWithIndex:0];
    
    XCTAssertEqual(conversationList[0], conversation2);
    
    XCTAssertGreaterThanOrEqual(observer.notifications.count, 2u);
    ConversationListChangeInfo *note2 = observer.notifications.lastObject;
    XCTAssertNotNil(note2);
    XCTAssertEqualObjects(note2.updatedIndexes, expectedIndexes3);
    
    ZMMessage *receivedMessage2 = conversation2.messages.lastObject;
    XCTAssertEqualObjects(receivedMessage2.textMessageData.messageText, messageText2);
    
    // send first message again
    
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> ZM_UNUSED *session) {
        ZMGenericMessage *message = [ZMGenericMessage messageWithText:messageText3 nonce:nonce3.transportString expiresAfter:nil];
        [self.selfToUser1Conversation encryptAndInsertDataFromClient:self.user1.clients.anyObject toClient:toClient data:message.data];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    NSIndexSet *expectedIndexes4 = [NSIndexSet indexSetWithIndex:0];
    
    XCTAssertEqual(conversationList[0], conversation1);
    XCTAssertGreaterThanOrEqual(observer.notifications.count, 3u);
    
    ConversationListChangeInfo *note3 = observer.notifications.lastObject;
    XCTAssertNotNil(note3);
    XCTAssertEqualObjects(note3.updatedIndexes, expectedIndexes4);
    
    ZMMessage *receivedMessage3 = conversation1.messages.lastObject;
    XCTAssertEqualObjects(receivedMessage3.textMessageData.messageText, messageText3);
}

- (void)testThatReceivingAPingInAConversationThatIsNotAtTheTopBringsItToTheTop
{
    // given
    XCTAssertTrue([self login]);
    
    ZMConversationList *conversationList = [ZMConversationList conversationsInUserSession:self.userSession];
    ConversationListChangeObserver *conversationListChangeObserver = [[ConversationListChangeObserver alloc] initWithConversationList:conversationList];
    ZMConversation *oneToOneConversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    
    // make sure oneToOneConversation is not on top
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        NOT_USED(session);
        [self.selfToUser2Conversation insertKnockFromUser:self.user2 nonce:[NSUUID createUUID]];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssertNotEqual(oneToOneConversation, conversationList[0]); // make sure conversation is not on top
    
    NSUInteger oneToOneIndex = [conversationList indexOfObject:oneToOneConversation];
    
    // when
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        NOT_USED(session);
        [self.selfToUser1Conversation insertKnockFromUser:self.user1 nonce:[NSUUID createUUID]];
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    ConversationListChangeInfo *note = conversationListChangeObserver.notifications.firstObject;
    XCTAssertTrue(note);
    
    NSMutableArray *moves = [NSMutableArray array];
    [note enumerateMovedIndexes:^(NSInteger from, NSInteger to) {
        [moves addObject:@[@(from), @(to)]];
    }];
    
    NSArray *expectedArray = @[@[@(oneToOneIndex), @0]];
    
    XCTAssertEqualObjects(moves, expectedArray);
}

- (void)testThatConversationGoesOnTopAfterARemoteUserAcceptsOurConnectionRequest
{
    //given
    XCTAssertTrue([self login]);

    ZMConversation *oneToOneConversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    MockUser *mockUser = [self createSentConnectionFromUserWithName:@"Hans" uuid:NSUUID.createUUID];

    ZMConversationList *conversationList = [ZMConversationList conversationsInUserSession:self.userSession];
    ZMConversation *sentConversation = conversationList.firstObject;

    [self.mockTransportSession performRemoteChanges:^(__unused MockTransportSession<MockTransportSessionObjectCreation> *session) {
        ZMGenericMessage *message = [ZMGenericMessage messageWithText:@"some message" nonce:NSUUID.createUUID.transportString expiresAfter:nil];
        [self.selfToUser1Conversation encryptAndInsertDataFromClient:self.user1.clients.anyObject toClient:self.selfUser.clients.anyObject data:message.data];
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
    
    NSUInteger from = [conversationList indexOfObject:sentConversation];
    XCTAssertEqualObjects(oneToOneConversation, conversationList[0]);
    NSUInteger pendingIndex = [conversationList indexOfObject:sentConversation];
    pendingIndex = conversationList.count;
    
    ConversationListChangeObserver *conversationListChangeObserver = [[ConversationListChangeObserver alloc] initWithConversationList:conversationList];
    
    //when
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [session remotelyAcceptConnectionToUser:mockUser];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    //then
    XCTAssertGreaterThanOrEqual(conversationListChangeObserver.notifications.count, 1u);

    NSInteger updatesCount = 0;
    __block NSMutableArray *moves = [@[] mutableCopy];
    for (ConversationListChangeInfo *note in conversationListChangeObserver.notifications) {
        updatesCount += note.updatedIndexes.count;
        [moves addObjectsFromArray:note.zm_movedIndexPairs];
        XCTAssertTrue([note.updatedIndexes containsIndex:0]);
        //should be no deletions or insertions
        XCTAssertEqual(note.deletedIndexes.count, 0u);
        XCTAssertEqual(note.insertedIndexes.count, 0u);
    }
    XCTAssertGreaterThanOrEqual(updatesCount, 1);
    XCTAssertEqual(moves.count, 1u);
    XCTAssertEqual([(ZMMovedIndex *)moves.firstObject from], from);
    XCTAssertEqual([(ZMMovedIndex *)moves.firstObject to], 0u);

    
    XCTAssertEqualObjects(sentConversation, conversationList.firstObject);
    XCTAssertEqualObjects(oneToOneConversation, conversationList[1]);
}

- (void)testThatConversationGoesOnTopAfterWeAcceptIncommingConnectionRequest
{
    //given
    XCTAssertTrue([self login]);

    MockUser *mockUser = [self createPendingConnectionFromUserWithName:@"Hans" uuid:NSUUID.createUUID];
    ZMUser *realUser = [self userForMockUser:mockUser];
    
    ZMConversationList *pending = [ZMConversationList pendingConnectionConversationsInUserSession:self.userSession];
    XCTAssertEqual(pending.count, 1u);
    ZMConversation *pendingConnversation = pending.lastObject;

    ZMConversationList *activeConversations = [ZMConversationList conversationsInUserSession:self.userSession];
    NSUInteger activeCount = activeConversations.count;
    ConversationListChangeObserver *activeObserver = [[ConversationListChangeObserver alloc] initWithConversationList:activeConversations];
    ConversationListChangeObserver *pendingObserver = [[ConversationListChangeObserver alloc] initWithConversationList:pending];
    
    // when
    [self.userSession performChanges:^{
        [realUser accept];
    }];
    WaitForAllGroupsToBeEmpty(0.5f);

    //then
    XCTAssertEqual(pending.count, 0u);
    XCTAssertEqual(activeConversations.count, activeCount + 1u);
    XCTAssertTrue([activeConversations containsObject:pendingConnversation]);
    XCTAssertEqualObjects(activeConversations.firstObject, pendingConnversation);
    
    NSInteger deletionsCount = 0;
    for (ConversationListChangeInfo *note in pendingObserver.notifications) {
        deletionsCount += note.deletedIndexes.count;
        //should be no updates, insertions, moves in pending list
        XCTAssertEqual(note.insertedIndexes.count, 0u);
        XCTAssertEqual(note.updatedIndexes.count, 0u);
        XCTAssertEqual(note.zm_movedIndexPairs.count, 0u);
    }
    XCTAssertEqual(deletionsCount, 1);
    
    NSInteger insertionsCount = 0;
    for (ConversationListChangeInfo *note in activeObserver.notifications) {
        insertionsCount += note.insertedIndexes.count;
        //should be no deletions in active list
        XCTAssertEqual(note.deletedIndexes.count, 0u);
    }
    XCTAssertEqual(insertionsCount, 1);
}

@end


#pragma mark - Archiving and silencing
@implementation ConversationTests (ArchivingAndSilencing)

- (void)testThatArchivingAConversationIsSynchronizedToTheBackend
{
    {
        // given
        NSDate *previousArchivedDate = [NSDate dateWithTimeIntervalSince1970:-1];
        [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
            // set last read
            NOT_USED(session);
            self.groupConversation.otrArchived = NO;
            self.groupConversation.otrArchivedRef = previousArchivedDate.transportString;
        }];
        
        XCTAssertTrue([self login]);
        [self.mockTransportSession resetReceivedRequests];
        
        ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
        XCTAssertNotNil(conversation.lastServerTimeStamp);
        XCTAssertFalse(conversation.isArchived);
        XCTAssertTrue([conversation.lastServerTimeStamp compare:conversation.archivedChangedTimestamp] == NSOrderedDescending);
        
        // when
        [self.userSession performChanges:^{
            conversation.isArchived = YES;
        }];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        ZMTransportRequest *request = self.mockTransportSession.receivedRequests.firstObject;
        NSString *expectedPath = [NSString stringWithFormat:@"/conversations/%@/self", self.groupConversation.identifier];
        XCTAssertEqualObjects(request.path, expectedPath);
        XCTAssertEqual(request.method, ZMMethodPUT);
        XCTAssertEqualObjects(request.payload[@"otr_archived_ref"], conversation.archivedChangedTimestamp.transportString);
        XCTAssertEqualObjects(request.payload[@"otr_archived"], @(conversation.isArchived));
    }
    
    // Tears down context(s) &
    // Re-create contexts
    [self recreateSessionManagerAndDeleteLocalData];
    
    {
        // Wait for sync to be done
        XCTAssertTrue([self login]);
        
        // then
        ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
        XCTAssertTrue(conversation.isArchived);
    }
    
}

- (void)testThatUnarchivingAConversationIsSynchronizedToTheBackend
{
    // given
    XCTAssertTrue([self login]);
    
    ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
    [self.userSession performChanges:^{
        conversation.isArchived = YES;
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
    [self.mockTransportSession resetReceivedRequests];
    
    // when
    [self.userSession performChanges:^{
        conversation.isArchived = NO;
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    ZMTransportRequest *request = self.mockTransportSession.receivedRequests.firstObject;
    NSString *expectedPath = [NSString stringWithFormat:@"/conversations/%@/self", self.groupConversation.identifier];
    XCTAssertEqualObjects(request.path, expectedPath);
    XCTAssertEqual(request.method, ZMMethodPUT);
    XCTAssertEqualObjects(conversation.lastServerTimeStamp, conversation.archivedChangedTimestamp);
    XCTAssertEqualObjects(request.payload[@"otr_archived_ref"], conversation.archivedChangedTimestamp.transportString);
    XCTAssertEqualObjects(request.payload[@"otr_archived"], @(conversation.isArchived));
}

- (void)testThatSilencingAConversationIsSynchronizedToTheBackend
{
    {
        // given
        XCTAssertTrue([self login]);
        [self.mockTransportSession resetReceivedRequests];
        
        ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
        
        // when
        [self.userSession performChanges:^{
            conversation.isSilenced = YES;
        }];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        ZMTransportRequest *request = self.mockTransportSession.receivedRequests.firstObject;
        NSString *expectedPath = [NSString stringWithFormat:@"/conversations/%@/self", self.groupConversation.identifier];
        XCTAssertEqualObjects(request.path, expectedPath);
        XCTAssertEqual(request.method, ZMMethodPUT);
        XCTAssertEqualObjects(conversation.lastServerTimeStamp, conversation.silencedChangedTimestamp);
        XCTAssertEqualObjects(request.payload[@"otr_muted_ref"], conversation.silencedChangedTimestamp.transportString);
        XCTAssertEqualObjects(request.payload[@"otr_muted"], @(conversation.isSilenced));
    }
    
    // Tears down context(s) &
    // Re-create contexts
    [self recreateSessionManagerAndDeleteLocalData];
    
    {
        // Wait for sync to be done
        XCTAssertTrue([self login]);
        
        // then
        ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
        XCTAssertTrue(conversation.isSilenced);
    }

}

- (void)testThatUnsilencingAConversationIsSynchronizedToTheBackend
{
    // given
    XCTAssertTrue([self login]);
    
    ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
    [self.userSession performChanges:^{
        conversation.isSilenced = YES;
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
    [self.mockTransportSession resetReceivedRequests];
    
    // when
    [self.userSession performChanges:^{
        conversation.isSilenced = NO;
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    ZMTransportRequest *request = self.mockTransportSession.receivedRequests.firstObject;
    NSString *expectedPath = [NSString stringWithFormat:@"/conversations/%@/self", self.groupConversation.identifier];
    XCTAssertEqualObjects(request.path, expectedPath);
    XCTAssertEqual(request.method, ZMMethodPUT);
    XCTAssertEqualObjects(request.payload[@"otr_muted"], @0);
    XCTAssertEqualObjects(request.payload[@"otr_muted_ref"], conversation.lastServerTimeStamp.transportString);
}

- (void)testThatWhenBlockingAUserTheOneOnOneConversationIsRemovedFromTheConversationList
{
    // login
    XCTAssertTrue([self login]);
    
    // given
    
    ZMUser *user1 = [self userForMockUser:self.user1];
    (void) user1.name;
    XCTAssertFalse(user1.isBlocked);

    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    (void) conversation.messages; // Make sure we've faulted in the messages
    XCTAssertNotNil(conversation);
    XCTAssertEqualObjects(conversation.connectedUser, user1);
    XCTAssertEqual(conversation.conversationType, ZMConversationTypeOneOnOne);

    ZMConversationList *active = [ZMConversationList conversationsInUserSession:self.userSession];
    XCTAssertEqual(active.count, 4u);
    XCTAssertTrue([active containsObject:conversation]);

    ConversationListChangeObserver *observer = [[ConversationListChangeObserver alloc] initWithConversationList:active];
    
    // when blocking user 1
    
    [self.userSession performChanges:^{
        [user1 block];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then the conversation should not be in the active list anymore
    XCTAssertTrue(user1.isBlocked);
    XCTAssertEqual(conversation.connection.status, ZMConnectionStatusBlocked);

    XCTAssertEqual(active.count, 3u);
    XCTAssertFalse([active containsObject:conversation]);
    (void)observer;
}


- (void)checkThatItUnarchives:(BOOL)shouldUnarchive silenced:(BOOL)isSilenced mockConversation:(MockConversation *)mockConversation withBlock:(void (^)(MockTransportSession<MockTransportSessionObjectCreation> *session))block
{
    // given
    XCTAssertTrue([self login]);
    
    ZMConversation *conversation = [self conversationForMockConversation:mockConversation];
    [self.userSession performChanges:^{
        conversation.isArchived = YES;
        if (isSilenced) {
            conversation.isSilenced = YES;
        }
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertTrue(conversation.isArchived);
    if (isSilenced) {
        XCTAssertTrue(conversation.isSilenced);
    }
    
    // when
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        block(session);
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    if (shouldUnarchive) {
        XCTAssertFalse(conversation.isArchived);
    } else {
        XCTAssertTrue(conversation.isArchived);
    }
}

- (void)testThatAddingAMessageToAnArchivedConversation_Unarchives_ThisConversation
{
    // expect
    BOOL shouldUnarchive = YES;
    
    // when
    [self checkThatItUnarchives:shouldUnarchive silenced:NO mockConversation:self.groupConversation withBlock:^(ZM_UNUSED id session) {
        ZMGenericMessage *message = [ZMGenericMessage messageWithText:@"Some text" nonce:NSUUID.createUUID.transportString expiresAfter:nil];
        MockUser *fromUser = self.groupConversation.activeUsers.lastObject;
        [self.groupConversation encryptAndInsertDataFromClient:fromUser.clients.anyObject toClient:self.selfUser.clients.anyObject data:message.data];
    }];
}

- (void)testThatAddingAMessageToAnArchived_AndSilenced_Conversation_DoesNotUnarchive_ThisConversation
{
    // expect
    BOOL shouldUnarchive = NO;
    
    // when
    [self checkThatItUnarchives:shouldUnarchive silenced:YES mockConversation:self.groupConversation withBlock:^(ZM_UNUSED id session) {
        ZMGenericMessage *message = [ZMGenericMessage messageWithText:@"Some text" nonce:NSUUID.createUUID.transportString expiresAfter:nil];
        MockUser *fromUser = self.groupConversation.activeUsers.lastObject;
        [self.groupConversation encryptAndInsertDataFromClient:fromUser.clients.anyObject toClient:self.selfUser.clients.anyObject data:message.data];
    }];
}

- (void)testThatAddingAnImageToAnArchivedConversation_Unarchives_ThisConversation
{
    // expect
    BOOL shouldUnarchive = YES;
    
    // when
    [self checkThatItUnarchives:shouldUnarchive silenced:NO mockConversation:self.groupConversation withBlock:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [self.groupConversation insertImageEventsFromUser:session.selfUser];
    }];
}

- (void)testThatAddingAnImageToAnArchived_AndSilenced_Conversation_DoesNotUnarchive_ThisConversation
{
    // expect
    BOOL shouldUnarchive = NO;
    
    // when
    [self checkThatItUnarchives:shouldUnarchive silenced:YES mockConversation:self.groupConversation withBlock:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [self.groupConversation insertImageEventsFromUser:session.selfUser];
    }];
}

- (void)testThatAddingAnKnockToAnArchivedConversation_Unarchives_ThisConversation
{
    // expect
    BOOL shouldUnarchive = YES;
    
    // when
    [self checkThatItUnarchives:shouldUnarchive silenced:NO mockConversation:self.groupConversation withBlock:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [self.groupConversation insertKnockFromUser:session.selfUser nonce:NSUUID.createUUID];
    }];
}

- (void)testThatAddingAnKnockToAnArchived_AndSilenced_Conversation_DoesNotUnarchive_ThisConversation
{
    // expect
    BOOL shouldUnarchive = NO;
    
    // when
    [self checkThatItUnarchives:shouldUnarchive silenced:YES mockConversation:self.groupConversation withBlock:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [self.groupConversation insertKnockFromUser:session.selfUser nonce:NSUUID.createUUID];
    }];
}

- (void)testThatAddingUsersToAnArchivedConversation_Unarchives_ThisConversation
{
    // expect
    BOOL shouldUnarchive = YES;
    
    // when
    [self checkThatItUnarchives:shouldUnarchive silenced:NO mockConversation:self.groupConversation withBlock:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [self.groupConversation addUsersByUser:session.selfUser addedUsers:@[self.user5]];
    }];
}

- (void)testThatAddingUsersToAnArchived_AndSilenced_Conversation_DoesNotUnarchive_ThisConversation
{
    // expect
    BOOL shouldUnarchive = NO;
    
    // when
    [self checkThatItUnarchives:shouldUnarchive silenced:YES mockConversation:self.groupConversation withBlock:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [self.groupConversation addUsersByUser:session.selfUser addedUsers:@[self.user5]];
    }];
}

- (void)testThatRemovingUsersFromAnArchivedConversation_DoesNotUnarchive_ThisConversation
{
    // expect
    BOOL shouldUnarchive = NO;
    
    // when
    [self checkThatItUnarchives:shouldUnarchive silenced:NO mockConversation:self.groupConversation withBlock:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [self.groupConversation removeUsersByUser:session.selfUser removedUser:self.user2];
    }];
}

- (void)testThatRemovingUsersFromAnArchived_AndSilenced_Conversation_DoesNotUnarchive_ThisConversation
{
    // expect
    BOOL shouldUnarchive = NO;
    
    // when
    [self checkThatItUnarchives:shouldUnarchive silenced:YES mockConversation:self.groupConversation withBlock:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [self.groupConversation removeUsersByUser:session.selfUser removedUser:self.user2];
    }];
}

- (void)testThatRemovingSelfUserFromAnArchivedConversation_DoesNotUnarchive_ThisConversation
{
    // expect
    BOOL shouldUnarchive = NO;

    // when
    [self checkThatItUnarchives:shouldUnarchive silenced:NO mockConversation:self.groupConversation withBlock:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [self.groupConversation removeUsersByUser:session.selfUser removedUser:session.selfUser];
    }];
}

- (void)testThatRemovingSelfUserFromAnArchived_AndSilenced_Conversation_DoesNotUnarchive_ThisConversation
{
    // expect
    BOOL shouldUnarchive = NO;
    
    // when
    [self checkThatItUnarchives:shouldUnarchive silenced:YES mockConversation:self.groupConversation withBlock:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [self.groupConversation removeUsersByUser:session.selfUser removedUser:session.selfUser];
    }];
}

- (void)testThatAcceptingArchivedOutgoingRequest_Unarchives_ThisConversation
{
    XCTAssertTrue([self login]);

    MockUser *mockUser = [self createSentConnectionFromUserWithName:@"Hans" uuid:NSUUID.createUUID];
    ZMConversationList *conversations = [ZMConversationList conversationsInUserSession:self.userSession];
    ZMConversation *conversation = conversations.firstObject;
    // expect
    
    BOOL shouldUnarchive = YES;
    
    // when
    [self.userSession performChanges:^{
        conversation.isArchived = YES;
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertTrue(conversation.isArchived);
    
    // when
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [session remotelyAcceptConnectionToUser:mockUser];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    if (shouldUnarchive) {
        XCTAssertFalse(conversation.isArchived);
    } else {
        XCTAssertTrue(conversation.isArchived);
    }
}

@end


#pragma mark - Last read
@implementation ConversationTests (LastRead)

- (void)testThatEstimatedUnreadCountIsIncreasedAfterRecevingATextMessage
{
    // login
    XCTAssertTrue([self login]);
    
    // given
    MockUserClient *fromClient = self.user1.clients.anyObject;
    MockUserClient *toClient = self.selfUser.clients.anyObject;
    
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        NOT_USED(session);
        ZMGenericMessage *message = [ZMGenericMessage messageWithText:@"Will insert this to have a message to read" nonce:NSUUID.createUUID.transportString expiresAfter:nil];
        [self.selfToUser1Conversation encryptAndInsertDataFromClient:fromClient toClient:toClient data:message.data];
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self recreateSessionManagerAndDeleteLocalData];
    XCTAssertTrue([self login]);
    
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    XCTAssertEqual(conversation.estimatedUnreadCount, 0u);
    
    toClient = [self.selfUser.clients.allObjects filterWithBlock:^(MockUserClient* client){
        return [client.identifier isEqualToString: [ZMUser selfUserInContext: self.userSession.managedObjectContext].selfClient.remoteIdentifier];
    }].firstObject;
    
    // when
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        NOT_USED(session);
        ZMGenericMessage *message = [ZMGenericMessage messageWithText:@"This should increase the unread count" nonce:NSUUID.createUUID.transportString expiresAfter:nil];
        [self.selfToUser1Conversation encryptAndInsertDataFromClient:fromClient toClient:toClient data:message.data];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(conversation.estimatedUnreadCount, 1u);
}

- (void)testThatItDoesNotSendALastReadEventWhenInsertingAMessage
{
    // given
    XCTAssertTrue([self login]);
    
    [self.mockTransportSession resetReceivedRequests];
    ZMConversation *conv =  [self conversationForMockConversation:self.selfToUser1Conversation];
    ZMConversation *selfConv = [ZMConversation selfConversationInContext:self.userSession.managedObjectContext];
    __block ZMMessage *textMsg;
    __block ZMMessage *imageMsg;

    // when
    [self.userSession performChanges:^{
        textMsg = (id)[conv appendMessageWithText:@"bla bla"];
        imageMsg = (id)[conv appendMessageWithImageData:self.verySmallJPEGData];
        [conv setVisibleWindowFromMessage:nil toMessage:imageMsg];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    ZMTransportRequest *lastReadRequest = [self.mockTransportSession.receivedRequests firstObjectMatchingWithBlock:^BOOL(ZMTransportRequest *request){
        return [request.path isEqualToString:[NSString stringWithFormat:@"/conversations/%@/otr/messages", selfConv.remoteIdentifier.transportString]];
    }];
    XCTAssertNil(lastReadRequest);
    
    XCTAssertEqual(conv.estimatedUnreadCount, 0u);
}

@end

#pragma mark - Conversation list pagination
@implementation ConversationTests (Pagination)

- (void)testThatItPaginatesConversationIDsRequests
{
    self.previousZMConversationTranscoderListPageSize = ZMConversationTranscoderListPageSize;
    ZMConversationTranscoderListPageSize = 3;
    
    __block NSUInteger numberOfConversations;
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        for(int i = 0; i < 10; ++i) {
            [session insertGroupConversationWithSelfUser:self.selfUser otherUsers:@[self.user1, self.user2]];
        }
        
        NSFetchRequest *request = [MockConversation sortedFetchRequest];
        NSArray *conversations = [self.mockTransportSession.managedObjectContext executeFetchRequestOrAssert:request];
        numberOfConversations = conversations.count;
    }];
    
    // when
    XCTAssertTrue([self login]);

    NSArray *activeConversations = [ZMConversationList conversationsInUserSession:self.userSession];
    NSArray *pendingConversations = [ZMConversationList pendingConnectionConversationsInUserSession:self.userSession];

    // then
    NSUInteger expectedRequests = (NSUInteger)(numberOfConversations * 1.f / ZMConversationTranscoderListPageSize + 0.5f);
    NSUInteger foundRequests = 0;
    for(ZMTransportRequest *request in self.mockTransportSession.receivedRequests) {
        if([request.path hasPrefix:@"/conversations/ids?size=3"]) {
            ++foundRequests;
        }
    }
    
    XCTAssertEqual(expectedRequests, foundRequests);
    XCTAssertEqual(1 + activeConversations.count + pendingConversations.count, numberOfConversations); // +1 is the self, which we don't return to UI
    
    // then
    ZMConversationTranscoderListPageSize = self.previousZMConversationTranscoderListPageSize;
}

@end

#pragma mark - Clearing history
@implementation ConversationTests (ClearingHistory)

- (void)loginAndFillConversationWithMessages:(MockConversation *)mockConversation messagesCount:(NSUInteger)messagesCount
{
    XCTAssertTrue([self login]);
    
    ZMConversation *conversation = [self conversationForMockConversation:mockConversation];
    MockUser *otherUser = (id)[mockConversation.activeUsers firstObjectNotInSet:[NSSet setWithObject:self.selfUser]];
    
    // given
    MockUserClient *fromClient = otherUser.clients.anyObject, *toClient = self.selfUser.clients.anyObject;
    
    [self.mockTransportSession performRemoteChanges:^(ZM_UNUSED id session) {
        // If the client is not registered yet we need to account for the added System Message
        for (NSUInteger i = 0; i < messagesCount - conversation.messages.count; i++) {
            ZMGenericMessage *message = [ZMGenericMessage messageWithText:[NSString stringWithFormat:@"foo %lu", (unsigned long)i] nonce:NSUUID.createUUID.transportString expiresAfter:nil];
            [mockConversation encryptAndInsertDataFromClient:fromClient toClient:toClient data:message.data];
        }
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    conversation = [self conversationForMockConversation:mockConversation];
    XCTAssertEqual(conversation.messages.count, messagesCount);
    
    ZMConversationMessageWindow *window = [conversation conversationWindowWithSize:messagesCount];
    XCTAssertEqual(window.messages.count, window.size);
}

- (void)testThatItNotifiesTheObserverWhenTheHistoryIsClearedAndSyncsWithTheBackend
{
    //given
    const NSUInteger messagesCount = 5;
    [self loginAndFillConversationWithMessages:self.groupConversation messagesCount:messagesCount];
    WaitForAllGroupsToBeEmpty(0.5);

    ZMConversationListDirectory *conversationDirectory = self.userSession.managedObjectContext.conversationListDirectory;
    WaitForAllGroupsToBeEmpty(0.5);

    ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
    {
        ZMConversationMessageWindow *window = [conversation conversationWindowWithSize:messagesCount];
        id token = [MessageWindowChangeInfo addObserver: self forWindow:window];
        [self.mockTransportSession resetReceivedRequests];
        [self.receivedConversationWindowChangeNotifications removeAllObjects];
        
        // when
    
        [self.userSession performChanges:^{
            [conversation clearMessageHistory];
        }];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        XCTAssertEqual(window.messages.count, 0u);
        XCTAssertFalse([conversationDirectory.conversationsIncludingArchived containsObject:conversation]);
        
        XCTAssertEqual(self.receivedConversationWindowChangeNotifications.count, 1u);
        MessageWindowChangeInfo *info = self.receivedConversationWindowChangeNotifications.firstObject;
        XCTAssertEqualObjects([info deletedIndexes], [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, messagesCount)]);
        
        ZMTransportRequest *firstRequest = self.mockTransportSession.receivedRequests.firstObject;
        NSString *expectedPath = [NSString stringWithFormat:@"/conversations/%@/self", conversation.remoteIdentifier.transportString];
        XCTAssertEqualObjects(firstRequest.payload[@"otr_archived_ref"], conversation.lastServerTimeStamp.transportString);
        XCTAssertEqualObjects(firstRequest.payload[@"otr_archived"], @1);

        XCTAssertEqualObjects(firstRequest.path, expectedPath);
        XCTAssertEqual(firstRequest.method, ZMMethodPUT);
        
        ZMUser *selfUser = [self userForMockUser:self.selfUser];
        ZMTransportRequest *lastRequest = self.mockTransportSession.receivedRequests.lastObject;
        NSString *selfConversationPath = [NSString stringWithFormat:@"/conversations/%@/otr/messages", selfUser.remoteIdentifier.transportString];
        XCTAssertNotNil(lastRequest.binaryData);
        XCTAssertEqualObjects(lastRequest.path, selfConversationPath);
        XCTAssertEqual(lastRequest.method, ZMMethodPOST);
        
        token = nil;
        window = nil;
    }
    conversation = nil;
    self.receivedConversationWindowChangeNotifications = [NSMutableArray array];
    [self recreateSessionManagerAndDeleteLocalData];
    WaitForAllGroupsToBeEmpty(0.5);

    {
        // Wait for sync to be done
        XCTAssertTrue([self login]);
    
        // then
        conversation = [self conversationForMockConversation:self.groupConversation];
        WaitForAllGroupsToBeEmpty(0.5);

        ZMConversationMessageWindow *window = [conversation conversationWindowWithSize:5];
        XCTAssertEqual(window.messages.count, 2u);
        XCTAssertEqualObjects([window.messages.firstObject class], [ZMSystemMessage class]);
        ZMSystemMessage *message = window.messages.firstObject;
        XCTAssertEqual(message.systemMessageType, ZMSystemMessageTypeUsingNewDevice);
        
        XCTAssertEqual(conversation.messages.count, 2u);
        XCTAssertEqualObjects([window.messages.firstObject objectID], [message objectID]);

        XCTAssertTrue(conversation.isArchived);
        XCTAssertFalse([conversationDirectory.conversationsIncludingArchived containsObject:conversation]);
    }
}

// TODO: test for conversations that starts with connection request

- (void)testThatItRemovesMessagesAfterReceivingAPushEventToClearHistory
{
    //given
    const NSUInteger messagesCount = 5;
    [self loginAndFillConversationWithMessages:self.groupConversation messagesCount:messagesCount];
    ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
    
    ZMConversationMessageWindow *window = [conversation conversationWindowWithSize:messagesCount];
    id token = [MessageWindowChangeInfo addObserver: self forWindow:window];
    
    ZMConversationListDirectory *conversationDirectory = self.userSession.managedObjectContext.conversationListDirectory;
    NSManagedObjectID *conversationID = conversation.objectID;
    
   
    // when removing messages remotely
    {
        [self remotelyAppendSelfConversationWithZMClearedForMockConversation:self.groupConversation atTime:conversation.lastServerTimeStamp];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        XCTAssertEqual(window.messages.count, 0u);
        
        XCTAssertEqual(self.receivedConversationWindowChangeNotifications.count, 1u);
        MessageWindowChangeInfo *info = self.receivedConversationWindowChangeNotifications.firstObject;
        XCTAssertEqualObjects([info deletedIndexes], [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 5)]);
        [self.receivedConversationWindowChangeNotifications removeAllObjects];
    }
    
    // when adding new messages
    
    [self.userSession performChanges:^{
        [self spinMainQueueWithTimeout:1]; // if the message is sent within the same second of clearing the window, it will not be added when resyncing
        [conversation appendMessageWithText:@"lalala"];
        [conversation setVisibleWindowFromMessage:conversation.messages.lastObject toMessage:conversation.messages.lastObject];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertEqual(conversation.messages.count, 1u);
    XCTAssertEqual(window.messages.count, 1u); // new message
    
    token = nil;
    window = nil;
    [self recreateSessionManagerAndDeleteLocalData];
    WaitForAllGroupsToBeEmpty(0.5);
    
    {
        // Wait for sync to be done
        XCTAssertTrue([self login]);
        
        // then
        conversation = [self conversationForMockConversation:self.groupConversation];
        WaitForAllGroupsToBeEmpty(0.5);
        
        window = [conversation conversationWindowWithSize:messagesCount];
        XCTAssertTrue([conversationDirectory.conversationsIncludingArchived.objectIDs containsObject:conversationID]);
    }
}

- (void)testThatDeletedConversationsStayDeletedAfterResyncing
{
    //given
    const NSUInteger messagesCount = 5;
    [self loginAndFillConversationWithMessages:self.groupConversation messagesCount:messagesCount];
    
    ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
    XCTAssertEqual(conversation.messages.count, 5lu);
    
    ZMConversationMessageWindow *window = [conversation conversationWindowWithSize:messagesCount];
    id token = [MessageWindowChangeInfo addObserver: self forWindow:window];
    
    ZMConversationListDirectory *conversationDirectory = self.userSession.managedObjectContext.conversationListDirectory;
    NSManagedObjectID *conversationID = conversation.objectID;
    
    // when deleting the conversation remotely
    {
        [self.mockTransportSession performRemoteChanges:^(ZM_UNUSED id session) {
            [self.groupConversation remotelyArchiveFromUser:self.selfUser referenceDate:[NSDate date]];
        }];
        WaitForAllGroupsToBeEmpty(0.5);
        [self remotelyAppendSelfConversationWithZMClearedForMockConversation:self.groupConversation atTime:conversation.lastServerTimeStamp];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        XCTAssertEqual(window.messages.count, 0u);
        XCTAssertFalse([conversationDirectory.conversationsIncludingArchived containsObject:conversation]);
        
        XCTAssertEqual(self.receivedConversationWindowChangeNotifications.count, 1u);
        MessageWindowChangeInfo *info = self.receivedConversationWindowChangeNotifications.firstObject;
        XCTAssertEqualObjects([info deletedIndexes], [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 5)]);
        [self.receivedConversationWindowChangeNotifications removeAllObjects];
    }
    
    token = nil;
    conversation = nil;
    window = nil;
    [self recreateSessionManagerAndDeleteLocalData];
    WaitForAllGroupsToBeEmpty(0.5);
    
    {
        // Wait for sync to be done
        XCTAssertTrue([self login]);
        
        // then
        conversation = [self conversationForMockConversation:self.groupConversation];
        WaitForAllGroupsToBeEmpty(0.5);
        
        window = [conversation conversationWindowWithSize:messagesCount];
        
        XCTAssertEqual(window.messages.count, 2u);
        XCTAssertEqualObjects([window.messages.firstObject class], [ZMSystemMessage class]);
        ZMSystemMessage *message = window.messages.firstObject;
        XCTAssertEqual(message.systemMessageType, ZMSystemMessageTypeUsingNewDevice);
        
        XCTAssertEqual(conversation.messages.count, 2u);
        XCTAssertEqualObjects([conversation.messages.lastObject objectID], [message objectID]);
        
        XCTAssertFalse([conversationDirectory.conversationsIncludingArchived.objectIDs containsObject:conversationID]);
        XCTAssertFalse([conversationDirectory.archivedConversations.objectIDs containsObject:conversationID]);
        XCTAssertTrue([conversationDirectory.clearedConversations.objectIDs containsObject:conversationID]);
    }
}

- (void)testFirstArchivingThenClearingRemotelyShouldDeleteConversation
{
    //given
    const NSUInteger messagesCount = 5;
    [self loginAndFillConversationWithMessages:self.groupConversation messagesCount:messagesCount];
    ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
    
    ZMConversationListDirectory *conversationDirectory = self.userSession.managedObjectContext.conversationListDirectory;
    NSManagedObjectID *conversationID = conversation.objectID;
    
    [self.mockTransportSession performRemoteChanges:^(ZM_UNUSED id session) {
        [self.groupConversation remotelyArchiveFromUser:self.selfUser referenceDate:[NSDate date]];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self remotelyAppendSelfConversationWithZMClearedForMockConversation:self.groupConversation atTime:conversation.lastServerTimeStamp];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertFalse([conversationDirectory.conversationsIncludingArchived.objectIDs containsObject:conversationID]);
}

- (void)testFirstClearingThenArchivingRemotelyShouldDeleteConversation
{
    //given
    const NSUInteger messagesCount = 5;
    [self loginAndFillConversationWithMessages:self.groupConversation messagesCount:messagesCount];
    ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
    
    ZMConversationListDirectory *conversationDirectory = self.userSession.managedObjectContext.conversationListDirectory;
    NSManagedObjectID *conversationID = conversation.objectID;
    
    [self remotelyAppendSelfConversationWithZMClearedForMockConversation:self.groupConversation atTime:conversation.lastServerTimeStamp];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.mockTransportSession performRemoteChanges:^(ZM_UNUSED id session) {
        [self.groupConversation remotelyArchiveFromUser:self.selfUser referenceDate:[NSDate date]];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertFalse([conversationDirectory.conversationsIncludingArchived.objectIDs containsObject:conversationID]);
}

- (void)testThatRemotelyArchivedConversationIsIncludedInTheCorrectConversationLists
{
    // given
    const NSUInteger messagesCount = 5;
    [self loginAndFillConversationWithMessages:self.groupConversation messagesCount:messagesCount];
    ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
    
    ZMConversationListDirectory *conversationDirectory = self.userSession.managedObjectContext.conversationListDirectory;
    
    // when archiving the conversation remotely
    [self.mockTransportSession performRemoteChanges:^(ZM_UNUSED id session) {
        [self.groupConversation remotelyArchiveFromUser:self.selfUser referenceDate:[NSDate date]];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertTrue([conversationDirectory.conversationsIncludingArchived containsObject:conversation]);
    XCTAssertTrue([conversationDirectory.archivedConversations containsObject:conversation]);
    XCTAssertFalse([conversationDirectory.clearedConversations containsObject:conversation]);
}

- (void)testThatRemotelyArchivedConversationIsIncludedInTheCorrectConversationListsAfterResyncing
{
    // given
    const NSUInteger messagesCount = 5;
    [self loginAndFillConversationWithMessages:self.groupConversation messagesCount:messagesCount];
    ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
    ZMConversationListDirectory *conversationDirectory = self.userSession.managedObjectContext.conversationListDirectory;
    NSManagedObjectID *conversationID = conversation.objectID;
    
    // when deleting the conversation remotely, whiping the cache and resyncing
    {
        [self.mockTransportSession performRemoteChanges:^(ZM_UNUSED id session) {
            [self.groupConversation remotelyArchiveFromUser:self.selfUser referenceDate:[NSDate date]];
        }];
        WaitForAllGroupsToBeEmpty(0.5);
        
        [self recreateSessionManagerAndDeleteLocalData];
        WaitForAllGroupsToBeEmpty(0.5);
        XCTAssertTrue([self login]);
    }
    
    // then
    conversation = [self conversationForMockConversation:self.groupConversation];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertTrue([conversationDirectory.conversationsIncludingArchived.objectIDs containsObject:conversationID]);
    XCTAssertTrue([conversationDirectory.archivedConversations.objectIDs containsObject:conversationID]);
    XCTAssertFalse([conversationDirectory.clearedConversations.objectIDs containsObject:conversationID]);
}

- (void)testThatReceivingRemoteTextMessageRevealsClearedConversation
{
    //given
    const NSUInteger messagesCount = 5;
    [self loginAndFillConversationWithMessages:self.groupConversation messagesCount:messagesCount];
    ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];

    [self.userSession performChanges:^{
        [conversation clearMessageHistory];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssertEqual(conversation.messages.count, 0u);
    
    // when
    
    [self.mockTransportSession performRemoteChanges:^(ZM_UNUSED id session) {
        [self spinMainQueueWithTimeout:1]; // if the action happens within the same second the user clears the history, the event is not added
        ZMGenericMessage *message = [ZMGenericMessage messageWithText:@"foo" nonce:NSUUID.createUUID.transportString expiresAfter:nil];
        [self.groupConversation encryptAndInsertDataFromClient:self.user2.clients.anyObject toClient:self.selfUser.clients.anyObject data:message.data];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    conversation = [self conversationForMockConversation:self.groupConversation];
    ZMConversationMessageWindow *window = [conversation conversationWindowWithSize:messagesCount];
    XCTAssertEqual(window.messages.count, 1u);
    XCTAssertEqual(conversation.messages.count, 1u);
    XCTAssertFalse(conversation.isArchived);
}

- (void)testThatReceivingRemoteSystemMessageRevealsClearedConversation
{
    //given
    const NSUInteger messagesCount = 5;
    [self loginAndFillConversationWithMessages:self.groupConversation messagesCount:messagesCount];
    ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
    
    [self.userSession performChanges:^{
        [conversation clearMessageHistory];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertEqual(conversation.messages.count, 0u);
    // when
    
    [self.mockTransportSession performRemoteChanges:^(ZM_UNUSED id session) {
        [self spinMainQueueWithTimeout:1]; // if the action happens within the same second the user clears the history, the event is not added
        [self.groupConversation removeUsersByUser:self.user2 removedUser:self.user3];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    conversation = [self conversationForMockConversation:self.groupConversation];
    ZMConversationMessageWindow *window = [conversation conversationWindowWithSize:messagesCount];
    XCTAssertEqual(window.messages.count, 1u);
    XCTAssertEqual(conversation.messages.count, 1u);
    XCTAssertTrue(conversation.isArchived);
}

- (void)testThatOpeningClearedConversationRevealsIt
{
    //given
    const NSUInteger messagesCount = 5;
    [self loginAndFillConversationWithMessages:self.groupConversation messagesCount:messagesCount];
    ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];

    [self.userSession performChanges:^{
        [conversation clearMessageHistory];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertEqual(conversation.messages.count, 0u);

    // when
    
    [self.userSession performChanges:^{
        [conversation revealClearedConversation];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    conversation = [self conversationForMockConversation:self.groupConversation];
    ZMConversationMessageWindow *window = [conversation conversationWindowWithSize:5];
    XCTAssertEqual(window.messages.count, 0u);
    XCTAssertEqual(conversation.messages.count, 0u);
    XCTAssertFalse(conversation.isArchived);
}


- (void)testThatItSetsTheLastReadWhenReceivingARemoteLastReadThroughTheSelfConversation
{
    // given
    XCTAssertTrue([self login]);
    
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    [self.userSession performChanges:^{
        ZMMessage *message = (id)[conversation appendMessageWithText:@"lalala"];
        conversation.lastReadServerTimeStamp = message.serverTimestamp;
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    NSDate *newLastRead = [conversation.lastReadServerTimeStamp dateByAddingTimeInterval:500];
    
    // when
    [self remotelyAppendSelfConversationWithZMLastReadForMockConversation:self.selfToUser1Conversation atTime:newLastRead];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual([conversation.lastReadServerTimeStamp timeIntervalSince1970], [newLastRead timeIntervalSince1970]);
}


- (void)testThatItClearsMessagesWhenReceivingARemoteClearedThroughTheSelfConversation
{
    // given
    XCTAssertTrue([self login]);
    
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    XCTAssertEqual(conversation.messages.count, 1u); // "You started using this device" message
    
    __block ZMMessage *message1;
    __block ZMMessage *message2;
    __block ZMMessage *message3;

    [self.userSession performChanges:^{
        [conversation appendMessageWithText:@"lalala"];
        [self spinMainQueueWithTimeout:0.1]; // this is needed so the timeStamps are at least a millisecond appart
        [conversation appendMessageWithText:@"boohoohoo"];
        [self spinMainQueueWithTimeout:0.1]; // this is needed so the timeStamps are at least a millisecond appart
        message1 = (id)[conversation appendMessageWithText:@"hehehe"];
        [NSThread sleepForTimeInterval:0.2]; // this is needed so the timeStamps are at least a millisecond appart
        message2 = (id)[conversation appendMessageWithText:@"I will not go away"];
        [self spinMainQueueWithTimeout:0.1]; // this is needed so the timeStamps are at least a millisecond appart
        message3 = (id)[conversation appendMessageWithText:@"I will stay for sure"];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssertEqual(conversation.messages.count, 6u);

    NSArray *remainingMessages = @[message2, message3];
    NSDate *cleared = message1.serverTimestamp;
    
    // when
    [self remotelyAppendSelfConversationWithZMClearedForMockConversation:self.selfToUser1Conversation atTime:cleared];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual([conversation.clearedTimeStamp timeIntervalSince1970], [cleared timeIntervalSince1970]);
    XCTAssertEqual(conversation.messages.count, 2u);
    AssertArraysContainsSameObjects(conversation.messages.array, remainingMessages);
}

- (void)testThatItRecoversFromFailedUpdateOfIsSelfAnActiveMember
{
    // given
    XCTAssertTrue([self login]);
    
    __block NSUInteger callCount = 0;
    ZM_WEAK(self);
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request) {
        ZM_STRONG(self);
        NSString *path = [NSString stringWithFormat:@"/conversations/%@/members/%@", self.groupConversation.identifier, self.selfUser.identifier];
        if([request.path isEqualToString:path]) {
            XCTAssertEqual(callCount, 0u);
            callCount++;
            return [ZMTransportResponse responseWithPayload:nil HTTPStatus:404 transportSessionError:nil];
        }
        return nil;
    };
    
    // when
    ZMUser *selfUser = [self userForMockUser:self.selfUser];
    ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
    [self.userSession performChanges:^{
        [conversation removeParticipant:selfUser];
    }];
    
    // then
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertTrue(conversation.isSelfAnActiveMember);
}

- (void)testThatItRecoversFromAddingABlockedUserToAConversation
{
    // given
    XCTAssertTrue([self login]);

    __block MockUser *connectedUserNotInConv;
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        connectedUserNotInConv = [session insertUserWithName:@"Connected user which originally is not in conversation"];
        connectedUserNotInConv.email = @"connectedUserNotInConv@example.com";
        connectedUserNotInConv.phone = @"23498579";
        
        MockConversation *selfToConnectedNotInConvConversation = [session insertOneOnOneConversationWithSelfUser:self.selfUser otherUser:connectedUserNotInConv];
        selfToConnectedNotInConvConversation.creator = self.selfUser;
        
        MockConnection *connectionSelfToConnectedUserNotInConv = [session insertConnectionWithSelfUser:self.selfUser toUser:connectedUserNotInConv];
        connectionSelfToConnectedUserNotInConv.status = @"accepted";
        connectionSelfToConnectedUserNotInConv.lastUpdate = [NSDate dateWithTimeIntervalSinceNow:-3];
        connectionSelfToConnectedUserNotInConv.conversation = selfToConnectedNotInConvConversation;
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    __block NSUInteger callCount = 0;
    ZM_WEAK(self);
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request) {
        ZM_STRONG(self);
        NSString *path = [NSString stringWithFormat:@"/conversations/%@/members", self.groupConversation.identifier];
        if([request.path isEqualToString:path] && request.method == ZMMethodPOST) {
            XCTAssertEqual(callCount, 0u);
            callCount++;
            return [ZMTransportResponse responseWithPayload:nil HTTPStatus:403 transportSessionError:nil];
        }
        return nil;
    };
    
    // when
    ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
    ZMUser *otherUser = [self userForMockUser:connectedUserNotInConv];
    XCTAssertNotNil(otherUser);
    XCTAssertFalse([conversation.activeParticipants containsObject:otherUser]);

    [self.userSession performChanges:^{
        [conversation addParticipant:otherUser];
        XCTAssertTrue([conversation.activeParticipants containsObject:otherUser]);
    }];
    
    // then
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertFalse([conversation.activeParticipants containsObject:otherUser]);
}

@end

@implementation ConversationTests (Reactions)

- (void)testThatAppendingAReactionWithSendAMessageWithReaction;
{
    // given
    XCTAssertTrue([self login]);
    
    [self prefetchRemoteClientByInsertingMessageInConversation:self.selfToUser1Conversation];
    WaitForAllGroupsToBeEmpty(0.5);
    
    MockConversation *mockConversation = self.selfToUser1Conversation;
    ZMConversation *conversation = [self conversationForMockConversation:mockConversation];
    
    __block ZMTextMessage *message;
    [self.userSession performChanges:^{
        message = (ZMTextMessage *)[conversation appendMessageWithText:@"Je t'aime JCVD"];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    NSString *reactionEmoji = @"❤️";
    [self.userSession performChanges:^{
        [ZMMessage addReaction:MessageReactionLike toMessage:message];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    //then
    XCTAssertEqual(message.usersReaction.count, 1lu);
    XCTAssertNotNil(message.usersReaction[reactionEmoji]);
    XCTAssertEqual([message.usersReaction[reactionEmoji] count], 1lu);
    XCTAssertEqualObjects([message.usersReaction[reactionEmoji] firstObject], [self userForMockUser:self.selfUser]);
    XCTAssertEqual(conversation.hiddenMessages.count, 0lu);
    XCTAssertNotNil([self.mockTransportSession.receivedRequests lastObject]);
}

- (void)testThatAppendingAReactionWithReceivingAMessageWithReaction;
{
    //given
    XCTAssertTrue([self login]);
    
    [self prefetchRemoteClientByInsertingMessageInConversation:self.selfToUser1Conversation];
    WaitForAllGroupsToBeEmpty(0.5);
    
    MockConversation *mockConversation = self.selfToUser1Conversation;
    ZMConversation *conversation = [self conversationForMockConversation:mockConversation];
    
    __block ZMTextMessage *message;
    [self.userSession performChanges:^{
        message = (ZMTextMessage *)[conversation appendMessageWithText:@"Je t'aime JCVD"];
    }];
    NSUUID *nonce = message.nonce;
    WaitForAllGroupsToBeEmpty(0.5);
    
    NSString *reactionEmoji = @"❤️";
    ZMGenericMessage *reactionMessage = [ZMGenericMessage messageWithEmojiString:reactionEmoji messageID:nonce.transportString nonce:[NSUUID UUID].transportString];
    MockUserClient *fromClient = [self.user1.clients anyObject];
    MockUserClient *toClient = [self.selfUser.clients anyObject];
    
    //when
    [self.mockTransportSession performRemoteChanges:^( __unused MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [mockConversation encryptAndInsertDataFromClient:fromClient toClient:toClient data:reactionMessage.data];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    //then
    XCTAssertEqual(message.usersReaction.count, 1lu);
    XCTAssertNotNil(message.usersReaction[reactionEmoji]);
    XCTAssertEqual([message.usersReaction[reactionEmoji] count], 1lu);
    XCTAssertEqualObjects([message.usersReaction[reactionEmoji] firstObject], [self userForMockUser:self.user1]);
    XCTAssertEqual(conversation.hiddenMessages.count, 0lu);
}

- (void)testThatAppendingAReactionNotifiesObserverOfAddedReactions;
{
    //given
    XCTAssertTrue([self login]);
    
    [self prefetchRemoteClientByInsertingMessageInConversation:self.selfToUser1Conversation];
    WaitForAllGroupsToBeEmpty(0.5);
    
    MockConversation *mockConversation = self.selfToUser1Conversation;
    ZMConversation *conversation = [self conversationForMockConversation:mockConversation];
    
    __block ZMTextMessage *message;
    [self.userSession performChanges:^{
        message = (ZMTextMessage *)[conversation appendMessageWithText:@"Je t'aime JCVD"];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    MessageChangeObserver *observer = [[MessageChangeObserver alloc] initWithMessage:message];

    // when
    [self.userSession performChanges:^{
        [ZMMessage addReaction:MessageReactionLike toMessage:message];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    //then
    XCTAssertEqual(observer.notifications.count, 1lu);
    MessageChangeInfo *changes = [observer.notifications lastObject];
    XCTAssertTrue(changes.reactionsChanged);
}

- (void)testThatAppendingAReactionNotifiesObserverOfChangesInReactions;
{
    //given
    XCTAssertTrue([self login]);
    
    [self prefetchRemoteClientByInsertingMessageInConversation:self.selfToUser1Conversation];
    WaitForAllGroupsToBeEmpty(0.5);
    
    MockConversation *mockConversation = self.selfToUser1Conversation;
    ZMConversation *conversation = [self conversationForMockConversation:mockConversation];
    
    __block ZMTextMessage *message;
    [self.userSession performChanges:^{
        message = (ZMTextMessage *)[conversation appendMessageWithText:@"Je t'aime JCVD"];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    [self.userSession performChanges:^{
        [ZMMessage addReaction:MessageReactionLike toMessage:message];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    MessageChangeObserver *observer = [[MessageChangeObserver alloc] initWithMessage:message];
    
    [self.userSession performChanges:^{
        // removes reaction for self user
        [ZMMessage removeReactionOnMessage:message];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    //then
    XCTAssertEqual(observer.notifications.count, 1lu);
    MessageChangeInfo *changes = [observer.notifications lastObject];
    XCTAssertTrue(changes.reactionsChanged);
}

- (void)testThatAppendingAReactionNotifiesObserverOfChangesInReactionsWhenExternalUserReact;
{
    //given
    XCTAssertTrue([self login]);
    
    [self prefetchRemoteClientByInsertingMessageInConversation:self.selfToUser1Conversation];
    WaitForAllGroupsToBeEmpty(0.5);
    
    MockConversation *mockConversation = self.selfToUser1Conversation;
    ZMConversation *conversation = [self conversationForMockConversation:mockConversation];
    
    __block ZMTextMessage *message;
    [self.userSession performChanges:^{
        message = (ZMTextMessage *)[conversation appendMessageWithText:@"Je t'aime JCVD"];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    NSString *reactionEmoji = @"❤️";
    [self.userSession performChanges:^{
        [ZMMessage addReaction:MessageReactionLike toMessage:message];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    MessageChangeObserver *observer = [[MessageChangeObserver alloc] initWithMessage:message];
    ZMGenericMessage *reactionMessage = [ZMGenericMessage messageWithEmojiString:reactionEmoji messageID:message.nonce.transportString nonce:[NSUUID UUID].transportString];
    MockUserClient *fromClient = [self.user1.clients anyObject];
    MockUserClient *toClient = [self.selfUser.clients anyObject];
    
    //when
    [self.mockTransportSession performRemoteChanges:^( __unused MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [mockConversation encryptAndInsertDataFromClient:fromClient toClient:toClient data:reactionMessage.data];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    //then
    XCTAssertGreaterThanOrEqual(observer.notifications.count, 1lu);
    MessageChangeInfo *changes = [observer.notifications lastObject];
    XCTAssertTrue(changes.reactionsChanged);

}

- (void)testThatReceivingAReactionThatIsNotHandledDoesntSaveIt;
{
    //given
    XCTAssertTrue([self login]);
    
    [self prefetchRemoteClientByInsertingMessageInConversation:self.selfToUser1Conversation];
    WaitForAllGroupsToBeEmpty(0.5);
    
    MockConversation *mockConversation = self.selfToUser1Conversation;
    ZMConversation *conversation = [self conversationForMockConversation:mockConversation];
    
    __block ZMTextMessage *message;
    [self.userSession performChanges:^{
        message = (ZMTextMessage *)[conversation appendMessageWithText:@"Je t'aime JCVD"];
    }];
    NSUUID *nonce = message.nonce;
    WaitForAllGroupsToBeEmpty(0.5);
    
    NSString *reactionEmoji = @"Jean Robert, j'ai mal aux pieds";
    ZMGenericMessage *reactionMessage = [ZMGenericMessage messageWithEmojiString:reactionEmoji messageID:nonce.transportString nonce:[NSUUID UUID].transportString];
    MockUserClient *fromClient = [self.user1.clients anyObject];
    MockUserClient *toClient = [self.selfUser.clients anyObject];
    
    //when
    [self.mockTransportSession performRemoteChanges:^( __unused MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [mockConversation encryptAndInsertDataFromClient:fromClient toClient:toClient data:reactionMessage.data];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    //then
    XCTAssertEqual(message.usersReaction.count, 0lu);
    XCTAssertEqual(message.reactions.count, 0lu);
}

- (void)testThatReceivingALikeInAClearedConversationDoesNotUnarchiveTheConversation
{
    //given
    XCTAssertTrue([self login]);
    
    [self prefetchRemoteClientByInsertingMessageInConversation:self.selfToUser1Conversation];
    WaitForAllGroupsToBeEmpty(0.5);
    
    MockConversation *mockConversation = self.selfToUser1Conversation;
    ZMConversation *conversation = [self conversationForMockConversation:mockConversation];
    
    __block ZMTextMessage *message;
    [self.userSession performChanges:^{
        message = (ZMTextMessage *)[conversation appendMessageWithText:@"Je t'aime JCVD"];
    }];
    NSUUID *nonce = message.nonce;
    WaitForAllGroupsToBeEmpty(0.5);
    
    NSString *reactionEmoji = @"❤️";

    ZMGenericMessage *reactionMessage = [ZMGenericMessage messageWithEmojiString:reactionEmoji messageID:nonce.transportString nonce:[NSUUID UUID].transportString];
    MockUserClient *fromClient = [self.user1.clients anyObject];
    MockUserClient *toClient = [self.selfUser.clients anyObject];
    
    // when
    [self.userSession performChanges:^{
        [conversation clearMessageHistory];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertTrue(conversation.isArchived);
    
    [self.mockTransportSession performRemoteChanges:^( __unused MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [mockConversation encryptAndInsertDataFromClient:fromClient toClient:toClient data:reactionMessage.data];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    //then
    XCTAssertTrue(conversation.isArchived);
}


- (void)testThatReceivingALikeInAnArchivedConversationDoesNotUnarchiveTheConversation
{
    //given
    XCTAssertTrue([self login]);
    
    [self prefetchRemoteClientByInsertingMessageInConversation:self.selfToUser1Conversation];
    WaitForAllGroupsToBeEmpty(0.5);
    
    MockConversation *mockConversation = self.selfToUser1Conversation;
    ZMConversation *conversation = [self conversationForMockConversation:mockConversation];
    
    __block ZMTextMessage *message;
    [self.userSession performChanges:^{
        message = (ZMTextMessage *)[conversation appendMessageWithText:@"Je t'aime JCVD"];
    }];
    NSUUID *nonce = message.nonce;
    WaitForAllGroupsToBeEmpty(0.5);
    
    NSString *reactionEmoji = @"❤️";
    ZMGenericMessage *reactionMessage = [ZMGenericMessage messageWithEmojiString:reactionEmoji messageID:nonce.transportString nonce:[NSUUID UUID].transportString];
    MockUserClient *fromClient = [self.user1.clients anyObject];
    MockUserClient *toClient = [self.selfUser.clients anyObject];
    
    // when
    [self.userSession performChanges:^{
        [conversation setIsArchived:YES];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertTrue(conversation.isArchived);
    
    [self.mockTransportSession performRemoteChanges:^( __unused MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [mockConversation encryptAndInsertDataFromClient:fromClient toClient:toClient data:reactionMessage.data];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    //then
    XCTAssertTrue(conversation.isArchived);
}

- (void)testThatLikesAreResetWhenEditingAMessage;
{
    //given
    XCTAssertTrue([self login]);
    
    [self prefetchRemoteClientByInsertingMessageInConversation:self.selfToUser1Conversation];
    WaitForAllGroupsToBeEmpty(0.5);
    
    MockConversation *mockConversation = self.selfToUser1Conversation;
    ZMConversation *conversation = [self conversationForMockConversation:mockConversation];
    
    __block ZMTextMessage *message;
    [self.userSession performChanges:^{
        message = (ZMTextMessage *)[conversation appendMessageWithText:@"Je t'aime JCVD"];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    [self.userSession performChanges:^{
        [ZMMessage addReaction:MessageReactionLike toMessage:message];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    // sanity check
    XCTAssertEqual(message.usersReaction.count, 1lu);
    
    // when
    [self.userSession performChanges:^{
        NOT_USED([ZMMessage edit:message newText:@"Je t'aime JCVD, plus que tout!"]);
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    //then
    XCTAssertEqual(message.usersReaction.count, 0lu);
}

- (void)testThatMessageDeletedForMyselfDoesNotAppearWhenLikedBySomeoneElse;
{
    //given
    XCTAssertTrue([self login]);
    
    [self prefetchRemoteClientByInsertingMessageInConversation:self.selfToUser1Conversation];
    WaitForAllGroupsToBeEmpty(0.5);
    
    MockConversation *mockConversation = self.selfToUser1Conversation;
    ZMConversation *conversation = [self conversationForMockConversation:mockConversation];
    
    __block ZMTextMessage *message;
    [self.userSession performChanges:^{
        message = (ZMTextMessage *)[conversation appendMessageWithText:@"Je t'aime JCVD"];
    }];
    NSUUID *nonce = message.nonce;
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.userSession performChanges:^{
        [ZMMessage hideMessage:message];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssertNil([ZMMessage fetchMessageWithNonce:nonce forConversation:conversation inManagedObjectContext:self.userSession.managedObjectContext]);
    
    NSString *reactionEmoji = @"❤️";
    ZMGenericMessage *reactionMessage = [ZMGenericMessage messageWithEmojiString:reactionEmoji messageID:nonce.transportString nonce:[NSUUID UUID].transportString];
    MockUserClient *fromClient = [self.user1.clients anyObject];
    MockUserClient *toClient = [self.selfUser.clients anyObject];
    
    // when
    [self.mockTransportSession performRemoteChanges:^( __unused MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [mockConversation encryptAndInsertDataFromClient:fromClient toClient:toClient data:reactionMessage.data];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    //then
    XCTAssertNil([ZMMessage fetchMessageWithNonce:nonce forConversation:conversation inManagedObjectContext:self.userSession.managedObjectContext]);
}

- (void)testThatWeCanLikeAMessageAfterItWasEditedByItsUser;
{
    XCTAssertTrue([self login]);
    
    [self prefetchRemoteClientByInsertingMessageInConversation:self.selfToUser1Conversation];
    WaitForAllGroupsToBeEmpty(0.5);
    
    MockConversation *mockConversation = self.selfToUser1Conversation;
    ZMConversation *conversation = [self conversationForMockConversation:mockConversation];
    
    MockUserClient *fromClient = [self.user1.clients anyObject];
    MockUserClient *toClient = [self.selfUser.clients anyObject];

    NSUUID *nonce = [NSUUID createUUID];
    ZMGenericMessage *message = [ZMGenericMessage messageWithText:@"JCVD is the best actor known" nonce:nonce.transportString expiresAfter:nil];
    
    [self.mockTransportSession performRemoteChanges:^( __unused  MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [mockConversation encryptAndInsertDataFromClient:fromClient toClient:toClient data:message.data];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    message = [ZMGenericMessage messageWithEditMessage:nonce.transportString newText:@"JCVD is the best actor known in the galaxy!" nonce:[NSUUID createUUID].transportString];
    
    [self.mockTransportSession performRemoteChanges:^( __unused MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [mockConversation encryptAndInsertDataFromClient:fromClient toClient:toClient data:message.data];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    ZMMessage *editedMessage = [ZMMessage fetchMessageWithNonce:nonce forConversation:conversation inManagedObjectContext:self.userSession.managedObjectContext];
    
    // when
    [self.userSession performChanges:^{
        [ZMMessage addReaction:MessageReactionLike toMessage:editedMessage];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    //then
    XCTAssertEqual(editedMessage.usersReaction.count, 1lu);

}

- (void)testThatWeSeeLikeFromBlockedUserInGroupConversation;
{
    XCTAssertTrue([self login]);
    
    [self prefetchRemoteClientByInsertingMessageInConversation:self.groupConversation];
    WaitForAllGroupsToBeEmpty(0.5);
    
    MockConversation *mockConversation = self.groupConversation;
    ZMConversation *conversation = [self conversationForMockConversation:mockConversation];
    
    [self.userSession performChanges:^{
        ZMUser *blockedUser = [self userForMockUser:self.user1];
        [blockedUser block];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    __block ZMTextMessage *message;
    [self.userSession performChanges:^{
        message = (ZMTextMessage *)[conversation appendMessageWithText:@"Je t'aime JCVD"];
    }];
    NSUUID *nonce = message.nonce;
    WaitForAllGroupsToBeEmpty(0.5);
        
    NSString *reactionEmoji = @"❤️";
    ZMGenericMessage *reactionMessage = [ZMGenericMessage messageWithEmojiString:reactionEmoji messageID:nonce.transportString nonce:[NSUUID UUID].transportString];
    MockUserClient *fromClient = [self.user1.clients anyObject];
    MockUserClient *toClient = [self.selfUser.clients anyObject];
    
    // when
    [self.mockTransportSession performRemoteChanges:^( __unused MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [mockConversation encryptAndInsertDataFromClient:fromClient toClient:toClient data:reactionMessage.data];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    //then
    XCTAssertEqual(message.usersReaction.count, 1lu);
}

@end

