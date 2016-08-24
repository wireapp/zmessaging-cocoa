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

@import ZMCDataModel;
@import zmessaging;
@import ZMTransport;
@import ZMCMockTransport;
@import ZMUtilities;
@import ZMTesting;

#import "MessagingTest.h"
#import "ZMUserSession.h"
#import "IntegrationTestBase.h"
#import "ZMTestNotifications.h"
#import "ZMUserSession+Internal.h"
#import "ZMConversationTranscoder+Internal.h"
#import <zmessaging/zmessaging-Swift.h>
#import "ConversationTestsBase.h"

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
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
}

- (void)testThatAConversationIsResyncedAfterRestartingFromScratch
{
    NSString *conversationName = @"My conversation";
    {
        // Create a UI context
        XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
        // Get the users:
        ZMUser *user1 = [self userForMockUser:self.user1];
        XCTAssertNotNil(user1);
        ZMUser *user2 = [self userForMockUser:self.user2];
        XCTAssertNotNil(user2);
        
        // Create a conversation
        __block ZMConversation *conversation;
        [self.userSession performChanges:^{
            conversation = [ZMConversation insertGroupConversationIntoUserSession:self.userSession withParticipants:@[user1, user2]];
            conversation.userDefinedName = conversationName;
        }];
        
        // Wait for merge ui->sync to be done
        WaitForEverythingToBeDone();
        XCTAssert([self waitOnMainLoopUntilBlock:^BOOL{
            return conversation.lastModifiedDate != nil;
        } timeout:0.5]);
    }
    
    // Tears down context(s) &
    // Re-create contexts
    [self recreateUserSessionAndWipeCache:YES];
    
    {
        // Wait for sync to be done
        XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
        WaitForEverythingToBeDone();
        
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
        XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
        // Get the group conversation
        ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
        XCTAssertNotNil(conversation);
        // Change the name & save
        conversation.userDefinedName = name;
        [self.userSession saveOrRollbackChanges];
        XCTAssertFalse(conversation.hasChanges, @"Rollback?");
        XCTAssertTrue([conversation hasLocalModificationsForKey:ZMConversationUserDefinedNameKey]);
        
        // Wait for merge ui->sync to be done
        WaitForEverythingToBeDone();
        
        XCTAssertFalse([conversation hasLocalModificationsForKey:ZMConversationUserDefinedNameKey]);
    }
    
    // Tears down context(s) &
    // Re-create contexts
    [self recreateUserSessionAndWipeCache:YES];
    
    // Wait for sync to be done
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    
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
        XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
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
        ZMConversation *syncConversation = [self.syncMOC objectWithID:conversation.objectID];
        
        XCTAssertFalse([syncConversation hasLocalModificationsForKey:ZMConversationUserDefinedNameKey]);
        XCTAssertFalse([conversation hasLocalModificationsForKey:ZMConversationUserDefinedNameKey]);
        XCTAssertEqual(self.mockTransportSession.receivedRequests.count, 0lu);
    }
    
    // Tears down context(s) &
    // Re-create contexts
    [self recreateUserSessionAndWipeCache:YES];
    
    // Wait for sync to be done
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    
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
        XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
        
        ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
        XCTAssertNotNil(conversation);
        
        ZMUser *user = [self userForMockUser:self.user3];
        
        XCTAssertTrue([conversation.activeParticipants containsObject:user]);
        [self.userSession performChanges:^{
            [conversation removeParticipant:user];

        }];
        XCTAssertFalse([conversation.activeParticipants containsObject:user]);

        // Wait for merge ui->sync to be done
        WaitForEverythingToBeDone();
    }

    // Tears down context(s) &
    // Re-create contexts
    [self recreateUserSessionAndWipeCache:YES];
    XCTAssert([self logInAndWaitForSyncToBeComplete]);
    
    // Wait for sync to be done
    WaitForEverythingToBeDone();
    
    {
        ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
        XCTAssertNotNil(conversation);
        ZMUser *user = [self userForMockUser:self.user3];

        XCTAssertFalse([conversation.activeParticipants containsObject:user]);
        XCTAssertTrue([conversation.inactiveParticipants containsObject:user]);
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
            [self storeRemoteIDForObject:connectedUserNotInConv];
            
            MockConversation *selfToConnectedNotInConvConversation = [session insertOneOnOneConversationWithSelfUser:self.selfUser otherUser:connectedUserNotInConv];
            selfToConnectedNotInConvConversation.creator = self.selfUser;
            
            MockConnection *connectionSelfToConnectedUserNotInConv = [session insertConnectionWithSelfUser:self.selfUser toUser:connectedUserNotInConv];
            connectionSelfToConnectedUserNotInConv.status = @"accepted";
            connectionSelfToConnectedUserNotInConv.lastUpdate = [NSDate dateWithTimeIntervalSinceNow:-3];
            connectionSelfToConnectedUserNotInConv.conversation = selfToConnectedNotInConvConversation;
        }];
        
        XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
        
        ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
        XCTAssertNotNil(conversation);
        
        ZMUser *user = [self userForMockUser:connectedUserNotInConv];
        
        XCTAssertFalse([conversation.activeParticipants containsObject:user]);
        [self.userSession performChanges:^{
            [conversation addParticipant:user];
        }];
        XCTAssertTrue([conversation.activeParticipants containsObject:user]);
        
        // Wait for merge ui->sync to be done
        WaitForEverythingToBeDone();
    }
    
    // Tears down context(s) &
    // Re-create contexts
    [self recreateUserSessionAndWipeCache:YES];
    XCTAssert([self logInAndWaitForSyncToBeComplete]);
    
    // Wait for sync to be done
    WaitForEverythingToBeDone();
    
    {
        ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
        XCTAssertNotNil(conversation);
        
        ZMUser *user = [self userForMockUser:connectedUserNotInConv];
        
        XCTAssertTrue([conversation.activeParticipants containsObject:user]);
        XCTAssertFalse([conversation.inactiveParticipants containsObject:user]);
    }
    
}

@end

@implementation ConversationTests (DisplayName)

- (void)testThatReceivingAPushEventForNameChangeChangesTheConversationName
{
    
    // given
    // Create a UI context
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
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
    [observer tearDown];

}

@end


#pragma mark - Participants
@implementation ConversationTests (Participants)

- (void)testThatParticipantsAreAddedToAConversationWhenTheyAreAddedRemotely
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForEverythingToBeDone();
    
    ZMConversation *groupConversation = [self conversationForMockConversation:self.groupConversation];
    XCTAssertNotNil(groupConversation);
    
    // when
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [self.groupConversation addUsersByUser:session.selfUser addedUsers:@[self.user4]];
    }];
    WaitForEverythingToBeDone();
    
    // then
    ZMUser *user4 = [self userForMockUser:self.user4];
    XCTAssertTrue([groupConversation.activeParticipants containsObject:user4]);
    XCTAssertFalse([groupConversation.inactiveParticipants containsObject:user4]);
    XCTAssertEqual(groupConversation.keysThatHaveLocalModifications.count, 0u);
}

