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



@import ZMCMockTransport;
@import ZMCDataModel;

#import "MessagingTest.h"
#import "NotificationObservers.h"
#import "MockLinkPreviewDetector.h"
#import <zmessaging/zmessaging-Swift.h>

@import ZMCMockTransport;
@import Cryptobox;

@class ZMUserSession;
@class ZMGenericMessage;
@class ZMGSMCallHandler;

#define WaitForEverythingToBeDoneWithTimeout(_timeout) \
    do { \
        if (! [self waitForEverythingToBeDoneWithTimeout:_timeout]) { \
            XCTFail(@"Timed out waiting for groups to empty."); \
    } \
} while (0)

#define WaitForEverythingToBeDone() WaitForEverythingToBeDoneWithTimeout(0.5)

extern NSString * const SelfUserEmail;
extern NSString * const SelfUserPassword;

@interface IntegrationTestBase : MessagingTest

@property (nonatomic, readonly) MockUser *selfUser;
@property (nonatomic, readonly) MockUser *user1; // connected, with profile picture
@property (nonatomic, readonly) MockUser *user2; // connected
@property (nonatomic, readonly) MockUser *user3; // not connected, with profile picture, in a common group conversation
@property (nonatomic, readonly) MockUser *user4; // not connected, with profile picture, no shared conversations
@property (nonatomic, readonly) MockUser *user5; // not connected, no shared conversation
@property (nonatomic, readonly) MockConversation *selfConversation;
@property (nonatomic, readonly) MockConversation *selfToUser1Conversation;
@property (nonatomic, readonly) MockConversation *selfToUser2Conversation;
@property (nonatomic, readonly) MockConversation *groupConversation;
@property (nonatomic, readonly) MockConnection *connectionSelfToUser1;
@property (nonatomic, readonly) MockConnection *connectionSelfToUser2;
@property (nonatomic, readonly) NSArray *connectedUsers;
@property (nonatomic, readonly) NSArray *nonConnectedUsers;
@property (nonatomic, readonly) NSArray *allUsers;
@property (nonatomic, readonly) MockFlowManager *mockFlowManager;
@property (nonatomic, readonly) MockLinkPreviewDetector *mockLinkPreviewDetector;

@property (nonatomic, readonly) ZMGSMCallHandler *gsmCallHandler;

@property (nonatomic) ConversationChangeObserver *conversationChangeObserver;
@property (nonatomic) UserChangeObserver *userChangeObserver;
@property (nonatomic) MessageChangeObserver *messageChangeObserver;

@property (nonatomic) BOOL registeredOnThisDevice;

@property (nonatomic) ZMUserSession *userSession;

- (BOOL)loginAndWaitForSyncToBeCompleteWithEmail:(NSString *)email password:(NSString *)password ZM_MUST_USE_RETURN;
- (BOOL)loginAndWaitForSyncToBeCompleteWithEmail:(NSString *)email password:(NSString *)password timeout:(NSTimeInterval)timeout ZM_MUST_USE_RETURN;
- (BOOL)logInWithEmail:(NSString *)email password:(NSString *)password ZM_MUST_USE_RETURN;
- (BOOL)logIn ZM_MUST_USE_RETURN;
- (BOOL)logInAndWaitForSyncToBeComplete ZM_MUST_USE_RETURN;
- (BOOL)logInAndWaitForSyncToBeCompleteIgnoringAuthenticationFailures:(BOOL)shouldIgnoreAuthenticationFailures ZM_MUST_USE_RETURN;

- (BOOL)logInAndWaitForSyncToBeCompleteWithTimeout:(NSTimeInterval)timeout ZM_MUST_USE_RETURN;
- (BOOL)loginAndWaitForSyncToBeCompleteWithPhone:(NSString *)phone ZM_MUST_USE_RETURN;
- (BOOL)loginAndWaitForSyncToBeCompleteWithPhone:(NSString *)phone ignoringAuthenticationFailure:(BOOL)ignoringAuthenticationFailures ZM_MUST_USE_RETURN;

- (void)recreateUserSessionAndWipeCache:(BOOL)wipeCache;

- (ZMConversation *)conversationForMockConversation:(MockConversation *)conversation;
- (void)setDate:(NSDate *)date forAllEventsInMockConversation:(MockConversation *)conversation;
- (ZMUser *)userForMockUser:(MockUser *)user;

- (void)storeRemoteIDForObject:(NSManagedObject *)mo;
- (NSUUID *)remoteIdentifierForMockObject:(NSManagedObject *)mo;

- (BOOL)waitForEverythingToBeDone ZM_MUST_USE_RETURN;
- (BOOL)waitForEverythingToBeDoneWithTimeout:(NSTimeInterval)timeout ZM_MUST_USE_RETURN;

- (void)searchAndConnectToUserWithName:(NSString *)searchUserName searchQuery:(NSString *)query;
- (MockUser *)createPendingConnectionFromUserWithName:(NSString *)name uuid:(NSUUID *)uuid;
- (MockUser *)createSentConnectionToUserWithName:(NSString *)name uuid:(NSUUID *)uuid;
- (MockUser *)createUserWithName:(NSString *)name uuid:(NSUUID *)uuid;

- (void)prefetchRemoteClientByInsertingMessageInConversation:(MockConversation *)conversation;

- (void)establishSessionBetweenSelfUserAndMockUser:(MockUser *)mockUser;

- (void)remotelyAppendSelfConversationWithZMClearedForMockConversation:(MockConversation *)mockConversation
                                                                atTime:(NSDate *)newClearedTimeStamp;

- (void)remotelyAppendSelfConversationWithZMLastReadForMockConversation:(MockConversation *)mockConversation
                                                                 atTime:(NSDate *)newClearedTimeStamp;

- (void)remotelyAppendSelfConversationWithZMMessageHideForMessageID:(NSString *)messageID
                                                     conversationID:(NSString *)conversationID;
- (void)simulateAppStopped;
- (void)simulateAppRestarted;

@end



@interface  MockFlowManager (AdditionalMethods)

- (BOOL)isReady;

@end
