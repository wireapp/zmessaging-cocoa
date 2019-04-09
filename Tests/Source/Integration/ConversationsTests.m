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

- (void)testThatServiceUsersAreRemovedFromAConversationWhenTheyAreRemovedRemotely
{
    // given
    [self createTeamAndConversations];
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertTrue([self login]);
    
    ZMUser *bot = [self userForMockUser:self.serviceUser];
    ZMConversation *groupConversation = [self conversationForMockConversation:self.groupConversationWithServiceUser];
    XCTAssertNotNil(groupConversation);
    XCTAssertTrue([groupConversation.activeParticipants containsObject:bot]);
    
    // when
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [self.groupConversationWithServiceUser removeUsersByUser:session.selfUser removedUser:self.serviceUser];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertFalse([groupConversation.activeParticipants containsObject:bot]);
    XCTAssertEqual(groupConversation.keysThatHaveLocalModifications.count, 0u);
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
    ZMConversation *conversation1 = [self conversationForMockConversation:self.selfToUser1Conversation];
    NSUInteger previousIndex = [conversationList indexOfObject:conversation1];
    
    XCTAssertEqual(conversationList.count, 5u);
    
    ConversationListChangeObserver *observer = [[ConversationListChangeObserver alloc] initWithConversationList:conversationList];

    // when
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> ZM_UNUSED *session) {
        ZMGenericMessage *message = [ZMGenericMessage messageWithContent:[ZMText textWith:@"some message" mentions:@[] linkPreviews:@[] replyingTo:nil] nonce:NSUUID.createUUID];
        [self.selfToUser1Conversation encryptAndInsertDataFromClient:self.user1.clients.anyObject toClient:self.selfUser.clients.anyObject data:message.data];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(observer.notifications.count, 1u);
    ConversationListChangeInfo *note1 = observer.notifications.lastObject;
    XCTAssertEqualObjects(note1.zm_movedIndexPairs.firstObject, [[ZMMovedIndex alloc] initFrom:previousIndex to:0]);
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
        ZMGenericMessage *message = [ZMGenericMessage messageWithContent:[ZMText textWith:@"Bla bla bla" mentions:@[] linkPreviews:@[] replyingTo:nil] nonce:NSUUID.createUUID];
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
    (void) conversation1.allMessages; // Make sure we've faulted in the messages
    ZMConversation *conversation2 = [self conversationForMockConversation:self.selfToUser2Conversation];
    (void) conversation2.allMessages; // Make sure we've faulted in the messages
    
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
    NSUInteger previousIndex1 = [conversationList indexOfObject:conversation1];
    
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> ZM_UNUSED *session) {
        ZMGenericMessage *message = [ZMGenericMessage messageWithContent:[ZMText textWith:messageText1 mentions:@[] linkPreviews:@[] replyingTo:nil] nonce:nonce1];
        [self.selfToUser1Conversation encryptAndInsertDataFromClient:self.user1.clients.anyObject toClient:toClient data:message.data];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(conversationList[0], conversation1);
    XCTAssertGreaterThanOrEqual(observer.notifications.count, 1u);
    ConversationListChangeInfo *note1 = observer.notifications.lastObject;
    XCTAssertEqualObjects(note1.zm_movedIndexPairs.firstObject, [[ZMMovedIndex alloc] initFrom:previousIndex1 to:0]);
    
    ZMMessage *receivedMessage1 = conversation1.lastMessage;
    XCTAssertEqualObjects(receivedMessage1.textMessageData.messageText, messageText1);
    NSUInteger previousIndex2 = [conversationList indexOfObject:conversation2];
    
    // send second message
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> ZM_UNUSED *session) {
        ZMGenericMessage *message = [ZMGenericMessage messageWithContent:[ZMText textWith:messageText2 mentions:@[] linkPreviews:@[] replyingTo:nil] nonce:nonce2];
        [self.selfToUser2Conversation encryptAndInsertDataFromClient:self.user1.clients.anyObject toClient:toClient data:message.data];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(conversationList[0], conversation2);
    XCTAssertGreaterThanOrEqual(observer.notifications.count, 2u);
    ConversationListChangeInfo *note2 = [observer.notifications objectAtIndex:1];
    XCTAssertEqualObjects(note2.zm_movedIndexPairs.firstObject, [[ZMMovedIndex alloc] initFrom:previousIndex2 to:0]);
    
    ZMMessage *receivedMessage2 = conversation2.lastMessage;
    XCTAssertEqualObjects(receivedMessage2.textMessageData.messageText, messageText2);
    NSUInteger previousIndex3 = [conversationList indexOfObject:conversation1];
    
    // send first message again
    
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> ZM_UNUSED *session) {
        ZMGenericMessage *message = [ZMGenericMessage messageWithContent:[ZMText textWith:messageText3 mentions:@[] linkPreviews:@[] replyingTo:nil] nonce:nonce3];
        [self.selfToUser1Conversation encryptAndInsertDataFromClient:self.user1.clients.anyObject toClient:toClient data:message.data];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(conversationList[0], conversation1);
    XCTAssertGreaterThanOrEqual(observer.notifications.count, 3u);
    ConversationListChangeInfo *note3 = observer.notifications.lastObject;
    XCTAssertEqualObjects(note3.zm_movedIndexPairs.firstObject, [[ZMMovedIndex alloc] initFrom:previousIndex3 to:0]);
    
    ZMMessage *receivedMessage3 = conversation1.lastMessage;
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
        ZMGenericMessage *knock = [ZMGenericMessage messageWithContent:[ZMKnock knock] nonce:NSUUID.createUUID];
        [self.self.selfToUser2Conversation encryptAndInsertDataFromClient:self.user2.clients.anyObject toClient:self.selfUser.clients.anyObject data:knock.data];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [conversationListChangeObserver clearNotifications];
    XCTAssertNotEqual(oneToOneConversation, conversationList[0]); // make sure conversation is not on top
    
    NSUInteger oneToOneIndex = [conversationList indexOfObject:oneToOneConversation];
    
    // when
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        NOT_USED(session);
        ZMGenericMessage *knock = [ZMGenericMessage messageWithContent:[ZMKnock knock] nonce:NSUUID.createUUID];
        [self.self.selfToUser1Conversation encryptAndInsertDataFromClient:self.user1.clients.anyObject toClient:self.selfUser.clients.anyObject data:knock.data];
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(oneToOneConversation, conversationList[0]); // make sure conversation is not on top
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
    ZMConversation *newConnectionConversation = [[self userForMockUser:mockUser] oneToOneConversation];
    
    WaitForAllGroupsToBeEmpty(0.5);

    ZMConversationList *conversationList = [ZMConversationList conversationsInUserSession:self.userSession];

    [self.mockTransportSession performRemoteChanges:^(__unused MockTransportSession<MockTransportSessionObjectCreation> *session) {
        ZMGenericMessage *message = [ZMGenericMessage messageWithContent:[ZMText textWith:@"some message" mentions:@[] linkPreviews:@[] replyingTo:nil] nonce:NSUUID.createUUID];
        [self.selfToUser1Conversation encryptAndInsertDataFromClient:self.user1.clients.anyObject toClient:self.selfUser.clients.anyObject data:message.data];
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssertEqualObjects(oneToOneConversation, conversationList[0]);
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
    XCTAssertEqual([(ZMMovedIndex *)moves.firstObject to], 0u);
    
    XCTAssertEqualObjects(newConnectionConversation, conversationList[0]);
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
        XCTAssertEqualObjects(request.payload.asDictionary[@"otr_archived_ref"], conversation.archivedChangedTimestamp.transportString);
        XCTAssertEqualObjects(request.payload.asDictionary[@"otr_archived"], @(conversation.isArchived));
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
    XCTAssertEqualObjects(request.payload.asDictionary[@"otr_archived_ref"], conversation.archivedChangedTimestamp.transportString);
    XCTAssertEqualObjects(request.payload.asDictionary[@"otr_archived"], @(conversation.isArchived));
}

- (void)testThatOnlyMentionsConversationIsSynchronizedToTheBackend
{
    {
        // given
        XCTAssertTrue([self login]);
        [self.mockTransportSession resetReceivedRequests];
        
        ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
        
        // when
        [self.userSession performChanges:^{
            conversation.isFullyMuted = YES;
        }];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        ZMTransportRequest *request = self.mockTransportSession.receivedRequests.firstObject;
        NSString *expectedPath = [NSString stringWithFormat:@"/conversations/%@/self", self.groupConversation.identifier];
        XCTAssertEqualObjects(request.path, expectedPath);
        XCTAssertEqual(request.method, ZMMethodPUT);
        XCTAssertEqualObjects(conversation.lastServerTimeStamp, conversation.silencedChangedTimestamp);
        XCTAssertEqualObjects(request.payload.asDictionary[@"otr_muted_ref"], conversation.silencedChangedTimestamp.transportString);
        XCTAssertEqualObjects(request.payload.asDictionary[@"otr_muted"], @(conversation.isFullyMuted));
        XCTAssertEqualObjects(request.payload.asDictionary[@"otr_muted_status"], @(conversation.isFullyMuted ? 3 : 0));
    }
    
    // Tears down context(s) &
    // Re-create contexts
    [self recreateSessionManagerAndDeleteLocalData];
    
    {
        // Wait for sync to be done
        XCTAssertTrue([self login]);
        
        // then
        ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
        XCTAssertTrue(conversation.isFullyMuted);
    }
    
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
            conversation.isFullyMuted = YES;
        }];
        WaitForAllGroupsToBeEmpty(0.5);

        // then
        ZMTransportRequest *request = self.mockTransportSession.receivedRequests.firstObject;
        NSString *expectedPath = [NSString stringWithFormat:@"/conversations/%@/self", self.groupConversation.identifier];
        XCTAssertEqualObjects(request.path, expectedPath);
        XCTAssertEqual(request.method, ZMMethodPUT);
        XCTAssertEqualObjects(conversation.lastServerTimeStamp, conversation.silencedChangedTimestamp);
        XCTAssertEqualObjects(request.payload.asDictionary[@"otr_muted_ref"], conversation.silencedChangedTimestamp.transportString);
        XCTAssertEqualObjects(request.payload.asDictionary[@"otr_muted"], @(conversation.isFullyMuted));
        XCTAssertEqualObjects(request.payload.asDictionary[@"otr_muted_status"], @(conversation.isFullyMuted ? 3 : 0));
    }

    // Tears down context(s) &
    // Re-create contexts
    [self recreateSessionManagerAndDeleteLocalData];

    {
        // Wait for sync to be done
        XCTAssertTrue([self login]);

        // then
        ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
        XCTAssertTrue(conversation.isFullyMuted);
    }

}