- (void)testThatParticipantsAreRemovedFromAConversationWhenTheyAreRemovedRemotely
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForEverythingToBeDone();
    
    ZMUser *user3 = [self userForMockUser:self.user3];
    ZMConversation *groupConversation = [self conversationForMockConversation:self.groupConversation];
    XCTAssertNotNil(groupConversation);
    XCTAssertTrue([groupConversation.activeParticipants containsObject:user3]);
    
    // when
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [self.groupConversation removeUsersByUser:session.selfUser removedUser:self.user3];
    }];
    WaitForEverythingToBeDone();
    
    // then
    XCTAssertFalse([groupConversation.activeParticipants containsObject:user3]);
    XCTAssertTrue([groupConversation.inactiveParticipants containsObject:user3]);
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
            [self storeRemoteIDForObject:connectedUserNotInConv];
            
            MockConversation *selfToConnectedNotInConvConversation = [session insertOneOnOneConversationWithSelfUser:self.selfUser otherUser:connectedUserNotInConv];
            selfToConnectedNotInConvConversation.creator = self.selfUser;
            
            MockConnection *connectionSelfToConnectedUserNotInConv = [session insertConnectionWithSelfUser:self.selfUser toUser:connectedUserNotInConv];
            connectionSelfToConnectedUserNotInConv.status = @"accepted";
            connectionSelfToConnectedUserNotInConv.lastUpdate = [NSDate dateWithTimeIntervalSinceNow:-3];
            connectionSelfToConnectedUserNotInConv.conversation = selfToConnectedNotInConvConversation;
        }];
        
        XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
        
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
        WaitForEverythingToBeDone();
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
        WaitForEverythingToBeDone();
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
        WaitForEverythingToBeDone();
        
        XCTAssertFalse([conversation hasLocalModificationsForKey:ZMConversationUnsyncedActiveParticipantsKey]);
        [observer tearDown];
    }
}


- (void)testThatWhenLeavingAConversationWeSetAndSynchronizeTheLastReadServerTimestamp
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    
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

    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request) {
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
    WaitForEverythingToBeDone();
    
    // then
    XCTAssertNotNil(conversation.lastReadServerTimeStamp);
    XCTAssertTrue(didSendFirstArchivedMessage);
    XCTAssertFalse(didSendLastReadMessage); // we update the last read locally but don't sync it
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
    [self recreateUserSessionAndWipeCache:YES];
    
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    
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
            [self storeRemoteIDForObject:connectedUserNotInConv];
            
            MockConversation *selfToConnectedNotInConvConversation = [session insertOneOnOneConversationWithSelfUser:self.selfUser otherUser:connectedUserNotInConv];
            selfToConnectedNotInConvConversation.creator = self.selfUser;
            
            MockConnection *connectionSelfToConnectedUserNotInConv = [session insertConnectionWithSelfUser:self.selfUser toUser:connectedUserNotInConv];
            connectionSelfToConnectedUserNotInConv.status = @"accepted";
            connectionSelfToConnectedUserNotInConv.lastUpdate = [NSDate dateWithTimeIntervalSinceNow:-3];
            connectionSelfToConnectedUserNotInConv.conversation = selfToConnectedNotInConvConversation;
        }];
        
        XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
        
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
        WaitForEverythingToBeDone();
        
        XCTAssertFalse([conversation hasLocalModificationsForKey:ZMConversationUnsyncedActiveParticipantsKey]);
        [observer tearDown];
    }
}


- (void)testThatActiveParticipantsInOneOnOneConversationsAreAllParticipants
{
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    XCTAssertNotNil(conversation);
    
    [self.userSession saveOrRollbackChanges];
    
    XCTAssertEqual(conversation.activeParticipants.count, 2u);
    XCTAssertEqual(conversation.inactiveParticipants.count, 0u);
}

- (void)testThatActiveParticipantsInOneOnOneConversationWithABlockedUserAreAllParticipants
{
    // given
    
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    XCTAssertNotNil(conversation);
    
    [self.userSession saveOrRollbackChanges];
    
    XCTAssertEqual(conversation.activeParticipants.count, 2u);
    XCTAssertEqual(conversation.inactiveParticipants.count, 0u);
    
    // when
    ZMUser *user1 = [self userForMockUser:self.user1];
    XCTAssertFalse(user1.isBlocked);

    [self.userSession performChanges:^{
        [user1 block];
    }];
    
    XCTAssertTrue(user1.isBlocked);
    XCTAssertEqual(conversation.activeParticipants.count, 2u);
    XCTAssertEqual(conversation.inactiveParticipants.count, 0u);
}

- (NSArray *)movedIndexPairsForChangeSet:(ConversationListChangeInfo *)note
{
    NSMutableArray *indexes = [NSMutableArray array];
    [note enumerateMovedIndexes:^(NSUInteger from, NSUInteger to) {
        ZMMovedIndex *index = [ZMMovedIndex movedIndexFrom:from to:to];
        [indexes addObject:index];
    }];
    
    return indexes;
}

- (void)testThatNotificationsAreReceivedWhenConversationsAreFaulted
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForEverythingToBeDone();
    
    ZMConversation *conversation1 = [self conversationForMockConversation:self.selfToUser1Conversation];
    ZMConversation *conversation2 = [self conversationForMockConversation:self.selfToUser2Conversation];
    ZMConversation *conversation3 = [self conversationForMockConversation:self.groupConversation];
    ZMConversation *conversation4 = [self conversationForMockConversation:self.groupConversationWithOnlyConnected];
    
    // I am faulting conversation, will maintain the "message" relations as faulted
    ZMConversationList *conversationList = [ZMConversationList conversationsInUserSession:self.userSession];
    
    NSArray *expectedList1 = @[conversation4, conversation3, conversation2, conversation1];
    XCTAssertEqualObjects(conversationList, expectedList1);
    XCTAssertEqual(conversationList.count, 4u);
    
    ConversationListChangeObserver *observer = [[ConversationListChangeObserver alloc] initWithConversationList:conversationList];

    // when
    {
        [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> ZM_UNUSED *session) {
            ZMGenericMessage *message = [ZMGenericMessage messageWithText:@"some message" nonce:NSUUID.createUUID.transportString];
            [self.selfToUser1Conversation encryptAndInsertDataFromClient:self.user1.clients.anyObject toClient:self.selfUser.clients.anyObject data:message.data];
        }];
        WaitForEverythingToBeDone();
        
        // then
        NSArray *expectedList2 = @[conversation1, conversation4, conversation3, conversation2];
        NSIndexSet *updatedIndexes2 = [NSIndexSet indexSetWithIndex:0];
        NSArray *movedIndexes2 = @[[ZMMovedIndex movedIndexFrom:3 to:0]];
        
        XCTAssertEqualObjects(conversationList, expectedList2);
        
        XCTAssertEqual(observer.notifications.count, 1u);
        ConversationListChangeInfo *note1 = observer.notifications.lastObject;
        XCTAssertEqualObjects(note1.updatedIndexes, updatedIndexes2);
        XCTAssertEqualObjects([self movedIndexPairsForChangeSet:note1], movedIndexes2);
    }
    [observer tearDown];
}

