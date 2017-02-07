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


@import CoreTelephony;
@import ZMCDataModel;
@import WireMessageStrategy;

#import "IntegrationTestBase.h"
#import "ZMHotfix.h"
#import "ZMUserSession+Internal.h"
#import "ZMTestNotifications.h"
#import "ZMSearchDirectory.h"
#import "ZMUserSession+Authentication.h"
#import "ZMUserSession+Registration.h"
#import "ZMCredentials.h"
#import <zmessaging/ZMAuthenticationStatus+Testing.h>
#import <zmessaging/zmessaging-Swift.h>
#import "ZMFlowSync.h"
#import "ZMGSMCallHandler.h"
#import "ZMOperationLoop+Private.h"
#import "ZMSyncStrategy.h"
#import "ZMCallStateTranscoder.h"
#import "MockLinkPreviewDetector.h"
#import "zmessaging_iOS_Tests-Swift.h"


NSString * const SelfUserEmail = @"myself@user.example.com";
NSString * const SelfUserPassword = @"fgf0934';$@#%";


@interface IntegrationTestBase ()

@property (nonatomic) NSMutableDictionary *mockObjectIDToRemoteID;
@property (nonatomic) MockUser *selfUser;
@property (nonatomic) MockUser *user1;
@property (nonatomic) MockUser *user2;
@property (nonatomic) MockUser *user3;
@property (nonatomic) MockUser *user4;
@property (nonatomic) MockUser *user5;
@property (nonatomic) MockConversation *selfConversation;
@property (nonatomic) MockConversation *selfToUser1Conversation;
@property (nonatomic) MockConversation *selfToUser2Conversation;
@property (nonatomic) MockConversation *groupConversation;
@property (nonatomic) MockConnection *connectionSelfToUser1;
@property (nonatomic) MockConnection *connectionSelfToUser2;
@property (nonatomic) NSArray *connectedUsers;
@property (nonatomic) NSArray *allUsers;
@property (nonatomic) NSArray *nonConnectedUsers;
@property (nonatomic) MockFlowManager *mockFlowManager;
@property (nonatomic) MockLinkPreviewDetector *mockLinkPreviewDetector;


@end


@interface MockFlowManager (Instance)
+ (instancetype)getInstance;
@end

@implementation MockFlowManager (Instance)

+ (instancetype)getInstance
{
    return ZMFlowSyncInternalFlowManagerOverride;
}

@end


@implementation IntegrationTestBase

- (void)setUp
{
    [super setUp];

    self.mockLinkPreviewDetector = [[MockLinkPreviewDetector alloc] initWithTestImageData:[self mediumJPEGData]];
    [LinkPreviewDetectorHelper setTest_debug_linkPreviewDetector:self.mockLinkPreviewDetector];
    
    self.mockObjectIDToRemoteID = [NSMutableDictionary dictionary];
    self.mockFlowManager = self.mockTransportSession.mockFlowManager;

    ZMFlowSyncInternalFlowManagerOverride = self.mockFlowManager;
    WireCallCenterV3Factory.wireCallCenterClass = WireCallCenterV3Mock.self;
    
    [self createObjects];
    
    [self recreateUserSessionAndWipeCache:YES];
    
    self.conversationChangeObserver = [[ConversationChangeObserver alloc] init];
    self.userChangeObserver = [[UserChangeObserver alloc] init];
    self.messageChangeObserver = [[MessageChangeObserver alloc] init];
    [self.application simulateApplicationDidBecomeActive];
    WaitForEverythingToBeDoneWithTimeout(0.5);
}

- (ZMGSMCallHandler *)gsmCallHandler
{
    return self.userSession.operationLoop.syncStrategy.callStateTranscoder.gsmCallHandler;
}