- (void)testThatUnsilencing_OnlyMentionsConversation_IsSynchronizedToTheBackend
{
    // given
    XCTAssertTrue([self login]);

    ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
    [self.userSession performChanges:^{
        conversation.isMutedDisplayingMentions = YES;
    }];

    WaitForAllGroupsToBeEmpty(0.5);
    [self.mockTransportSession resetReceivedRequests];

    // when
    [self.userSession performChanges:^{
        conversation.isMutedDisplayingMentions = NO;
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    ZMTransportRequest *request = self.mockTransportSession.receivedRequests.firstObject;
    NSString *expectedPath = [NSString stringWithFormat:@"/conversations/%@/self", self.groupConversation.identifier];
    XCTAssertEqualObjects(request.path, expectedPath);
    XCTAssertEqual(request.method, ZMMethodPUT);
    XCTAssertEqualObjects(request.payload.asDictionary[@"otr_muted"], @0);
    XCTAssertEqualObjects(request.payload.asDictionary[@"otr_muted_ref"], conversation.lastServerTimeStamp.transportString);
    XCTAssertEqualObjects(request.payload.asDictionary[@"otr_muted_status"], @0);
}

- (void)testThatUnsilencingAConversationIsSynchronizedToTheBackend
{
    // given
    XCTAssertTrue([self login]);
    
    ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
    [self.userSession performChanges:^{
        conversation.isFullyMuted = YES;
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
    [self.mockTransportSession resetReceivedRequests];
    
    // when
    [self.userSession performChanges:^{
        conversation.isFullyMuted = NO;
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    ZMTransportRequest *request = self.mockTransportSession.receivedRequests.firstObject;
    NSString *expectedPath = [NSString stringWithFormat:@"/conversations/%@/self", self.groupConversation.identifier];
    XCTAssertEqualObjects(request.path, expectedPath);
    XCTAssertEqual(request.method, ZMMethodPUT);
    XCTAssertEqualObjects(request.payload.asDictionary[@"otr_muted"], @0);
    XCTAssertEqualObjects(request.payload.asDictionary[@"otr_muted_ref"], conversation.lastServerTimeStamp.transportString);
    XCTAssertEqualObjects(request.payload.asDictionary[@"otr_muted_status"], @0);
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
    (void) conversation.allMessages; // Make sure we've faulted in the messages
    XCTAssertNotNil(conversation);
    XCTAssertEqualObjects(conversation.connectedUser, user1);
    XCTAssertEqual(conversation.conversationType, ZMConversationTypeOneOnOne);

    ZMConversationList *active = [ZMConversationList conversationsInUserSession:self.userSession];
    XCTAssertEqual(active.count, 5u);
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

    XCTAssertEqual(active.count, 4u);
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
            conversation.isFullyMuted = YES;
        }
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertTrue(conversation.isArchived);
    if (isSilenced) {
        XCTAssertTrue(conversation.isFullyMuted);
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
        ZMGenericMessage *message = [ZMGenericMessage messageWithContent:[ZMText textWith:@"Some text" mentions:@[] linkPreviews:@[] replyingTo:nil] nonce:NSUUID.createUUID];
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
        ZMGenericMessage *message = [ZMGenericMessage messageWithContent:[ZMText textWith:@"Some text" mentions:@[] linkPreviews:@[] replyingTo:nil] nonce:NSUUID.createUUID];
        MockUser *fromUser = self.groupConversation.activeUsers.lastObject;
        [self.groupConversation encryptAndInsertDataFromClient:fromUser.clients.anyObject toClient:self.selfUser.clients.anyObject data:message.data];
    }];
}

- (void)testThatAddingAnImageToAnArchivedConversation_Unarchives_ThisConversation
{
    // expect
    BOOL shouldUnarchive = YES;

    ZMGenericMessage *message = [ZMGenericMessage messageWithContent:[ZMAsset assetWithOriginalWithImageSize:CGSizeMake(10, 10) mimeType:@"image/jpeg" size:123] nonce:NSUUID.createUUID];

    // when
    [self checkThatItUnarchives:shouldUnarchive silenced:NO mockConversation:self.groupConversation withBlock:^(MockTransportSession<MockTransportSessionObjectCreation> ZM_UNUSED *session) {
        MockUser *fromUser = self.groupConversation.activeUsers.lastObject;
        [self.groupConversation encryptAndInsertDataFromClient:fromUser.clients.anyObject toClient:self.selfUser.clients.anyObject data:message.data];
    }];
}

- (void)testThatAddingAnImageToAnArchived_AndSilenced_Conversation_DoesNotUnarchive_ThisConversation
{
    // expect
    BOOL shouldUnarchive = NO;

    ZMGenericMessage *message = [ZMGenericMessage messageWithContent:[ZMAsset assetWithOriginalWithImageSize:CGSizeMake(10, 10) mimeType:@"image/jpeg" size:123] nonce:NSUUID.createUUID];

    // when
    [self checkThatItUnarchives:shouldUnarchive silenced:YES mockConversation:self.groupConversation withBlock:^(MockTransportSession<MockTransportSessionObjectCreation> ZM_UNUSED *session) {
        MockUser *fromUser = self.groupConversation.activeUsers.lastObject;
        [self.groupConversation encryptAndInsertDataFromClient:fromUser.clients.anyObject toClient:self.selfUser.clients.anyObject data:message.data];
    }];
}

- (void)testThatAddingAnKnockToAnArchivedConversation_Unarchives_ThisConversation
{
    // expect
    BOOL shouldUnarchive = YES;

    // when
    [self checkThatItUnarchives:shouldUnarchive silenced:NO mockConversation:self.groupConversation withBlock:^(MockTransportSession<MockTransportSessionObjectCreation> ZM_UNUSED *session) {
        ZMGenericMessage *knock = [ZMGenericMessage messageWithContent:[ZMKnock knock] nonce:NSUUID.createUUID];
        MockUser *fromUser = self.groupConversation.activeUsers.lastObject;
        [self.groupConversation encryptAndInsertDataFromClient:fromUser.clients.anyObject toClient:self.selfUser.clients.anyObject data:knock.data];
    }];
}

- (void)testThatAddingAnKnockToAnArchived_AndSilenced_Conversation_DoesNotUnarchive_ThisConversation
{
    // expect
    BOOL shouldUnarchive = NO;

    // when
    [self checkThatItUnarchives:shouldUnarchive silenced:YES mockConversation:self.groupConversation withBlock:^(MockTransportSession<MockTransportSessionObjectCreation> ZM_UNUSED *session) {
        ZMGenericMessage *knock = [ZMGenericMessage messageWithContent:[ZMKnock knock] nonce:NSUUID.createUUID];
        MockUser *fromUser = self.groupConversation.activeUsers.lastObject;
        [self.groupConversation encryptAndInsertDataFromClient:fromUser.clients.anyObject toClient:self.selfUser.clients.anyObject data:knock.data];
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
    // given
    XCTAssertTrue([self login]);

    MockUser *mockUser = [self createSentConnectionFromUserWithName:@"Hans" uuid:NSUUID.createUUID];
    ZMConversation *conversation = [[self userForMockUser:mockUser] oneToOneConversation];
    
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
    XCTAssertFalse(conversation.isArchived);
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
        ZMGenericMessage *message = [ZMGenericMessage messageWithContent:[ZMText textWith:@"Will insert this to have a message to read" mentions:@[] linkPreviews:@[] replyingTo:nil] nonce:NSUUID.createUUID];
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
        ZMGenericMessage *message = [ZMGenericMessage messageWithContent:[ZMText textWith:@"This should increase the unread count" mentions:@[] linkPreviews:@[] replyingTo:nil] nonce:NSUUID.createUUID];
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
    NSUInteger expectedRequests = (NSUInteger)ceil(numberOfConversations * 1.f / ZMConversationTranscoderListPageSize + 0.5f);
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
        for (NSUInteger i = 0; i < messagesCount - conversation.allMessages.count; i++) {
            ZMGenericMessage *message = [ZMGenericMessage messageWithContent:[ZMText textWith:[NSString stringWithFormat:@"foo %lu", (unsigned long)i] mentions:@[] linkPreviews:@[] replyingTo:nil] nonce:NSUUID.createUUID];
            [mockConversation encryptAndInsertDataFromClient:fromClient toClient:toClient data:message.data];
        }
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    conversation = [self conversationForMockConversation:mockConversation];
    [conversation markAsRead];
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssertEqual(conversation.allMessages.count, messagesCount);
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
        [self.mockTransportSession resetReceivedRequests];
        
        // when
    
        [self.userSession performChanges:^{
            [conversation clearMessageHistory];
        }];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        XCTAssertEqual(conversation.allMessages.count, 0u);
        XCTAssertFalse([conversationDirectory.conversationsIncludingArchived containsObject:conversation]);
        
        ZMTransportRequest *firstRequest = self.mockTransportSession.receivedRequests.firstObject;
        NSString *expectedPath = [NSString stringWithFormat:@"/conversations/%@/self", conversation.remoteIdentifier.transportString];
        XCTAssertEqualObjects(firstRequest.payload.asDictionary[@"otr_archived_ref"], conversation.lastServerTimeStamp.transportString);
        XCTAssertEqualObjects(firstRequest.payload.asDictionary[@"otr_archived"], @1);

        XCTAssertEqualObjects(firstRequest.path, expectedPath);
        XCTAssertEqual(firstRequest.method, ZMMethodPUT);
        
        ZMUser *selfUser = [self userForMockUser:self.selfUser];
        ZMTransportRequest *lastRequest = self.mockTransportSession.receivedRequests.lastObject;
        NSString *selfConversationPath = [NSString stringWithFormat:@"/conversations/%@/otr/messages", selfUser.remoteIdentifier.transportString];
        XCTAssertNotNil(lastRequest.binaryData);
        XCTAssertEqualObjects(lastRequest.path, selfConversationPath);
        XCTAssertEqual(lastRequest.method, ZMMethodPOST);
        
    }
    conversation = nil;
    [self recreateSessionManagerAndDeleteLocalData];
    WaitForAllGroupsToBeEmpty(0.5);

    {
        // Wait for sync to be done
        XCTAssertTrue([self login]);
    
        // then
        conversation = [self conversationForMockConversation:self.groupConversation];
        WaitForAllGroupsToBeEmpty(0.5);

        XCTAssertEqual(conversation.allMessages.count, 2u);
        ZMSystemMessage *message = (ZMSystemMessage *)conversation.lastMessage;
        XCTAssertEqual(message.systemMessageType, ZMSystemMessageTypeUsingNewDevice);

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
    
    ZMConversationListDirectory *conversationDirectory = self.userSession.managedObjectContext.conversationListDirectory;
    NSManagedObjectID *conversationID = conversation.objectID;
    
   
    // when removing messages remotely
    {
        [self remotelyAppendSelfConversationWithZMClearedForMockConversation:self.groupConversation atTime:conversation.lastServerTimeStamp];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        XCTAssertEqual(conversation.allMessages.count, 0u);
    }
    
    // when adding new messages
    
    [self.userSession performChanges:^{
        [self spinMainQueueWithTimeout:1]; // if the message is sent within the same second of clearing the window, it will not be added when resyncing
        id<ZMConversationMessage> message = [conversation appendMessageWithText:@"lalala"];
        [conversation markMessagesAsReadUntil:message];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertEqual(conversation.allMessages.count, 1u);
    
    [self recreateSessionManagerAndDeleteLocalData];
    WaitForAllGroupsToBeEmpty(0.5);
    
    {
        // Wait for sync to be done
        XCTAssertTrue([self login]);
        
        // then
        conversation = [self conversationForMockConversation:self.groupConversation];
        WaitForAllGroupsToBeEmpty(0.5);
        
        XCTAssertTrue([conversationDirectory.conversationsIncludingArchived.objectIDs containsObject:conversationID]);
    }
}

- (void)testThatDeletedConversationsStayDeletedAfterResyncing
{
    //given
    const NSUInteger messagesCount = 5;
    [self loginAndFillConversationWithMessages:self.groupConversation messagesCount:messagesCount];
    
    ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
    XCTAssertEqual(conversation.allMessages.count, 5lu);
    
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
        XCTAssertEqual(conversation.allMessages.count, 0u);
        XCTAssertFalse([conversationDirectory.conversationsIncludingArchived containsObject:conversation]);
    }
    
    conversation = nil;
    [self recreateSessionManagerAndDeleteLocalData];
    WaitForAllGroupsToBeEmpty(0.5);
    
    {
        // Wait for sync to be done
        XCTAssertTrue([self login]);
        
        // then
        conversation = [self conversationForMockConversation:self.groupConversation];
        WaitForAllGroupsToBeEmpty(0.5);
        
        ZMSystemMessage *message = (ZMSystemMessage *)conversation.lastMessage;
        XCTAssertEqual(message.systemMessageType, ZMSystemMessageTypeUsingNewDevice);
        
        XCTAssertEqual(conversation.allMessages.count, 2u);
        XCTAssertEqualObjects([conversation.lastMessage objectID], [message objectID]);
        
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
    
    XCTAssertEqual(conversation.allMessages.count, 0u);
    
    // when
    
    [self.mockTransportSession performRemoteChanges:^(ZM_UNUSED id session) {
        [self spinMainQueueWithTimeout:1]; // if the action happens within the same second the user clears the history, the event is not added
        ZMGenericMessage *message = [ZMGenericMessage messageWithContent:[ZMText textWith:@"foo" mentions:@[] linkPreviews:@[] replyingTo:nil] nonce:NSUUID.createUUID];
        [self.groupConversation encryptAndInsertDataFromClient:self.user2.clients.anyObject toClient:self.selfUser.clients.anyObject data:message.data];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    conversation = [self conversationForMockConversation:self.groupConversation];
    XCTAssertEqual(conversation.allMessages.count, 1u);
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
    XCTAssertEqual(conversation.allMessages.count, 0u);
    // when
    
    [self.mockTransportSession performRemoteChanges:^(ZM_UNUSED id session) {
        [self spinMainQueueWithTimeout:1]; // if the action happens within the same second the user clears the history, the event is not added
        [self.groupConversation removeUsersByUser:self.user2 removedUser:self.user3];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    conversation = [self conversationForMockConversation:self.groupConversation];

    XCTAssertEqual(conversation.allMessages.count, 1u);
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
    XCTAssertEqual(conversation.allMessages.count, 0u);

    // when
    
    [self.userSession performChanges:^{
        [conversation revealClearedConversation];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    conversation = [self conversationForMockConversation:self.groupConversation];
    XCTAssertEqual(conversation.allMessages.count, 0u);
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
    XCTAssertEqual(conversation.allMessages.count, 1u); // "You started using this device" message
    
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
    
    XCTAssertEqual(conversation.allMessages.count, 6u);

    NSArray *remainingMessages = @[message3, message2];
    NSDate *cleared = message1.serverTimestamp;
    
    // when
    [self remotelyAppendSelfConversationWithZMClearedForMockConversation:self.selfToUser1Conversation atTime:cleared];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual([conversation.clearedTimeStamp timeIntervalSince1970], [cleared timeIntervalSince1970]);
    XCTAssertEqual(conversation.allMessages.count, 2u);
    AssertArraysContainsSameObjects([conversation lastMessagesWithLimit:10], remainingMessages);
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
    ZMGenericMessage *reactionMessage = [ZMGenericMessage messageWithContent:[ZMReaction reactionWithEmoji:reactionEmoji messageID:nonce] nonce:NSUUID.createUUID];
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
    ZMGenericMessage *reactionMessage = [ZMGenericMessage messageWithContent:[ZMReaction reactionWithEmoji:reactionEmoji messageID:message.nonce] nonce:NSUUID.createUUID];
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
    ZMGenericMessage *reactionMessage = [ZMGenericMessage messageWithContent:[ZMReaction reactionWithEmoji:reactionEmoji messageID:nonce] nonce:NSUUID.createUUID];
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

    ZMGenericMessage *reactionMessage = [ZMGenericMessage messageWithContent:[ZMReaction reactionWithEmoji:reactionEmoji messageID:nonce] nonce:NSUUID.createUUID];
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
    ZMGenericMessage *reactionMessage = [ZMGenericMessage messageWithContent:[ZMReaction reactionWithEmoji:reactionEmoji messageID:nonce] nonce:NSUUID.createUUID];
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
        [message.textMessageData editText:@"Je t'aime JCVD, plus que tout!" mentions:@[] fetchLinkPreview:NO];
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
    ZMGenericMessage *reactionMessage = [ZMGenericMessage messageWithContent:[ZMReaction reactionWithEmoji:reactionEmoji messageID:nonce] nonce:NSUUID.createUUID];
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
    ZMGenericMessage *message = [ZMGenericMessage messageWithContent:[ZMText textWith:@"JCVD is the best actor known" mentions:@[] linkPreviews:@[] replyingTo:nil] nonce:nonce];
    
    [self.mockTransportSession performRemoteChanges:^( __unused  MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [mockConversation encryptAndInsertDataFromClient:fromClient toClient:toClient data:message.data];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    message = [ZMGenericMessage messageWithContent:[ZMText textWith:@"JCVD is the best actor known in the galaxy!" mentions:@[] linkPreviews:@[] replyingTo:nil] nonce:NSUUID.createUUID];
    
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
    ZMGenericMessage *reactionMessage = [ZMGenericMessage messageWithContent:[ZMReaction reactionWithEmoji:reactionEmoji messageID:nonce] nonce:NSUUID.createUUID];
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