- (void)testThatSelfUserSeesConversationWhenItIsAddedToConversationByOtherUser
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForEverythingToBeDone();

    __block MockConversation *groupConversation;
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        groupConversation = [session insertConversationWithCreator:self.user3 otherUsers:@[self.user1, self.user2] type:ZMTConversationTypeGroup];
        [self storeRemoteIDForObject:groupConversation];
        [groupConversation changeNameByUser:self.selfUser name:@"Group conversation 2"];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    ZMConversationList *conversationList = [ZMConversationList conversationsInUserSession:self.userSession];
    
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> ZM_UNUSED *session) {
        [groupConversation addUsersByUser:self.user1 addedUsers:@[self.selfUser]];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    //By this moment new conversation should be created and self user should be it's member
    ZMConversation *newConv = [self conversationForMockConversation:groupConversation];
    ZMUser *user = [self userForMockUser:self.selfUser];

    XCTAssertEqualObjects(conversationList.firstObject, newConv);
    XCTAssertTrue([[newConv allParticipants] containsObject:user]);
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
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    MockUserClient *fromClient = self.user2.clients.anyObject, *toClient = self.selfUser.clients.anyObject;
    
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        NOT_USED(session);
        
        for (NSUInteger i=0; i<20; ++i) {
            ZMGenericMessage *message = [ZMGenericMessage messageWithText:[NSString stringWithFormat:@"Message %ld", (unsigned long)i] nonce:NSUUID.createUUID.transportString];
            [self.groupConversation encryptAndInsertDataFromClient:fromClient toClient:toClient data:message.data];
            [NSThread sleepForTimeInterval:0.002]; // SE has milisecond precision
        }
        
        self.groupConversation.lastRead = ((MockEvent *)self.groupConversation.events.lastObject).identifier;
    }];
    WaitForEverythingToBeDone();
    
    
    ZMConversation *groupConversation = [self conversationForMockConversation:self.groupConversation];
    XCTAssertNotNil(groupConversation);
    
    ZMConversationMessageWindow *conversationWindow = [groupConversation conversationWindowWithSize:5];
    id token = [conversationWindow addConversationWindowObserver:self];
    
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
        ZMGenericMessage *message = [ZMGenericMessage messageWithText:extraMessageText nonce:NSUUID.createUUID.transportString];
        [self.groupConversation encryptAndInsertDataFromClient:fromClient toClient:toClient data:message.data];
    }];
    WaitForEverythingToBeDone();

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
    
    // finally
    [conversationWindow removeConversationWindowObserverToken:token];
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
        newMessage = [observer.window.conversation appendMessageWithText:expectedText];
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
        ZMGenericMessage *message = [ZMGenericMessage messageWithText:expectedText nonce:NSUUID.createUUID.transportString];
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
    
    // when
    ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
    [conversation appendMessageWithText:expectedTextLocal];
    
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *syncConversation = [ZMConversation conversationWithRemoteID:[NSUUID uuidWithTransportString:self.groupConversation.identifier] createIfNeeded:NO inContext:self.syncMOC];
        [syncConversation appendMessageWithText:expectedTextRemote];
        [self.syncMOC saveOrRollback];
    }];
    
    [self.uiMOC saveOrRollback];
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
    XCTAssertEqualObjects([[(id<ZMConversationMessage>)currentMessageSet[0] textMessageData] messageText], expectedTextLocal);
    XCTAssertEqualObjects([[(id<ZMConversationMessage>)currentMessageSet[1] textMessageData] messageText], expectedTextRemote);
}

@end

#pragma mark - Conversation list
@implementation ConversationTests (ConversationStatusAndOrder)

- (void)testThatTheConversationListOrderIsUpdatedAsWeReceiveMessages
{
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForAllGroupsToBeEmpty(0.5);

    // given
    __block MockConversation *mockExtraConversation;
    
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        mockExtraConversation = [session insertGroupConversationWithSelfUser:self.selfUser otherUsers:@[self.user1, self.user2]];
        [self storeRemoteIDForObject:mockExtraConversation];
        [mockExtraConversation changeNameByUser:self.selfUser name:@"Extra conversation"];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        NOT_USED(session);
        [self setDate:[NSDate dateWithTimeInterval:1000 sinceDate:self.groupConversation.lastEventTime] forAllEventsInMockConversation:mockExtraConversation];
    }];
    
    
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
        ZMGenericMessage *message = [ZMGenericMessage messageWithText:@"Bla bla bla" nonce:NSUUID.createUUID.transportString];
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
        [moves addObjectsFromArray:note.movedIndexPairs];
        
    }
    XCTAssertEqual(updatesCount, 1);
    XCTAssertEqual(moves.count, 1u);
    XCTAssertEqual([(ZMMovedIndex *)moves.firstObject from], 2u);
    XCTAssertEqual([(ZMMovedIndex *)moves.firstObject to], 0u);
    [observer tearDown];
}

- (void)testThatAConversationListListenerOnlyReceivesNotificationsForTheSpecificListItSignedUpFor
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
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
    [convListener1 tearDown];
    [convListener2 tearDown];

}