- (void)tearDown
{
    WaitForAllGroupsToBeEmpty(0.5);

    self.mockLinkPreviewDetector = nil;
    [BackgroundActivityFactory tearDownInstance];
    [LinkPreviewDetectorHelper tearDown];
    
    self.conversationChangeObserver = nil;
    self.userChangeObserver = nil;
    self.messageChangeObserver = nil;

    WaitForAllGroupsToBeEmpty(0.5);
    
    ZMFlowSyncInternalFlowManagerOverride = nil;
    
    [self.userSession tearDown];
    WaitForAllGroupsToBeEmpty(0.5);

    self.userSession = nil;
    
    self.selfUser = nil;
    self.user1 = nil;
    self.user2 = nil;
    self.user3 = nil;
    self.user4 = nil;
    self.user5 = nil;
    self.selfConversation = nil;
    self.selfToUser1Conversation = nil;
    self.selfToUser2Conversation = nil;
    self.groupConversation = nil;
    self.connectionSelfToUser1 = nil;
    self.connectionSelfToUser2 = nil;
    self.connectedUsers = nil;
    self.allUsers = nil;
    self.nonConnectedUsers = nil;
    
    [super tearDown];
}

- (void)storeRemoteIDForObject:(NSManagedObject *)mo;
{
    NSManagedObjectID *moid = mo.objectID;
    if (moid.isTemporaryID) {
        XCTAssert([mo.managedObjectContext obtainPermanentIDsForObjects:@[mo] error:NULL]);
        moid = mo.objectID;
    }
    
    NSString *remoteID = [mo valueForKey:@"identifier"];
    if (remoteID == nil) {
        [self.mockObjectIDToRemoteID removeObjectForKey:moid];
    } else {
        self.mockObjectIDToRemoteID[moid] = remoteID.UUID;
    }
}

- (NSUUID *)remoteIdentifierForMockObject:(NSManagedObject *)mo;
{
    return self.mockObjectIDToRemoteID[mo.objectID];
}

- (void)setDate:(NSDate *)date forAllEventsInMockConversation:(MockConversation *)conversation
{
    for(MockEvent *event in conversation.events) {
        event.time = date;
    }
    conversation.lastEventTime = date;
}

- (void)createObjects
{
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        self.selfUser = [session insertSelfUserWithName:@"The Self User"];
        self.selfUser.email = SelfUserEmail;
        self.selfUser.password = SelfUserPassword;
        self.selfUser.phone = @"";
        self.selfUser.accentID = 2;
        [session addProfilePictureToUser:self.selfUser];
        [self storeRemoteIDForObject:self.selfUser];
        
        self.user1 = [session insertUserWithName:@"Extra User1"];
        self.user1.email = @"user1@example.com";
        self.user1.phone = @"6543";
        self.user1.accentID = 3;
        [session addProfilePictureToUser:self.user1];
        [self storeRemoteIDForObject:self.user1];

        self.user2 = [session insertUserWithName:@"Extra User2"];
        self.user2.email = @"user2@example.com";
        self.user2.phone = @"4534";
        self.user2.accentID = 1;
        [self storeRemoteIDForObject:self.user2];

        self.user3 = [session insertUserWithName:@"Extra User3"];
        self.user3.email = @"user3@example.com";
        self.user3.phone = @"340958";
        self.user3.accentID = 4;
        [session addProfilePictureToUser:self.user3];
        [self storeRemoteIDForObject:self.user3];

        self.user4 = [session insertUserWithName:@"Extra User4"];
        self.user4.email = @"user4@example.com";
        self.user4.phone = @"2349857";
        self.user4.accentID = 7;
        [session addProfilePictureToUser:self.user4];
        [self storeRemoteIDForObject:self.user4];
        
        self.user5 = [session insertUserWithName:@"Extra User5"];
        self.user5.email = @"user5@example.com";
        self.user5.phone = @"555466434325";
        self.user5.accentID = 7;
        [self storeRemoteIDForObject:self.user5];
        
        self.selfConversation = [session insertSelfConversationWithSelfUser:self.selfUser];
        self.selfConversation.identifier = self.selfUser.identifier;
        [self storeRemoteIDForObject:self.selfConversation];

        self.selfToUser1Conversation = [session insertOneOnOneConversationWithSelfUser:self.selfUser otherUser:self.user1];
        self.selfToUser1Conversation.creator = self.selfUser;
        [self.selfToUser1Conversation setValue:@"Connection conversation to user 1" forKey:@"name"];
        [self storeRemoteIDForObject:self.selfToUser1Conversation];

        self.connectionSelfToUser1 = [session insertConnectionWithSelfUser:self.selfUser toUser:self.user1];
        self.connectionSelfToUser1.status = @"accepted";
        self.connectionSelfToUser1.lastUpdate = [NSDate dateWithTimeIntervalSinceNow:-3];
        self.connectionSelfToUser1.conversation = self.selfToUser1Conversation;
        
        self.selfToUser2Conversation = [session insertOneOnOneConversationWithSelfUser:self.selfUser otherUser:self.user2];
        self.selfToUser2Conversation.creator = self.user2;
        [self.selfToUser2Conversation setValue:@"Connection conversation to user 2" forKey:@"name"];
        [self storeRemoteIDForObject:self.selfToUser2Conversation];

        self.connectionSelfToUser2 = [session insertConnectionWithSelfUser:self.selfUser toUser:self.user2];
        self.connectionSelfToUser2.status = @"accepted";
        self.connectionSelfToUser2.lastUpdate = [NSDate dateWithTimeIntervalSinceNow:-5];
        self.connectionSelfToUser2.conversation = self.selfToUser2Conversation;
        
        self.groupConversation = [session insertGroupConversationWithSelfUser:self.selfUser
                                                                   otherUsers:@[self.user1,
                                                                                self.user2,
                                                                                self.user3
                                                                                ]];
        self.groupConversation.creator = self.user3;
        [self storeRemoteIDForObject:self.groupConversation];
        [self.groupConversation changeNameByUser:self.selfUser name:@"Group conversation"];
        
        self.allUsers = @[self.user1, self.user2, self.user3, self.user4, self.user5];
        self.connectedUsers = @[self.user1, self.user2];
        self.nonConnectedUsers = @[self.user3, self.user4, self.user5];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    NSDate *selfConversationDate = [NSDate dateWithTimeIntervalSince1970:1400157817];
    NSDate *connection1Date = [NSDate dateWithTimeInterval:500 sinceDate:selfConversationDate];
    NSDate *connection2Date = [NSDate dateWithTimeInterval:1000 sinceDate:connection1Date];
    NSDate *groupConversationDate = [NSDate dateWithTimeInterval:1000 sinceDate:connection2Date];

    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        NOT_USED(session);
        
        [self setDate:selfConversationDate forAllEventsInMockConversation:self.selfConversation];
        [self setDate:connection1Date forAllEventsInMockConversation:self.selfToUser1Conversation];
        [self setDate:connection2Date forAllEventsInMockConversation:self.selfToUser2Conversation];
        [self setDate:groupConversationDate forAllEventsInMockConversation:self.groupConversation];
        
        self.connectionSelfToUser1.lastUpdate = connection1Date;
        self.connectionSelfToUser2.lastUpdate = connection2Date;

    }];
}

- (void)simulateAppStopped
{
    [self recreateUserSessionAndWipeCache:NO];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [session simulatePushChannelClosed];
    }];
    WaitForEverythingToBeDone();
    
    [self.syncMOC zm_tearDownCallTimer];
    [self.uiMOC zm_tearDownCallState];
    [self.syncMOC zm_tearDownCallState];
}

- (void)simulateAppRestarted
{
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForEverythingToBeDone();
    
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [session simulatePushChannelOpened];
    }];
    WaitForEverythingToBeDone();
}