- (void)testThatLatestConversationIsAlwyaysOnTop
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForEverythingToBeDone();
    
    ZMConversationList *conversationList = [ZMConversationList conversationsInUserSession:self.userSession];
    ZMConversation *conversation1 = [self conversationForMockConversation:self.selfToUser1Conversation];
    (void) conversation1.messages; // Make sure we've faulted in the messages
    ZMConversation *conversation2 = [self conversationForMockConversation:self.selfToUser2Conversation];
    (void) conversation2.messages; // Make sure we've faulted in the messages
    ZMConversation *conversation3 = [self conversationForMockConversation:self.groupConversation];
    ZMConversation *conversation4 = [self conversationForMockConversation:self.groupConversationWithOnlyConnected];
    
    MockUserClient *toClient = self.selfUser.clients.anyObject;

    XCTAssertNotNil(conversation1);
    XCTAssertNotNil(conversation2);
    
    NSArray *expectedList1 = @[conversation4, conversation3, conversation2, conversation1];
    XCTAssertEqualObjects(conversationList, expectedList1);
    
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
        ZMGenericMessage *message = [ZMGenericMessage messageWithText:messageText1 nonce:nonce1.transportString];
        [self.selfToUser1Conversation encryptAndInsertDataFromClient:self.user1.clients.anyObject toClient:toClient data:message.data];
    }];
    WaitForEverythingToBeDone();
    
    // then
    NSArray *expectedList2 = @[conversation1, conversation4, conversation3, conversation2];
    NSIndexSet *expectedIndexes2 = [NSIndexSet indexSetWithIndex:0];
    
    XCTAssertEqualObjects(conversationList, expectedList2);
    XCTAssertEqual(conversationList[0], conversation1);
    
    XCTAssertGreaterThanOrEqual(observer.notifications.count, 1u);
    ConversationListChangeInfo *note1 = observer.notifications.lastObject;
    XCTAssertNotNil(note1);
    XCTAssertEqualObjects(note1.updatedIndexes, expectedIndexes2);
    
    ZMMessage *receivedMessage1 = conversation1.messages.lastObject;
    XCTAssertEqualObjects(receivedMessage1.textMessageData.messageText, messageText1);
    
    // send second message
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> ZM_UNUSED *session) {
        ZMGenericMessage *message = [ZMGenericMessage messageWithText:messageText2 nonce:nonce2.transportString];
        [self.selfToUser2Conversation encryptAndInsertDataFromClient:self.user1.clients.anyObject toClient:toClient data:message.data];
    }];
    WaitForEverythingToBeDone();
    
    // then
    NSArray *expectedList3 = @[conversation2, conversation1, conversation4, conversation3];
    NSIndexSet *expectedIndexes3 = [NSIndexSet indexSetWithIndex:0];
    
    XCTAssertEqualObjects(conversationList, expectedList3);
    XCTAssertEqual(conversationList[0], conversation2);
    
    XCTAssertGreaterThanOrEqual(observer.notifications.count, 2u);
    ConversationListChangeInfo *note2 = observer.notifications.lastObject;
    XCTAssertNotNil(note2);
    XCTAssertEqualObjects(note2.updatedIndexes, expectedIndexes3);
    
    ZMMessage *receivedMessage2 = conversation2.messages.lastObject;
    XCTAssertEqualObjects(receivedMessage2.textMessageData.messageText, messageText2);
    
    // send first message again
    
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> ZM_UNUSED *session) {
        ZMGenericMessage *message = [ZMGenericMessage messageWithText:messageText3 nonce:nonce3.transportString];
        [self.selfToUser1Conversation encryptAndInsertDataFromClient:self.user1.clients.anyObject toClient:toClient data:message.data];
    }];
    WaitForEverythingToBeDone();
    
    // then
    NSArray *expectedList4 = @[conversation1, conversation2, conversation4, conversation3];
    NSIndexSet *expectedIndexes4 = [NSIndexSet indexSetWithIndex:0];
    
    XCTAssertEqualObjects(conversationList, expectedList4);
    XCTAssertEqual(conversationList[0], conversation1);
    XCTAssertGreaterThanOrEqual(observer.notifications.count, 3u);
    
    ConversationListChangeInfo *note3 = observer.notifications.lastObject;
    XCTAssertNotNil(note3);
    XCTAssertEqualObjects(note3.updatedIndexes, expectedIndexes4);
    
    ZMMessage *receivedMessage3 = conversation1.messages.lastObject;
    XCTAssertEqualObjects(receivedMessage3.textMessageData.messageText, messageText3);
    [observer tearDown];
}

- (void)testThatReceivingAPingInAConversationThatIsNotAtTheTopBringsItToTheTop
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    
    ZMConversationList *conversationList = [ZMConversationList conversationsInUserSession:self.userSession];
    ConversationListChangeObserver *conversationListChangeObserver = [[ConversationListChangeObserver alloc] initWithConversationList:conversationList];
    
    ZMConversation *oneToOneConversation = [self conversationForMockConversation:self.selfToUser1Conversation];
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
    [note enumerateMovedIndexes:^(NSUInteger from, NSUInteger to) {
        [moves addObject:@[@(from), @(to)]];
    }];
    
    NSArray *expectedArray = @[@[@(oneToOneIndex), @0]];
    
    XCTAssertEqualObjects(moves, expectedArray);
    [conversationListChangeObserver tearDown];

}

- (void)testThatConversationGoesOnTopAfterARemoteUserAcceptsOurConnectionRequest
{
    //given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);

    ZMConversation *oneToOneConversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    MockUser *mockUser = [self createSentConnectionToUserWithName:@"Hans" uuid:NSUUID.createUUID];

    ZMConversationList *conversationList = [ZMConversationList conversationsInUserSession:self.userSession];
    ZMConversation *sentConversation = conversationList.firstObject;

    [self.mockTransportSession performRemoteChanges:^(__unused MockTransportSession<MockTransportSessionObjectCreation> *session) {
        ZMGenericMessage *message = [ZMGenericMessage messageWithText:@"some message" nonce:NSUUID.createUUID.transportString];
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
        [moves addObjectsFromArray:note.movedIndexPairs];
        XCTAssertTrue([note.updatedIndexes containsIndex:0]);
        //should be no deletions or insertions
        XCTAssertEqual(note.deletedIndexes.count, 0u);
        XCTAssertEqual(note.insertedIndexes.count, 0u);
    }
    XCTAssertEqual(updatesCount, 1);
    XCTAssertEqual(moves.count, 1u);
    XCTAssertEqual([(ZMMovedIndex *)moves.firstObject from], from);
    XCTAssertEqual([(ZMMovedIndex *)moves.firstObject to], 0u);

    
    XCTAssertEqualObjects(sentConversation, conversationList.firstObject);
    XCTAssertEqualObjects(oneToOneConversation, conversationList[1]);
    [conversationListChangeObserver tearDown];
}

- (void)testThatConversationGoesOnTopAfterWeAcceptIncommingConnectionRequest
{
    //given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);

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
    WaitForEverythingToBeDoneWithTimeout(0.5f);

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
        XCTAssertEqual(note.movedIndexPairs.count, 0u);
    }
    XCTAssertEqual(deletionsCount, 1);
    
    NSInteger insertionsCount = 0;
    for (ConversationListChangeInfo *note in activeObserver.notifications) {
        insertionsCount += note.insertedIndexes.count;
        //should be no deletions in active list
        XCTAssertEqual(note.deletedIndexes.count, 0u);
    }
    XCTAssertEqual(insertionsCount, 1);
    [activeObserver tearDown];
    [pendingObserver tearDown];
}

@end


#pragma mark - Archiving and silencing
@implementation ConversationTests (ArchivingAndSilencing)

- (void)testThatArchivingAConversationIsSynchronizedToTheBackend
{
    {
        // given
        [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
            // set last read
            NOT_USED(session);
            self.groupConversation.otrArchived = NO;
            self.groupConversation.otrArchivedRef = [[self.groupConversation.lastEventTime dateByAddingTimeInterval:-100] transportString];
        }];
        
        XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
        WaitForEverythingToBeDone();
        [self.mockTransportSession resetReceivedRequests];
        
        ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
        XCTAssertNotNil(conversation.lastServerTimeStamp);
        XCTAssertFalse(conversation.isArchived);
        XCTAssertTrue([conversation.lastServerTimeStamp compare:conversation.archivedChangedTimestamp] == NSOrderedDescending);
        
        // when
        [self.userSession performChanges:^{
            conversation.isArchived = YES;
        }];
        WaitForEverythingToBeDone();
        
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
    [self recreateUserSessionAndWipeCache:YES];
    
    {
        // Wait for sync to be done
        XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
        WaitForEverythingToBeDone();
        
        // then
        ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
        XCTAssertTrue(conversation.isArchived);
    }
    
}