- (void)recreateUserSessionAndWipeCache:(BOOL)wipeCache
{
    
    [self.userSession tearDown];
    self.userSession = nil;
    
    WaitForEverythingToBeDone();
    
    [self resetUIandSyncContextsAndResetPersistentStore:wipeCache];
    if(wipeCache) {
        [ZMPersistentCookieStorage deleteAllKeychainItems];
    }
    
    // Workaround for hotfix introduced in 40.2 to reregister for push notifications.
    // The hotfix posts a notification to reset the push tokens on ZMUserSession,
    // which will be triggered for every test and log an error caused by the pushRegistrant
    // being nil and no pushToken being present in the NSManagedObjectContext
    [self disableHotfixes];
        
    id mockAPNSEnrvironment = [OCMockObject niceMockForClass:[ZMAPNSEnvironment class]];
    [[[mockAPNSEnrvironment stub] andReturn:@"com.wire.production"] appIdentifier];
    [[[mockAPNSEnrvironment stub] andReturn:@"APNS"] transportTypeForTokenType:ZMAPNSTypeNormal];
    [[[mockAPNSEnrvironment stub] andReturn:@"APNS_VOIP"] transportTypeForTokenType:ZMAPNSTypeVoIP];

    if (self.registeredOnThisDevice) {
        // Set flag to make sure that "Started using on new device" message is suppressed
        [self.syncMOC setPersistentStoreMetadata:@YES forKey:RegisteredOnThisDeviceKey];
        [self.uiMOC setPersistentStoreMetadata:@YES forKey:RegisteredOnThisDeviceKey];
        [self.testMOC setPersistentStoreMetadata:@YES forKey:RegisteredOnThisDeviceKey];
        [self.alternativeTestMOC setPersistentStoreMetadata:@YES forKey:RegisteredOnThisDeviceKey];
        [self.searchMOC setPersistentStoreMetadata:@YES forKey:RegisteredOnThisDeviceKey];
    }
    
    [[BackgroundActivityFactory sharedInstance] setMainGroupQueue:self.uiMOC];
    [[BackgroundActivityFactory sharedInstance] setApplication:[UIApplication sharedApplication]];
    
    self.userSession = [[ZMUserSession alloc]
                        initWithTransportSession:(id)self.mockTransportSession
                        userInterfaceContext:self.uiMOC
                        syncManagedObjectContext:self.syncMOC
                        mediaManager:nil
                        apnsEnvironment:mockAPNSEnrvironment
                        operationLoop:nil
                        application:self.application
                        appVersion:@"00000"
                        appGroupIdentifier:self.groupIdentifier];
    WaitForEverythingToBeDone();
    
    [self.syncMOC zm_tearDownCallTimer];
    [self.uiMOC zm_tearDownCallState];
    [self.syncMOC zm_tearDownCallState];
}


- (void)disableHotfixes
{
    [self.syncMOC setPersistentStoreMetadata:@(YES) forKey:ZMSkipHotfix];
}

- (BOOL)loginAndWaitForSyncToBeCompleteWithEmail:(NSString *)email
                                        password:(NSString *)password
                                         timeout:(NSTimeInterval)timeout
{
    return [self loginAndWaitForSyncToBeCompleteWithEmail:email password:password timeout:timeout shouldIgnoreAuthenticationFailures:NO];
}

- (BOOL)loginAndWaitForSyncToBeCompleteWithEmail:(NSString *)email
                                        password:(NSString *)password
                                         timeout:(NSTimeInterval)timeout
              shouldIgnoreAuthenticationFailures: (BOOL)shouldIgnoreAuthenticationFailures;
{
    BOOL synchronized = [self logInWithEmail:email password:password shouldIgnoreAuthenticationFailures:shouldIgnoreAuthenticationFailures];
    
    
    synchronized = synchronized && [self waitForCustomExpectationsWithTimeout:timeout];
    
    WaitForEverythingToBeDoneWithTimeout(timeout);
    
    XCTestExpectation *e = [self expectationWithDescription:@"sync with main queue."];
    dispatch_async(dispatch_get_main_queue(), ^{
        [e fulfill];
    });
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
    
    return synchronized;

}

- (BOOL)loginAndWaitForSyncToBeCompleteWithPhone:(NSString *)phone ignoringAuthenticationFailure:(BOOL)ignoringAuthenticationFailures;
{
    BOOL synchronized = [self logInWithCredentials:[ZMPhoneCredentials credentialsWithPhoneNumber:phone verificationCode:self.mockTransportSession.phoneVerificationCodeForLogin] shouldIgnoreAuthenticationFailures:ignoringAuthenticationFailures];
    XCTAssertTrue(synchronized);
    
    synchronized = synchronized && [self waitForCustomExpectationsWithTimeout:0.5];
    
    WaitForEverythingToBeDoneWithTimeout(0.5);
    
    XCTestExpectation *e = [self expectationWithDescription:@"sync with main queue."];
    dispatch_async(dispatch_get_main_queue(), ^{
        [e fulfill];
    });
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
    
    return synchronized;
}

- (BOOL)loginAndWaitForSyncToBeCompleteWithPhone:(NSString *)phone;
{
    return [self loginAndWaitForSyncToBeCompleteWithPhone:phone ignoringAuthenticationFailure:NO];
}

- (BOOL)loginAndWaitForSyncToBeCompleteWithEmail:(NSString *)email password:(NSString *)password
{
    return [self loginAndWaitForSyncToBeCompleteWithEmail:email password:password timeout:0.5 shouldIgnoreAuthenticationFailures:NO];
}

- (BOOL)logInWithEmail:(NSString *)email password:(NSString *)password
{
    return [self logInWithEmail:email password:password shouldIgnoreAuthenticationFailures:NO];
}

- (BOOL)logInWithEmail:(NSString *)email password:(NSString *)password shouldIgnoreAuthenticationFailures:(BOOL)shouldIgnoreAuthenticationFailures
{
    return [self logInWithCredentials:[ZMEmailCredentials credentialsWithEmail:email password:password] shouldIgnoreAuthenticationFailures:shouldIgnoreAuthenticationFailures];
}

- (BOOL)logInWithCredentials:(ZMCredentials *)credentials shouldIgnoreAuthenticationFailures:(BOOL)shouldIgnoreAuthenticationFailures;
{
    id authenticationObserver = [OCMockObject niceMockForProtocol:@protocol(ZMAuthenticationObserver)];

    if (shouldIgnoreAuthenticationFailures) {
        [[authenticationObserver stub] authenticationDidFail:OCMOCK_ANY];
    } else {
        [[authenticationObserver reject] authenticationDidFail:OCMOCK_ANY];
    }

    __block BOOL didSucceed = NO;
    [[[authenticationObserver expect] andDo:^(NSInvocation *invocation ZM_UNUSED) {
        didSucceed = YES;
    }] authenticationDidSucceed];

    id token = [self.userSession addAuthenticationObserver:authenticationObserver];
    [self.userSession loginWithCredentials:credentials];
    
    BOOL done = [self waitOnMainLoopUntilBlock:^BOOL{
        return didSucceed;
    } timeout:0.5];
    
    if (self.registeredOnThisDevice) {
        // Set flag to make sure that "Started using on new device" message is suppressed
        [self.syncMOC performGroupedBlockAndWait:^{
            [self.syncMOC setPersistentStoreMetadata:@YES forKey:RegisteredOnThisDeviceKey];
        }];
        
        [self.uiMOC setPersistentStoreMetadata:@YES forKey:RegisteredOnThisDeviceKey];

    }
    
    [self.userSession removeAuthenticationObserverForToken:token];
    return done;
}

- (BOOL)logIn;
{
    return [self logInWithEmail:SelfUserEmail password:SelfUserPassword];
}


- (BOOL)logInAndWaitForSyncToBeComplete;
{
    return [self logInAndWaitForSyncToBeCompleteIgnoringAuthenticationFailures:NO];
}

- (BOOL)logInAndWaitForSyncToBeCompleteIgnoringAuthenticationFailures:(BOOL)shouldIgnoreAuthenticationFailures
{
    return [self logInAndWaitForSyncToBeCompleteWithTimeout:0.5 shouldIgnoreAuthenticationFailures:shouldIgnoreAuthenticationFailures];
}

- (BOOL)logInAndWaitForSyncToBeCompleteWithTimeout:(NSTimeInterval)timeout shouldIgnoreAuthenticationFailures:(BOOL)shouldIgnoreAuthenticationFailures
{
    return [self loginAndWaitForSyncToBeCompleteWithEmail:SelfUserEmail password:SelfUserPassword timeout:timeout shouldIgnoreAuthenticationFailures:shouldIgnoreAuthenticationFailures];
}

- (BOOL)logInAndWaitForSyncToBeCompleteWithTimeout:(NSTimeInterval)timeout
{
    return [self logInAndWaitForSyncToBeCompleteWithTimeout:timeout shouldIgnoreAuthenticationFailures:NO];
}