- (void)testThatUnarchivingAConversationIsSynchronizedToTheBackend
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForEverythingToBeDone();
    
    ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
    [self.userSession performChanges:^{
        conversation.isArchived = YES;
    }];
    
    WaitForEverythingToBeDone();
    [self.mockTransportSession resetReceivedRequests];
    
    // when
    [self.userSession performChanges:^{
        conversation.isArchived = NO;
    }];
    WaitForEverythingToBeDone();
    
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
        XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
        WaitForEverythingToBeDone();
        [self.mockTransportSession resetReceivedRequests];
        
        ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
        
        // when
        [self.userSession performChanges:^{
            conversation.isSilenced = YES;
        }];
        WaitForEverythingToBeDone();
        
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
    [self recreateUserSessionAndWipeCache:YES];
    
    {
        // Wait for sync to be done
        XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
        WaitForEverythingToBeDone();
        
        // then
        ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
        XCTAssertTrue(conversation.isSilenced);
    }

}

- (void)testThatUnsilencingAConversationIsSynchronizedToTheBackend
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForEverythingToBeDone();
    
    ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
    [self.userSession performChanges:^{
        conversation.isSilenced = YES;
    }];
    
    WaitForEverythingToBeDone();
    [self.mockTransportSession resetReceivedRequests];
    
    // when
    [self.userSession performChanges:^{
        conversation.isSilenced = NO;
    }];
    WaitForEverythingToBeDone();
    
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
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForEverythingToBeDone();
    
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
    WaitForEverythingToBeDone();
    
    // then the conversation should not be in the active list anymore
    XCTAssertTrue(user1.isBlocked);
    XCTAssertEqual(conversation.connection.status, ZMConnectionStatusBlocked);

    XCTAssertEqual(active.count, 3u);
    XCTAssertFalse([active containsObject:conversation]);
    [observer tearDown];
}


- (void)checkThatItUnarchives:(BOOL)shouldUnarchive silenced:(BOOL)isSilenced mockConversation:(MockConversation *)mockConversation withBlock:(void (^)(MockTransportSession<MockTransportSessionObjectCreation> *session))block
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForEverythingToBeDone();
    
    ZMConversation *conversation = [self conversationForMockConversation:mockConversation];
    [self.userSession performChanges:^{
        conversation.isArchived = YES;
        if (isSilenced) {
            conversation.isSilenced = YES;
        }
    }];
    WaitForEverythingToBeDone();
    XCTAssertTrue(conversation.isArchived);
    if (isSilenced) {
        XCTAssertTrue(conversation.isSilenced);
    }
    
    // when
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        block(session);
    }];
    WaitForEverythingToBeDone();
    
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
        ZMGenericMessage *message = [ZMGenericMessage messageWithText:@"Some text" nonce:NSUUID.createUUID.transportString];
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
        ZMGenericMessage *message = [ZMGenericMessage messageWithText:@"Some text" nonce:NSUUID.createUUID.transportString];
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

- (void)testThatRemovingUsersFromAnArchivedConversation_Unarchives_ThisConversation
{
    // expect
    BOOL shouldUnarchive = YES;
    
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

- (void)testThatCallingAnArchived_AndSilenced_Conversation_Unarchives_ThisConversation
{
    // expect
    BOOL shouldUnarchive = YES;
    
    // when
    [self checkThatItUnarchives:shouldUnarchive silenced:YES mockConversation:self.selfToUser1Conversation withBlock:^(MockTransportSession *session ZM_UNUSED) {
        [self.selfToUser1Conversation addUserToCall:self.user1];
    }];
    
    ZMConversation *syncConv = (id)[self.userSession.syncManagedObjectContext objectWithID:[self conversationForMockConversation:self.selfToUser1Conversation].objectID];
    [syncConv.voiceChannel tearDown];
}

- (void)testThatCallingAnArchivedConversation_Unarchives_ThisConversation
{
    // expect
    BOOL shouldUnarchive = YES;
    
    // when
    [self checkThatItUnarchives:shouldUnarchive silenced:NO mockConversation:self.selfToUser1Conversation withBlock:^(MockTransportSession *session ZM_UNUSED) {
        [self.selfToUser1Conversation addUserToCall:self.user1];
    }];
    ZMConversation *syncConv = (id)[self.userSession.syncManagedObjectContext objectWithID:[self conversationForMockConversation:self.selfToUser1Conversation].objectID];
    [syncConv.voiceChannel tearDown];
}

- (void)testThatAcceptingArchivedOutgoingRequest_Unarchives_ThisConversation
{
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);

    MockUser *mockUser = [self createSentConnectionToUserWithName:@"Hans" uuid:NSUUID.createUUID];
    ZMConversationList *conversations = [ZMConversationList conversationsInUserSession:self.userSession];
    ZMConversation *conversation = conversations.firstObject;
    // expect
    
    BOOL shouldUnarchive = YES;
    
    // when
    [self.userSession performChanges:^{
        conversation.isArchived = YES;
    }];
    WaitForEverythingToBeDone();
    XCTAssertTrue(conversation.isArchived);
    
    // when
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [session remotelyAcceptConnectionToUser:mockUser];
    }];
    WaitForEverythingToBeDone();
    
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
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForEverythingToBeDone();
    
    // given
    MockUserClient *fromClient = self.user1.clients.anyObject, *toClient = self.selfUser.clients.anyObject;
    
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        NOT_USED(session);
        ZMGenericMessage *message = [ZMGenericMessage messageWithText:@"Will insert this to have a message to read" nonce:NSUUID.createUUID.transportString];
        [self.selfToUser1Conversation encryptAndInsertDataFromClient:fromClient toClient:toClient data:message.data];
        MockEvent *lastEvent = self.selfToUser1Conversation.events.lastObject;
        self.selfToUser1Conversation.lastRead = lastEvent.identifier;
    }];
    
    WaitForEverythingToBeDone();
    
    [self recreateUserSessionAndWipeCache:YES];
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForEverythingToBeDone();
    
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    XCTAssertEqual(conversation.estimatedUnreadCount, 0u);
    
    // when
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        NOT_USED(session);
        ZMGenericMessage *message = [ZMGenericMessage messageWithText:@"This should increase the unread count" nonce:NSUUID.createUUID.transportString];
        [self.selfToUser1Conversation encryptAndInsertDataFromClient:fromClient toClient:toClient data:message.data];
    }];
    WaitForEverythingToBeDone();
    
    // then
    XCTAssertEqual(conversation.estimatedUnreadCount, 1u);
}