- (ZMUser *)userForMockUser:(MockUser *)user;
{
    NSUUID *remoteID = [self remoteIdentifierForMockObject:user];
    XCTAssertNotNil(remoteID, @"Need to register mock objects with -storeRemoteIDForObject:");
    NSFetchRequest *request = [ZMUser sortedFetchRequestWithPredicateFormat:@"remoteIdentifier_data == %@", remoteID.data];
    NSArray *result = [self.userSession.managedObjectContext executeFetchRequestOrAssert:request];
    return (0 < result.count) ? result[0] : nil;
}


- (ZMConversation *)conversationForMockConversation:(MockConversation *)conversation;
{
    NSUUID *remoteID = [self remoteIdentifierForMockObject:conversation];
    XCTAssertNotNil(remoteID, @"Need to register mock objects with -storeRemoteIDForObject:");
    NSFetchRequest *request = [ZMConversation sortedFetchRequestWithPredicateFormat:@"remoteIdentifier_data == %@", remoteID.data];
    NSError *error;
    NSArray *result = [self.userSession.managedObjectContext executeFetchRequest:request error:&error];
    XCTAssertNotNil(result, @"Fetch failed: %@", error);
    return (0 < result.count) ? result[0] : nil;
}

- (BOOL)waitForEverythingToBeDone;
{
    return [self waitForEverythingToBeDoneWithTimeout:0.5];
}

- (BOOL)waitForEverythingToBeDoneWithTimeout:(NSTimeInterval)timeout
{
    return ([self waitForAllGroupsToBeEmptyWithTimeout:timeout] &&
            [self.mockTransportSession waitForAllRequestsToCompleteWithTimeout:timeout] &&
            [self waitForAllGroupsToBeEmptyWithTimeout:timeout]);
}

- (void)searchAndConnectToUserWithName:(NSString *)searchUserName searchQuery:(NSString *)query
{
    id searchResultObserver = [OCMockObject mockForProtocol:@protocol(ZMSearchResultObserver)];
    [self verifyMockLater:searchResultObserver];
    
    __block ZMSearchResult *result;
    XCTestExpectation *searchCompleted = [self expectationWithDescription:@"second search result"];
    
    // this might be called once or twice, if the "network" thread is faster than the "sync" thread (that reads from the cache)
    [[searchResultObserver stub] didReceiveSearchResult:[OCMArg checkWithBlock:^BOOL(ZMSearchResult *searchResult) {
        if(searchResult.usersInDirectory.count > 0u) {
            result = searchResult;
            [searchCompleted fulfill];
        }
        return YES;
    }] forToken:OCMOCK_ANY];
    
    ZMSearchDirectory *searchDirectory = [[ZMSearchDirectory alloc] initWithUserSession:self.userSession];
    [searchDirectory addSearchResultObserver:searchResultObserver];
    [searchDirectory searchForUsersAndConversationsMatchingQueryString:query];
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
    XCTAssertNotNil(result);
    
    ZMSearchUser *searchUser = result.usersInDirectory.firstObject;
    XCTAssertNotNil(searchUser);
    XCTAssertEqualObjects(searchUser.displayName, searchUserName);
    XCTestExpectation *connectionCreatedExpectation = [self expectationWithDescription:@"Connection created locally"];
    
    // when
    [searchUser connectWithMessageText:@"Hola" completionHandler:^{
        [connectionCreatedExpectation fulfill];
    }];

    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
    [searchDirectory tearDown];
}

- (MockUser *)createPendingConnectionFromUserWithName:(NSString *)name uuid:(NSUUID *)uuid
{
    MockUser *mockUser = [self createUserWithName:name uuid:uuid];
    [self storeRemoteIDForObject:mockUser];
    
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        MockConnection *connection1 = [session insertConnectionWithSelfUser:self.selfUser toUser:mockUser];
        connection1.message = @"Hello, my friend.";
        connection1.status = @"pending";
        connection1.lastUpdate = [NSDate dateWithTimeIntervalSinceNow:-20000];
        MockConversation *mockConversation = [session insertConversationWithSelfUser:self.selfUser creator:mockUser otherUsers:nil type:ZMTConversationTypeInvalid];
        connection1.conversation = mockConversation;
        [self storeRemoteIDForObject:mockConversation];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    return mockUser;
}

- (MockUser *)createSentConnectionToUserWithName:(NSString *)name uuid:(NSUUID *)uuid
{
    MockUser *mockUser = [self createUserWithName:name uuid:uuid];
    [self storeRemoteIDForObject:mockUser];
    
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        MockConnection *connection1 = [session insertConnectionWithSelfUser:self.selfUser toUser:mockUser];
        connection1.message = @"Hello, my friend.";
        connection1.status = @"sent";
        connection1.lastUpdate = [NSDate dateWithTimeIntervalSinceNow:-20000];
        MockConversation *mockConversation = [session insertConversationWithSelfUser:self.selfUser creator:mockUser otherUsers:nil type:ZMTConversationTypeInvalid];
        connection1.conversation = mockConversation;
        [self storeRemoteIDForObject:mockConversation];

    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    return mockUser;
}

- (MockUser *)createUserWithName:(NSString *)name uuid:(NSUUID *)uuid
{
    __block MockUser *user;
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        user = [session insertUserWithName:name];
        user.identifier = uuid.transportString;
    }];
    return user;
}

- (void)prefetchRemoteClientByInsertingMessageInConversation:(MockConversation *)conversation;
{
    ZMConversation *realConversation = [self conversationForMockConversation:conversation];
    [self.userSession performChanges:^{
        [realConversation appendMessageWithText:@"hum, t'es sûr?"];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)establishSessionBetweenSelfUserAndMockUser:(MockUser *)mockUser
{
    [self.mockTransportSession performRemoteChanges:^(id<MockTransportSessionObjectCreation> _Nonnull session) {
        if (mockUser.clients.count == 0) {
            [session registerClientForUser:mockUser label:@"Wire for MS-DOS" type:@"permanent"];
        }
       
        for (MockUserClient* client in mockUser.clients) {
            [self.syncMOC performGroupedBlockAndWait:^{
                [self establishSessionFromSelfToRemoteClient:client];
            }];
        }
    }];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)remotelyAppendSelfConversationWithZMClearedForMockConversation:(MockConversation *)mockConversation
                                                                atTime:(NSDate *)newClearedTimeStamp
{
    ZMGenericMessage *genericMessage = [ZMGenericMessage messageWithClearedTimestamp:newClearedTimeStamp
                                                                ofConversationWithID:mockConversation.identifier
                                                                               nonce:[NSUUID createUUID].transportString];
    
    // when
    [self.mockTransportSession performRemoteChanges:^(id session) {
        NOT_USED(session);
        [self.selfConversation insertClientMessageFromUser:self.selfUser data:genericMessage.data];
    }];
}

- (void)remotelyAppendSelfConversationWithZMLastReadForMockConversation:(MockConversation *)mockConversation
                                                                 atTime:(NSDate *)newClearedTimeStamp
{
    ZMGenericMessage *genericMessage = [ZMGenericMessage messageWithLastRead:newClearedTimeStamp
                                                        ofConversationWithID:mockConversation.identifier
                                                                       nonce:[NSUUID createUUID].transportString];
    
    // when
    [self.mockTransportSession performRemoteChanges:^(id session) {
        NOT_USED(session);
        [self.selfConversation insertClientMessageFromUser:self.selfUser data:genericMessage.data];
    }];
}

- (void)remotelyAppendSelfConversationWithZMMessageHideForMessageID:(NSString *)messageID
                                                     conversationID:(NSString *)conversationID;
{
    ZMGenericMessage *genericMessage = [ZMGenericMessage messageWithHideMessage:messageID
                                                                 inConversation:conversationID
                                                                          nonce:[NSUUID createUUID].transportString];
    
    // when
    [self.mockTransportSession performRemoteChanges:^(id session) {
        NOT_USED(session);
        [self.selfConversation insertClientMessageFromUser:self.selfUser data:genericMessage.data];
    }];
}

@end


@implementation  MockFlowManager (AdditionalMethods)

- (BOOL)isReady
{
    return YES;
}

@end