- (void)testThatLastReadIsAutomaticallyIncreasedInCaseOfCallEvents
{
    // login
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    // given
    [self.mockTransportSession performRemoteChanges:^(__unused MockTransportSession<MockTransportSessionObjectCreation> *session) {
        ZMGenericMessage *message = [ZMGenericMessage messageWithText:@"Will insert this to have a message to read" nonce:NSUUID.createUUID.transportString];
        [self.selfToUser1Conversation encryptAndInsertDataFromClient:self.user1.clients.anyObject toClient:self.selfUser.clients.anyObject data:message.data];
        
        MockEvent *lastEvent = self.selfToUser1Conversation.events.lastObject;
        self.selfToUser1Conversation.lastRead = lastEvent.identifier;
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // login
    [self recreateUserSessionAndWipeCache:YES];
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    XCTAssertEqual(conversation.estimatedUnreadCount, 0u);
    
    // when
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        NOT_USED(session);
        [self.selfToUser1Conversation addUserToCall:self.user1];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(conversation.estimatedUnreadCount, 0u);

    // when
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        NOT_USED(session);
        [self.selfToUser1Conversation callEndedEventFromUser:self.user1 selfUser:self.selfUser];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertEqual(conversation.estimatedUnreadCount, 1u);

    ZMConversation *syncConv = (id)[self.userSession.syncManagedObjectContext objectWithID:[self conversationForMockConversation:self.selfToUser1Conversation].objectID];
    [syncConv.voiceChannel tearDown];
}

- (void)testThatItDoesNotSendALastReadEventWhenInsertingAMessage
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.mockTransportSession resetReceivedRequests];
    ZMConversation *conv =  [self conversationForMockConversation:self.selfToUser1Conversation];
    ZMConversation *selfConv = [ZMConversation selfConversationInContext:self.uiMOC];
    __block ZMMessage *textMsg;
    __block ZMMessage *imageMsg;

    // when
    [self.userSession performChanges:^{
        textMsg = [conv appendMessageWithText:@"bla bla"];
        imageMsg = [conv appendMessageWithImageData:self.verySmallJPEGData];
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

- (void)setupTestThatItPaginatesConversationIDsRequests
{
    self.previousZMConversationTranscoderListPageSize = ZMConversationTranscoderListPageSize;
    ZMConversationTranscoderListPageSize = 3;
}

- (void)testThatItPaginatesConversationIDsRequests
{
    // given
    XCTAssertEqual(ZMConversationTranscoderListPageSize, 3u);
    
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
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForEverythingToBeDone();

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
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForEverythingToBeDone();
    
    ZMConversation *conversation = [self conversationForMockConversation:mockConversation];
    MockUser *otherUser = (id)[mockConversation.activeUsers firstObjectNotInSet:[NSSet setWithObject:self.selfUser]];
    
    // given
    MockUserClient *fromClient = otherUser.clients.anyObject, *toClient = self.selfUser.clients.anyObject;
    
    [self.mockTransportSession performRemoteChanges:^(ZM_UNUSED id session) {
        // If the client is not registered yet we need to account for the added System Message
        for (NSUInteger i = 0; i < messagesCount - conversation.messages.count; i++) {
            ZMGenericMessage *message = [ZMGenericMessage messageWithText:[NSString stringWithFormat:@"foo %lu", (unsigned long)i] nonce:NSUUID.createUUID.transportString];
            [mockConversation encryptAndInsertDataFromClient:fromClient toClient:toClient data:message.data];
        }
    }];
    WaitForEverythingToBeDone();
    
    conversation = [self conversationForMockConversation:mockConversation];
    XCTAssertEqual(conversation.messages.count, messagesCount);
    
    ZMConversationMessageWindow *window = [conversation conversationWindowWithSize:messagesCount];
    XCTAssertEqual(window.messages.count, window.size);
}

- (void)testThatItNotifiesTheObserverWhenTheHistoryIsClearedAndSyncsWithTheBackend
{
    //given
    const NSUInteger messagesCount = 5;
    self.registeredOnThisDevice = YES;
    [self loginAndFillConversationWithMessages:self.groupConversation messagesCount:messagesCount];
    WaitForEverythingToBeDone();

    ZMConversationListDirectory *conversationDirectory = [self.uiMOC conversationListDirectory];
    WaitForEverythingToBeDone();

    ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
    {
        ZMConversationMessageWindow *window = [conversation conversationWindowWithSize:messagesCount];
        MessageWindowChangeToken *token = (id)[window addConversationWindowObserver:self];
        [self.mockTransportSession resetReceivedRequests];
        [self.receivedConversationWindowChangeNotifications removeAllObjects];
        
        // when
    
        [self.userSession performChanges:^{
            [conversation clearMessageHistory];
        }];
        WaitForEverythingToBeDone();
        
        // then
        XCTAssertEqual(window.messages.count, 0u);
        XCTAssertFalse([conversationDirectory.conversationsIncludingArchived containsObject:conversation]);
        
        XCTAssertEqual(self.receivedConversationWindowChangeNotifications.count, 1u);
        MessageWindowChangeInfo *info = self.receivedConversationWindowChangeNotifications.firstObject;
        XCTAssertEqualObjects([info deletedIndexes], [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, messagesCount)]);
        
        ZMTransportRequest *firstRequest = self.mockTransportSession.receivedRequests.firstObject;
        NSString *expectedPath = [NSString stringWithFormat:@"/conversations/%@/self", conversation.remoteIdentifier.transportString];
        XCTAssertEqualObjects(firstRequest.payload[@"cleared"], conversation.lastEventID.transportString);
        XCTAssertEqualObjects(firstRequest.payload[@"otr_archived_ref"], conversation.lastServerTimeStamp.transportString);
        XCTAssertEqualObjects(firstRequest.payload[@"otr_archived"], @1);

        XCTAssertNil(firstRequest.payload[@"last_read"]);
        XCTAssertEqualObjects(firstRequest.path, expectedPath);
        XCTAssertEqual(firstRequest.method, ZMMethodPUT);
        
        ZMUser *selfUser = [self userForMockUser:self.selfUser];
        ZMTransportRequest *lastRequest = self.mockTransportSession.receivedRequests.lastObject;
        NSString *selfConversationPath = [NSString stringWithFormat:@"/conversations/%@/otr/messages", selfUser.remoteIdentifier.transportString];
        XCTAssertNotNil(lastRequest.binaryData);
        XCTAssertEqualObjects(lastRequest.path, selfConversationPath);
        XCTAssertEqual(lastRequest.method, ZMMethodPOST);
        
        [window removeConversationWindowObserverToken:(id)token];
    }
    
    [self recreateUserSessionAndWipeCache:YES];
    WaitForEverythingToBeDone();

    {
        // Wait for sync to be done
        XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
        WaitForEverythingToBeDone();
    

        // then
        conversation = [self conversationForMockConversation:self.groupConversation];
        [conversation startFetchingMessages];
        WaitForEverythingToBeDone();

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
    self.registeredOnThisDevice = YES;
    [self loginAndFillConversationWithMessages:self.groupConversation messagesCount:messagesCount];
    ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
    
    ZMConversationMessageWindow *window = [conversation conversationWindowWithSize:messagesCount];
    MessageWindowChangeToken *token = (id)[window addConversationWindowObserver:self];
    
    ZMConversationListDirectory *conversationDirectory = [self.uiMOC conversationListDirectory];
    NSManagedObjectID *conversationID = conversation.objectID;
    
    // when removing messages remotely
    {
        [self.mockTransportSession performRemoteChanges:^(ZM_UNUSED id session) {
            [self.groupConversation remotelyClearHistoryFromUser:self.selfUser includeOTR:NO];
        }];
        WaitForEverythingToBeDone();
        
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
    WaitForEverythingToBeDone();

    // then
    XCTAssertEqual(conversation.messages.count, 1u);
    XCTAssertEqual(window.messages.count, 1u); // new message
    
    [window removeConversationWindowObserverToken:(id)token];
    
    [self recreateUserSessionAndWipeCache:YES];
    WaitForEverythingToBeDone();
    
    {
        // Wait for sync to be done
        XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
        WaitForEverythingToBeDone();
        
        // then
        conversation = [self conversationForMockConversation:self.groupConversation];
        [conversation startFetchingMessages];
        WaitForEverythingToBeDone();
        
        window = [conversation conversationWindowWithSize:messagesCount];
        XCTAssertTrue([conversationDirectory.conversationsIncludingArchived.objectIDs containsObject:conversationID]);
    }
}

- (void)testThatDeletedConversationsStayDeletedAfterResyncing
{
    //given
    const NSUInteger messagesCount = 5;
    self.registeredOnThisDevice = YES;
    [self loginAndFillConversationWithMessages:self.groupConversation messagesCount:messagesCount];
    
    ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
    XCTAssertEqual(conversation.messages.count, 5lu);
    
    ZMConversationMessageWindow *window = [conversation conversationWindowWithSize:messagesCount];
    MessageWindowChangeToken *token = (id)[window addConversationWindowObserver:self];
    
    ZMConversationListDirectory *conversationDirectory = [self.uiMOC conversationListDirectory];
    NSManagedObjectID *conversationID = conversation.objectID;
    
    // when deleting the conversation remotely
    {
        [self.mockTransportSession performRemoteChanges:^(ZM_UNUSED id session) {
            [self.groupConversation remotelyDeleteFromUser:self.selfUser includeOTR:NO];
        }];
        WaitForEverythingToBeDone();
        
        // then
        XCTAssertEqual(window.messages.count, 0u);
        XCTAssertFalse([conversationDirectory.conversationsIncludingArchived containsObject:conversation]);
        
        XCTAssertEqual(self.receivedConversationWindowChangeNotifications.count, 1u);
        MessageWindowChangeInfo *info = self.receivedConversationWindowChangeNotifications.firstObject;
        XCTAssertEqualObjects([info deletedIndexes], [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 5)]);
        [self.receivedConversationWindowChangeNotifications removeAllObjects];
    }
    
    [window removeConversationWindowObserverToken:(id)token];
    [self recreateUserSessionAndWipeCache:YES];
    WaitForEverythingToBeDone();
    
    {
        // Wait for sync to be done
        XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
        WaitForEverythingToBeDone();
        
        // then
        conversation = [self conversationForMockConversation:self.groupConversation];
        [conversation startFetchingMessages];
        WaitForEverythingToBeDone();
        
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
    
    ZMConversationListDirectory *conversationDirectory = [self.uiMOC conversationListDirectory];
    NSManagedObjectID *conversationID = conversation.objectID;
    
    [self.mockTransportSession performRemoteChanges:^(ZM_UNUSED id session) {
        [self.groupConversation remotelyArchiveFromUser:self.selfUser includeOTR:NO];
    }];
    WaitForEverythingToBeDone();
    
    [self.mockTransportSession performRemoteChanges:^(ZM_UNUSED id session) {
        [self.groupConversation remotelyClearHistoryFromUser:self.selfUser includeOTR:NO];
    }];
    WaitForEverythingToBeDone();
    
    // then
    XCTAssertFalse([conversationDirectory.conversationsIncludingArchived.objectIDs containsObject:conversationID]);
}

- (void)testFirstArchivingThenClearingRemotelyShouldDeleteConversation_UseOTRFlags
{
    //given
    const NSUInteger messagesCount = 5;
    [self loginAndFillConversationWithMessages:self.groupConversation messagesCount:messagesCount];
    ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
    
    ZMConversationListDirectory *conversationDirectory = [self.uiMOC conversationListDirectory];
    NSManagedObjectID *conversationID = conversation.objectID;
    
    [self.mockTransportSession performRemoteChanges:^(ZM_UNUSED id session) {
        [self.groupConversation remotelyArchiveFromUser:self.selfUser includeOTR:YES];
    }];
    WaitForEverythingToBeDone();
    
    [self.mockTransportSession performRemoteChanges:^(ZM_UNUSED id session) {
        [self.groupConversation remotelyClearHistoryFromUser:self.selfUser includeOTR:YES];
    }];
    WaitForEverythingToBeDone();
    
    // then
    XCTAssertFalse([conversationDirectory.conversationsIncludingArchived.objectIDs containsObject:conversationID]);
}

- (void)testFirstClearingThenArchivingRemotelyShouldDeleteConversation
{
    //given
    const NSUInteger messagesCount = 5;
    [self loginAndFillConversationWithMessages:self.groupConversation messagesCount:messagesCount];
    ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
    
    ZMConversationListDirectory *conversationDirectory = [self.uiMOC conversationListDirectory];
    NSManagedObjectID *conversationID = conversation.objectID;
    
    [self.mockTransportSession performRemoteChanges:^(ZM_UNUSED id session) {
        [self.groupConversation remotelyClearHistoryFromUser:self.selfUser includeOTR:NO];
    }];
    WaitForEverythingToBeDone();
    
    [self.mockTransportSession performRemoteChanges:^(ZM_UNUSED id session) {
        [self.groupConversation remotelyArchiveFromUser:self.selfUser includeOTR:NO];
        
    }];
    WaitForEverythingToBeDone();
    
    // then
    XCTAssertFalse([conversationDirectory.conversationsIncludingArchived.objectIDs containsObject:conversationID]);
}

- (void)testThatRemotelyArchivedConversationIsIncludedInTheCorrectConversationLists
{
    // given
    const NSUInteger messagesCount = 5;
    [self loginAndFillConversationWithMessages:self.groupConversation messagesCount:messagesCount];
    ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
    
    ZMConversationListDirectory *conversationDirectory = [self.uiMOC conversationListDirectory];
    
    // when archiving the conversation remotely
    [self.mockTransportSession performRemoteChanges:^(ZM_UNUSED id session) {
        [self.groupConversation remotelyArchiveFromUser:self.selfUser includeOTR:NO];
    }];
    WaitForEverythingToBeDone();
    
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
    ZMConversationListDirectory *conversationDirectory = [self.uiMOC conversationListDirectory];
    NSManagedObjectID *conversationID = conversation.objectID;
    
    // when deleting the conversation remotely, whiping the cache and resyncing
    {
        [self.mockTransportSession performRemoteChanges:^(ZM_UNUSED id session) {
            [self.groupConversation remotelyArchiveFromUser:self.selfUser includeOTR:NO];
        }];
        WaitForEverythingToBeDone();
        
        [self recreateUserSessionAndWipeCache:YES];
        WaitForEverythingToBeDone();
        XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
        WaitForAllGroupsToBeEmpty(0.5);
    }
    
    // then
    conversation = [self conversationForMockConversation:self.groupConversation];
    [conversation startFetchingMessages];
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
    WaitForEverythingToBeDone();
    
    XCTAssertEqual(conversation.messages.count, 0u);
    
    // when
    
    [self.mockTransportSession performRemoteChanges:^(ZM_UNUSED id session) {
        [self spinMainQueueWithTimeout:1]; // if the action happens within the same second the user clears the history, the event is not added
        ZMGenericMessage *message = [ZMGenericMessage messageWithText:@"foo" nonce:NSUUID.createUUID.transportString];
        [self.groupConversation encryptAndInsertDataFromClient:self.user2.clients.anyObject toClient:self.selfUser.clients.anyObject data:message.data];
    }];
    WaitForEverythingToBeDone();
    
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
    WaitForEverythingToBeDone();
    XCTAssertEqual(conversation.messages.count, 0u);
    // when
    
    [self.mockTransportSession performRemoteChanges:^(ZM_UNUSED id session) {
        [self spinMainQueueWithTimeout:1]; // if the action happens within the same second the user clears the history, the event is not added
        [self.groupConversation removeUsersByUser:self.user2 removedUser:self.user3];
    }];
    WaitForEverythingToBeDone();

    // then
    conversation = [self conversationForMockConversation:self.groupConversation];
    ZMConversationMessageWindow *window = [conversation conversationWindowWithSize:messagesCount];
    XCTAssertEqual(window.messages.count, 1u);
    XCTAssertEqual(conversation.messages.count, 1u);
    XCTAssertFalse(conversation.isArchived);
}

- (void)testThatReceivingRemoteKnockMessageRevealsClearedConversation
{
    //given
    const NSUInteger messagesCount = 5;
    [self loginAndFillConversationWithMessages:self.groupConversation messagesCount:messagesCount];
    ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
    
    [self.userSession performChanges:^{
        [conversation clearMessageHistory];
    }];
    WaitForEverythingToBeDone();
    XCTAssertEqual(conversation.messages.count, 0u);
    // when
    
    [self.mockTransportSession performRemoteChanges:^(ZM_UNUSED id session) {
        [self spinMainQueueWithTimeout:1]; // if the action happens within the same second the user clears the history, the event is not added
        [self.groupConversation insertKnockFromUser:self.user2 nonce:[NSUUID createUUID]];
    }];
    WaitForEverythingToBeDone();
    
    // then
    conversation = [self conversationForMockConversation:self.groupConversation];
    ZMConversationMessageWindow *window = [conversation conversationWindowWithSize:messagesCount];
    XCTAssertEqual(window.messages.count, 1u);
    XCTAssertEqual(conversation.messages.count, 1u);
    XCTAssertFalse(conversation.isArchived);
}

- (void)testThatReceivingRemoteImageMessageRevealsClearedConversation
{
    //given
    const NSUInteger messagesCount = 5;
    [self loginAndFillConversationWithMessages:self.groupConversation messagesCount:messagesCount];
    ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
    
    [self.userSession performChanges:^{
        [conversation clearMessageHistory];
    }];
    WaitForEverythingToBeDone();
    XCTAssertEqual(conversation.messages.count, 0u);

    // when
    
    [self.mockTransportSession performRemoteChanges:^(ZM_UNUSED id session) {
        [self spinMainQueueWithTimeout:1]; // if the action happens within the same second the user clears the history, the event is not added
        [self.groupConversation insertPreviewImageEventFromUser:self.user2 correlationID:[NSUUID createUUID] none:[NSUUID createUUID]];
    }];
    WaitForEverythingToBeDone();
    
    // then
    conversation = [self conversationForMockConversation:self.groupConversation];
    ZMConversationMessageWindow *window = [conversation conversationWindowWithSize:messagesCount];
    XCTAssertEqual(window.messages.count, 1u);
    XCTAssertEqual(conversation.messages.count, 1u);
    XCTAssertFalse(conversation.isArchived);
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
    WaitForEverythingToBeDone();
    XCTAssertEqual(conversation.messages.count, 0u);

    // when
    
    [self.userSession performChanges:^{
        [conversation revealClearedConversation];
    }];
    WaitForEverythingToBeDone();
    
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
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    [self.userSession performChanges:^{
        ZMMessage *message = [conversation appendMessageWithText:@"lalala"];
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
    self.registeredOnThisDevice = YES;
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    
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
        message1 = [conversation appendMessageWithText:@"hehehe"];
        [NSThread sleepForTimeInterval:0.2]; // this is needed so the timeStamps are at least a millisecond appart
        message2 = [conversation appendMessageWithText:@"I will not go away"];
        [self spinMainQueueWithTimeout:0.1]; // this is needed so the timeStamps are at least a millisecond appart
        message3 = [conversation appendMessageWithText:@"I will stay for sure"];
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
    self.registeredOnThisDevice = YES;
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    
    __block NSUInteger callCount = 0;
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request) {
        NSString *path = [NSString stringWithFormat:@"/conversations/%@/members/%@", self.groupConversation.identifier, self.selfUser.identifier];
        if([request.path isEqualToString:path]) {
            XCTAssertEqual(callCount, 0u);
            callCount++;
            return [ZMTransportResponse responseWithPayload:nil HTTPstatus:404 transportSessionError:nil];
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
    self.registeredOnThisDevice = YES;
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);

    __block MockUser *connectedUserNotInConv;
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        connectedUserNotInConv = [session insertUserWithName:@"Connected user which originally is not in conversation"];
        connectedUserNotInConv.email = @"connectedUserNotInConv@example.com";
        connectedUserNotInConv.phone = @"23498579";
        [self storeRemoteIDForObject:connectedUserNotInConv];
        
        MockConversation *selfToConnectedNotInConvConversation = [session insertOneOnOneConversationWithSelfUser:self.selfUser otherUser:connectedUserNotInConv];
        selfToConnectedNotInConvConversation.creator = self.selfUser;
        
        MockConnection *connectionSelfToConnectedUserNotInConv = [session insertConnectionWithSelfUser:self.selfUser toUser:connectedUserNotInConv];
        connectionSelfToConnectedUserNotInConv.status = @"accepted";
        connectionSelfToConnectedUserNotInConv.lastUpdate = [NSDate dateWithTimeIntervalSinceNow:-3];
        connectionSelfToConnectedUserNotInConv.conversation = selfToConnectedNotInConvConversation;
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    __block NSUInteger callCount = 0;
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request) {
        NSString *path = [NSString stringWithFormat:@"/conversations/%@/members", self.groupConversation.identifier];
        if([request.path isEqualToString:path] && request.method == ZMMethodPOST) {
            XCTAssertEqual(callCount, 0u);
            callCount++;
            return [ZMTransportResponse responseWithPayload:nil HTTPstatus:403 transportSessionError:nil];
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


