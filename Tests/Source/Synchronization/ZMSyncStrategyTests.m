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


@import UIKit;
@import ZMTransport;
@import zmessaging;
@import ZMCDataModel;


#import "MessagingTest.h"
#import "ZMUserSession+Internal.h"
#import "ZMConnectionTranscoder.h"
#import "ZMSyncStrategy+Internal.h"
#import "ZMUserTranscoder.h"
#import "ZMSyncState.h"
#import "ZMUnauthenticatedState.h"
#import "ZMEventProcessingState.h"
#import "ZMSlowSyncPhaseOneState.h"
#import "ZMSlowSyncPhaseTwoState.h"
#import "ZMConversationTranscoder.h"
#import "ZMSelfTranscoder.h"
#import "ZMMessageTranscoder.h"
#import "ZMConversationEventsTranscoder.h"
#import "ZMAssetTranscoder.h"
#import "ZMUserImageTranscoder.h"
#import "ZMSyncStateMachine.h"
#import "ZMAuthenticationStatus.h"
#import "ZMClientRegistrationStatus.h"
#import "ZMUpdateEventsBuffer.h"
#import "ZMMissingUpdateEventsTranscoder.h"
#import "ZMRegistrationTranscoder.h"
#import "ZMFlowSync.h"
#import "ZMPushTokenTranscoder.h"
#import "ZMCallStateTranscoder.h"
#import "ZMOperationLoop.h"
#import "ZMKnockTranscoder.h"
#import "ZMTypingTranscoder.h"
#import "ZMRemovedSuggestedPeopleTranscoder.h"
#import "AVSMediaManager.h"
#import "AVSFlowManager.h"
#import "ZMLoginCodeRequestTranscoder.h"
#import "ZMPhoneNumberVerificationTranscoder.h"
#import "ZMUserProfileUpdateTranscoder.h"
#import "ZMUserProfileUpdateStatus.h"
#import "ZMBadge.h"
#import "ZMMessageTranscoder+Internal.h"
#import "ZMClientMessageTranscoder.h"
#import "MessagingTest+EventFactory.h"
#import "zmessaging_iOS_Tests-Swift.h"


@interface ZMSyncStrategyTests : MessagingTest

@property (nonatomic) ZMSyncStrategy *sut;
@property (nonatomic) ZMAuthenticationStatus *authenticationStatus;
@property (nonatomic) ZMUserProfileUpdateStatus *userProfileUpdateStatus;
@property (nonatomic) ZMClientRegistrationStatus *clientRegistrationStatus;
@property (nonatomic) ClientUpdateStatus *clientUpdateStatus;

@property (nonatomic) id stateMachine;
@property (nonatomic) NSArray *syncObjects;
@property (nonatomic) id updateEventsBuffer;
@property (nonatomic) id syncStateDelegate;
@property (nonatomic) id backgroundableSession;
@property (nonatomic) id conversationTranscoder;
@property (nonatomic) BOOL shouldStubContextChangeTrackers;
@property (nonatomic) id mockUpstreamSync1;
@property (nonatomic) id mockUpstreamSync2;
@property (nonatomic) NSFetchRequest *fetchRequestForTrackedObjects1;
@property (nonatomic) NSFetchRequest *fetchRequestForTrackedObjects2;
@property (nonatomic) id mockDispatcher;
@property (nonatomic) ZMBadge *badge;

@end



@implementation ZMSyncStrategyTests;

- (void)setUp
{
    [super setUp];
    
    self.badge = [[ZMBadge alloc] initWithApplication:self.application];
    self.mockDispatcher = [OCMockObject niceMockForClass:[ZMLocalNotificationDispatcher class]];
    self.mockUpstreamSync1 = [OCMockObject mockForClass:[ZMUpstreamModifiedObjectSync class]];
    self.mockUpstreamSync2 = [OCMockObject mockForClass:[ZMUpstreamModifiedObjectSync class]];
    [self verifyMockLater:self.mockUpstreamSync1];
    [self verifyMockLater:self.mockUpstreamSync2];
    
    self.authenticationStatus = [[ZMAuthenticationStatus alloc] initWithManagedObjectContext:self.syncMOC cookie:nil];
    self.userProfileUpdateStatus = [[ZMUserProfileUpdateStatus alloc] initWithManagedObjectContext:self.syncMOC];
    self.clientRegistrationStatus = [[ZMClientRegistrationStatus alloc] initWithManagedObjectContext:self.syncMOC loginCredentialProvider:self.authenticationStatus updateCredentialProvider:self.userProfileUpdateStatus cookie:nil registrationStatusDelegate:nil];
    self.clientUpdateStatus = [[ClientUpdateStatus alloc] initWithSyncManagedObjectContext:self.syncMOC];
    
    self.backgroundableSession = [OCMockObject mockForProtocol:@protocol(ZMBackgroundable)];
    [self verifyMockLater:self.backgroundableSession];
    
    id userTranscoder = [OCMockObject mockForClass:ZMUserTranscoder.class];
    [[[[userTranscoder expect] andReturn:userTranscoder] classMethod] alloc];
    (void) [[[userTranscoder expect] andReturn:userTranscoder] initWithManagedObjectContext:self.syncMOC];

    self.conversationTranscoder = [OCMockObject mockForClass:ZMConversationTranscoder.class];
    [[[[self.conversationTranscoder expect] andReturn:self.conversationTranscoder] classMethod] alloc];
    (void) [[[self.conversationTranscoder expect] andReturn:self.conversationTranscoder] initWithManagedObjectContext:self.syncMOC authenticationStatus:OCMOCK_ANY accountStatus:OCMOCK_ANY syncStrategy:OCMOCK_ANY];

    id systemMessageTranscoder = [OCMockObject mockForClass:ZMSystemMessageTranscoder.class];
    [[[[systemMessageTranscoder expect] andReturn:systemMessageTranscoder] classMethod] alloc];
    (void) [[[systemMessageTranscoder expect] andReturn:systemMessageTranscoder] initWithManagedObjectContext:self.syncMOC upstreamInsertedObjectSync:nil localNotificationDispatcher:self.mockDispatcher messageExpirationTimer:nil];

    id clientMessageTranscoder = [OCMockObject mockForClass:ZMClientMessageTranscoder.class];
    [[[[clientMessageTranscoder expect] andReturn:clientMessageTranscoder] classMethod] alloc];
    (void) [[[clientMessageTranscoder expect] andReturn:clientMessageTranscoder] initWithManagedObjectContext:self.syncMOC localNotificationDispatcher:self.mockDispatcher clientRegistrationStatus:OCMOCK_ANY apnsConfirmationStatus:OCMOCK_ANY];

    id knockTranscoder = [OCMockObject mockForClass:ZMKnockTranscoder.class];
    [[[[knockTranscoder expect] andReturn:knockTranscoder] classMethod] alloc];
    (void) [[[knockTranscoder expect] andReturn:knockTranscoder] initWithManagedObjectContext:self.syncMOC];

    id selfTranscoder = [OCMockObject mockForClass:ZMSelfTranscoder.class];
    [[[[selfTranscoder expect] andReturn:selfTranscoder] classMethod] alloc];
    (void) [[[selfTranscoder expect] andReturn:selfTranscoder] initWithClientRegistrationStatus:OCMOCK_ANY managedObjectContext:self.syncMOC];

    id connectionTranscoder = [OCMockObject mockForClass:ZMConnectionTranscoder.class];
    [[[[connectionTranscoder expect] andReturn:connectionTranscoder] classMethod] alloc];
    (void) [[[connectionTranscoder expect] andReturn:connectionTranscoder] initWithManagedObjectContext:self.syncMOC];

    id registrationTranscoder = [OCMockObject mockForClass:ZMRegistrationTranscoder.class];
    [[[[registrationTranscoder expect] andReturn:registrationTranscoder] classMethod] alloc];
    (void) [[[registrationTranscoder expect] andReturn:registrationTranscoder] initWithManagedObjectContext:self.syncMOC authenticationStatus:self.authenticationStatus];

    id missingUpdateEventsTranscoder = [OCMockObject mockForClass:ZMMissingUpdateEventsTranscoder.class];
    [[[[missingUpdateEventsTranscoder expect] andReturn:missingUpdateEventsTranscoder] classMethod] alloc];
    (void) [[[missingUpdateEventsTranscoder expect] andReturn:missingUpdateEventsTranscoder] initWithSyncStrategy:OCMOCK_ANY];
    
    id flowTranscoder = [OCMockObject mockForClass:ZMFlowSync.class];
    [[[[flowTranscoder expect] andReturn:flowTranscoder] classMethod] alloc];
    (void)[[[flowTranscoder expect] andReturn:flowTranscoder] initWithMediaManager:nil onDemandFlowManager:nil syncManagedObjectContext:self.syncMOC uiManagedObjectContext:self.uiMOC application:self.application];

    id userImageTranscoder = [OCMockObject mockForClass:ZMUserImageTranscoder.class];
    [[[[userImageTranscoder expect] andReturn:userImageTranscoder] classMethod] alloc];
    (void) [[[userImageTranscoder expect] andReturn:userImageTranscoder] initWithManagedObjectContext:self.syncMOC imageProcessingQueue:OCMOCK_ANY];

    id assetTranscoder = [OCMockObject mockForClass:ZMAssetTranscoder.class];
    [[[[assetTranscoder expect] andReturn:assetTranscoder] classMethod] alloc];
    (void) [[[assetTranscoder expect] andReturn:assetTranscoder] initWithManagedObjectContext:self.syncMOC];

    id pushTokenTranscoder = [OCMockObject mockForClass:ZMPushTokenTranscoder.class];
    [[[[pushTokenTranscoder expect] andReturn:pushTokenTranscoder] classMethod] alloc];
    (void) [[[pushTokenTranscoder expect] andReturn:pushTokenTranscoder] initWithManagedObjectContext:self.syncMOC clientRegistrationStatus:OCMOCK_ANY];

    id callStateTranscoder = [OCMockObject mockForClass:ZMCallStateTranscoder.class];
    [[[[callStateTranscoder expect] andReturn:callStateTranscoder] classMethod] alloc];
    (void) [[[callStateTranscoder expect] andReturn:callStateTranscoder] initWithSyncManagedObjectContext:self.syncMOC uiManagedObjectContext:self.uiMOC objectStrategyDirectory:OCMOCK_ANY];
    
    id typingTranscoder = [OCMockObject mockForClass:ZMTypingTranscoder.class];
    [[[[typingTranscoder expect] andReturn:typingTranscoder] classMethod] alloc];
    (void) [[[typingTranscoder expect] andReturn:typingTranscoder] initWithManagedObjectContext:self.syncMOC userInterfaceContext:self.uiMOC];
    
    id removedSuggestedPeopleTranscoder = [OCMockObject mockForClass:ZMRemovedSuggestedPeopleTranscoder.class];
    [[[[removedSuggestedPeopleTranscoder expect] andReturn:removedSuggestedPeopleTranscoder] classMethod] alloc];
    (void) [[[removedSuggestedPeopleTranscoder expect] andReturn:removedSuggestedPeopleTranscoder] initWithManagedObjectContext:self.syncMOC];
    
    id loginCodeRequestTranscoder = [OCMockObject mockForClass:ZMLoginCodeRequestTranscoder.class];
    [[[[loginCodeRequestTranscoder expect] andReturn:loginCodeRequestTranscoder] classMethod] alloc];
    (void) [[[loginCodeRequestTranscoder expect] andReturn:loginCodeRequestTranscoder] initWithManagedObjectContext:self.syncMOC authenticationStatus:self.authenticationStatus];
    
    id phoneNumberVerificationTranscoder = [OCMockObject mockForClass:ZMPhoneNumberVerificationTranscoder.class];
    [[[[phoneNumberVerificationTranscoder expect] andReturn:phoneNumberVerificationTranscoder] classMethod] alloc];
    (void) [[[phoneNumberVerificationTranscoder expect] andReturn:phoneNumberVerificationTranscoder] initWithManagedObjectContext:self.syncMOC authenticationStatus:self.authenticationStatus];
    
    id userProfileUpdateTranscoder = [OCMockObject mockForClass:ZMUserProfileUpdateTranscoder.class];
    [[[[userProfileUpdateTranscoder expect] andReturn:userProfileUpdateTranscoder] classMethod] alloc];
    (void) [[[userProfileUpdateTranscoder expect] andReturn:userProfileUpdateTranscoder] initWithManagedObjectContext:self.syncMOC userProfileUpdateStatus:self.userProfileUpdateStatus];
    
    self.stateMachine = [OCMockObject mockForClass:ZMSyncStateMachine.class];
    [[[[self.stateMachine expect] andReturn:self.stateMachine] classMethod] alloc];
    [[self.stateMachine stub] tearDown];
    (void) [[[self.stateMachine expect] andReturn:self.stateMachine] initWithAuthenticationStatus:self.authenticationStatus
                                                                         clientRegistrationStatus:self.clientRegistrationStatus
                                                                          objectStrategyDirectory:OCMOCK_ANY
                                                                                syncStateDelegate:OCMOCK_ANY
                                                                            backgroundableSession:self.backgroundableSession
                                                                                      application:self.application
            ];
    [self verifyMockLater:self.stateMachine];
    
    self.updateEventsBuffer = [OCMockObject mockForClass:ZMUpdateEventsBuffer.class];
    [[[[self.updateEventsBuffer expect] andReturn:self.updateEventsBuffer] classMethod] alloc];
    (void) [[[self.updateEventsBuffer expect] andReturn:self.updateEventsBuffer] initWithUpdateEventConsumer:OCMOCK_ANY];
    [self verifyMockLater:self.updateEventsBuffer];
    
    self.syncStateDelegate = [OCMockObject niceMockForProtocol:@protocol(ZMSyncStateDelegate)];

    self.syncObjects = @[
                         connectionTranscoder,
                         userTranscoder,
                         self.conversationTranscoder,
                         selfTranscoder,
                         systemMessageTranscoder,
                         clientMessageTranscoder,
                         knockTranscoder,
                         assetTranscoder,
                         userImageTranscoder,
                         missingUpdateEventsTranscoder,
                         registrationTranscoder,
                         flowTranscoder,
                         pushTokenTranscoder,
                         callStateTranscoder,
                         typingTranscoder,
                         removedSuggestedPeopleTranscoder,
                         loginCodeRequestTranscoder,
                         phoneNumberVerificationTranscoder,
                         userProfileUpdateTranscoder
                         ];
    
    for(ZMObjectSyncStrategy *strategy in self.syncObjects) {
        [[(id) strategy stub] tearDown];
        [self verifyMockLater:strategy];
    }
    self.fetchRequestForTrackedObjects1 = [NSFetchRequest fetchRequestWithEntityName:@"User"];
    self.fetchRequestForTrackedObjects1.predicate = [NSPredicate predicateWithFormat:@"name != nil"];
    self.fetchRequestForTrackedObjects2 = [NSFetchRequest fetchRequestWithEntityName:@"Conversation"];
    self.fetchRequestForTrackedObjects2.predicate = [NSPredicate predicateWithFormat:@"userDefinedName != nil"];
    
    [self stubChangeTrackerBootstrapInitialization];
    
    self.sut = [[ZMSyncStrategy alloc] initWithAuthenticationCenter:self.authenticationStatus
                                            userProfileUpdateStatus:self.userProfileUpdateStatus
                                           clientRegistrationStatus:self.clientRegistrationStatus
                                                 clientUpdateStatus:self.clientUpdateStatus
                                               proxiedRequestStatus:nil
                                                      accountStatus:nil
                                       backgroundAPNSPingBackStatus:nil
                                                       mediaManager:nil
                                                onDemandFlowManager:nil
                                                            syncMOC:self.syncMOC
                                                              uiMOC:self.uiMOC
                                                  syncStateDelegate:self.syncStateDelegate
                                              backgroundableSession:self.backgroundableSession
                                       localNotificationsDispatcher:self.mockDispatcher
                                           taskCancellationProvider:OCMOCK_ANY
                                                 appGroupIdentifier:nil
                                                              badge:self.badge
                                                        application:self.application];
    
    XCTAssertEqual(self.sut.userTranscoder, userTranscoder);
    XCTAssertEqual(self.sut.userImageTranscoder, userImageTranscoder);
    XCTAssertEqual(self.sut.conversationTranscoder, self.conversationTranscoder);
    XCTAssertEqual(self.sut.systemMessageTranscoder, systemMessageTranscoder);
    XCTAssertEqual(self.sut.clientMessageTranscoder, clientMessageTranscoder);
    XCTAssertEqual(self.sut.knockTranscoder, knockTranscoder);
    XCTAssertEqual(self.sut.assetTranscoder, assetTranscoder);
    XCTAssertEqual(self.sut.selfTranscoder, selfTranscoder);
    XCTAssertEqual(self.sut.connectionTranscoder, connectionTranscoder);
    XCTAssertEqual(self.sut.registrationTranscoder, registrationTranscoder);
    XCTAssertEqual(self.sut.flowTranscoder, flowTranscoder);
    XCTAssertEqual(self.sut.pushTokenTranscoder, pushTokenTranscoder);
    XCTAssertEqual(self.sut.callStateTranscoder, callStateTranscoder);
    XCTAssertEqual(self.sut.typingTranscoder, typingTranscoder);
    XCTAssertEqual(self.sut.removedSuggestedPeopleTranscoder, removedSuggestedPeopleTranscoder);
    XCTAssertEqual(self.sut.loginCodeRequestTranscoder, loginCodeRequestTranscoder);
    XCTAssertEqual(self.sut.phoneNumberVerificationTranscoder, phoneNumberVerificationTranscoder);
    XCTAssertEqual(self.sut.userProfileUpdateTranscoder, userProfileUpdateTranscoder);
    
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)stubChangeTrackerBootstrapInitialization
{
    for(ZMObjectSyncStrategy *strategy in self.syncObjects) {
        [[[(id)strategy expect] andReturn:@[self.mockUpstreamSync1, self.mockUpstreamSync2]] contextChangeTrackers];
        [self verifyMockLater:strategy];
    }
}


- (void)tearDown;
{
    [self.sut tearDown];

    for (id syncObject in self.syncObjects) {
        [syncObject stopMocking];
    }
    [self.stateMachine stopMocking];
    self.stateMachine = nil;
    
    [self.updateEventsBuffer stopMocking];
    self.updateEventsBuffer = nil;

    self.sut = nil;
    self.authenticationStatus = nil;
    [self.clientRegistrationStatus tearDown];
    [self.clientUpdateStatus tearDown];
    self.clientRegistrationStatus = nil;
    self.clientUpdateStatus = nil;
    self.syncObjects = nil;
    self.badge = nil;
    [super tearDown];
}

- (void)testThatDownloadedEventsAreForwardedToAllIndividualObjects
{
    // given
    ZMConversation *conv = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conv.remoteIdentifier = [NSUUID createUUID];
    NSDictionary *payload = [self payloadForMessageInConversation:conv type:EventConversationAdd data:@{@"foo" : @"bar"}];
    ZMUpdateEvent *event = [ZMUpdateEvent eventFromEventStreamPayload:payload uuid:[NSUUID createUUID]];
    NSArray *eventsArray = @[event];
    
    
    // expect
    [self expectSyncObjectsToProcessEvents:YES
                                liveEvents:NO
                             decryptEvents:YES
                   returnIDsForPrefetching:YES
                                withEvents:eventsArray];
    
    // when
    [self.sut processDownloadedEvents:eventsArray];
    WaitForAllGroupsToBeEmpty(0.5);
    
}

- (void)testThatPushEventsAreProcessedForConversationEventSyncBeforeConversationSync
{
    // given
    NSString *eventType = @"user.update";
    
    NSDictionary *payload = @{
                               @"type" : eventType,
                               @"foo" : @"bar"
                               };
    
    NSDictionary *eventData = @{
                                @"id" : @"5cc1ab91-45f4-49ec-bb7a-a5517b7a4173",
                                @"payload" : @[payload],
                                };
    
    NSArray *expectedEvents = [ZMUpdateEvent eventsArrayFromPushChannelData:eventData];
    XCTAssertEqual(expectedEvents.count, 1u);
    
    // expect
    for(id obj in self.syncObjects) {
        if(obj != self.sut.conversationTranscoder) {
            [[obj stub] processEvents:OCMOCK_ANY liveEvents:YES prefetchResult:OCMOCK_ANY];
        }
    }
    
    [self expectSyncObjectsToProcessEvents:NO
                                liveEvents:NO
                             decryptEvents:YES
                   returnIDsForPrefetching:YES
                                withEvents:expectedEvents];
    
    __block BOOL didCallConversationSync = NO;
    
    [[[(id) self.sut.conversationTranscoder expect] andDo:^(NSInvocation *i ZM_UNUSED) {
        didCallConversationSync = YES;
    }] processEvents:expectedEvents liveEvents:YES prefetchResult:OCMOCK_ANY];
    
    // when
    [self.sut consumeUpdateEvents:@[expectedEvents.firstObject]];
    
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertTrue(didCallConversationSync);
}

- (void)testThatWhenItConsumesEventsTheyAreForwardedToAllIndividualObjects
{
    // given
    NSArray *eventsArray = @[[ZMUpdateEvent eventFromEventStreamPayload:@{@"type": @"conversation.member-join", @"f": @2} uuid:nil],
                             [ZMUpdateEvent eventFromEventStreamPayload:@{@"type": @"conversation.message-add", @"a": @3} uuid:nil]];
    XCTAssertEqual(eventsArray.count, 2u);
    
    // expect
    for(ZMUpdateEvent *event in eventsArray) {
            [self expectSyncObjectsToProcessEvents:YES
                                        liveEvents:YES
                                     decryptEvents:YES
                           returnIDsForPrefetching:YES
                                        withEvents:@[event]];
    }

    // when
    for(id event in eventsArray) {
        [self.sut consumeUpdateEvents:@[event]];
        WaitForAllGroupsToBeEmpty(0.5);
    }
}

- (void)testThatItAsksClientMessageTranscoderToDecryptUpdateEvents
{
    // given
    NSArray *eventsArray = @[[ZMUpdateEvent eventFromEventStreamPayload:@{@"type": @"conversation.member-join", @"f": @2} uuid:nil],
                             [ZMUpdateEvent eventFromEventStreamPayload:@{@"type": @"conversation.message-add", @"a": @3} uuid:nil]];
    XCTAssertEqual(eventsArray.count, 2u);
    
    // expect
    [self expectSyncObjectsToProcessEvents:YES
                                liveEvents:YES
                             decryptEvents:YES
                   returnIDsForPrefetching:YES
                                withEvents:eventsArray];
    
    // when
    [self.sut processUpdateEvents:eventsArray ignoreBuffer:YES];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItProcessUpdateEventsIfTheCurrentStateShouldProcessThem
{
    // given
    NSDictionary *eventData = @{
                                @"id" : @"5cc1ab91-45f4-49ec-bb7a-a5517b7a4173",
                                @"payload" : @[
                                        @{
                                            @"type" : @"user.update",
                                            @"foo" : @"bar"
                                            }
                                        ]
                                };
    NSMutableArray *expectedEvents = [NSMutableArray array];
    [expectedEvents addObjectsFromArray:[ZMUpdateEvent eventsArrayFromPushChannelData:eventData]];
    
    [[[(id) self.stateMachine stub] andReturnValue:OCMOCK_VALUE(ZMUpdateEventPolicyProcess)] updateEventsPolicy];
    
    // expect
    [self expectSyncObjectsToProcessEvents:YES
                                liveEvents:YES
                             decryptEvents:YES
                   returnIDsForPrefetching:YES
                                withEvents:expectedEvents];
    
    // when
    [self.sut processUpdateEvents:expectedEvents ignoreBuffer:NO];
    WaitForAllGroupsToBeEmpty(0.5);
}


- (void)testThatItForwardsUpdateEventsToBufferIfTheCurrentStateShouldBufferThemAndDoesNotDecryptTheUpdateEvents
{
    // given
    NSDictionary *eventData = @{
                                @"id" : @"5cc1ab91-45f4-49ec-bb7a-a5517b7a4173",
                                @"payload" : @[
                                        @{
                                            @"type" : @"user.update",
                                            @"foo" : @"bar"
                                            }
                                        ]
                                };
    NSMutableArray *expectedEvents = [NSMutableArray array];
    [expectedEvents addObjectsFromArray:[ZMUpdateEvent eventsArrayFromPushChannelData:eventData]];
    XCTAssertGreaterThan(expectedEvents.count, 0u);
    
    [[[(id) self.stateMachine stub] andReturnValue:OCMOCK_VALUE(ZMUpdateEventPolicyBuffer)] updateEventsPolicy];

    
    // expect
    [self expectSyncObjectsToProcessEvents:NO
                                liveEvents:YES
                             decryptEvents:NO
                   returnIDsForPrefetching:NO
                                withEvents:expectedEvents];

    for(id obj in expectedEvents) {
        [[self.updateEventsBuffer expect] addUpdateEvent:obj];
    }
    
    // when
    [self.sut processUpdateEvents:expectedEvents ignoreBuffer:NO];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItProcessUpdateEventsToBufferIfTheCurrentStateShouldBufferThemButIgnoreBufferIsYes
{
    // given
    NSDictionary *eventData = @{
                                @"id" : @"5cc1ab91-45f4-49ec-bb7a-a5517b7a4173",
                                @"payload" : @[
                                        @{
                                            @"type" : @"user.update",
                                            @"foo" : @"bar"
                                            }
                                        ]
                                };
    NSMutableArray *expectedEvents = [NSMutableArray array];
    [expectedEvents addObjectsFromArray:[ZMUpdateEvent eventsArrayFromPushChannelData:eventData]];
    XCTAssertGreaterThan(expectedEvents.count, 0u);
    
    [[[(id) self.stateMachine stub] andReturnValue:OCMOCK_VALUE(ZMUpdateEventPolicyBuffer)] updateEventsPolicy];
    
    // expect
    [self expectSyncObjectsToProcessEvents:YES
                                liveEvents:YES
                             decryptEvents:YES
                   returnIDsForPrefetching:YES
                                withEvents:expectedEvents];
    [[self.updateEventsBuffer reject] addUpdateEvent:OCMOCK_ANY];
    
    // when
    [self.sut processUpdateEvents:expectedEvents ignoreBuffer:YES];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItDoesNotProcessUpdateEventsIfTheCurrentStateShouldIgnoreThem
{
    // given
    NSDictionary *eventData = @{
                                @"id" : @"5cc1ab91-45f4-49ec-bb7a-a5517b7a4173",
                                @"payload" : @[
                                        @{
                                            @"type" : @"conversation.message-add",
                                            @"foo" : @"bar"
                                            }
                                        ]
                                };
    NSMutableArray *expectedEvents = [NSMutableArray array];
    [expectedEvents addObjectsFromArray:[ZMUpdateEvent eventsArrayFromPushChannelData:eventData]];
    XCTAssertGreaterThan(expectedEvents.count, 0u);
    
    [[[(id) self.stateMachine stub] andReturnValue:OCMOCK_VALUE(ZMUpdateEventPolicyIgnore)] updateEventsPolicy];
    
    
    // expect
    for(id obj in self.syncObjects) {
        [[obj reject] processEvents:OCMOCK_ANY liveEvents:YES prefetchResult:OCMOCK_ANY];
    }
    
    // when
    [self.sut processUpdateEvents:expectedEvents ignoreBuffer:NO];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItDoesProcessesFlowUpdateEvents;
{
    // given
    NSMutableArray *expectedEvents = [NSMutableArray array];
    for (ZMUpdateEventType type = ZMUpdateEventUnknown; type < ZMUpdateEvent_LAST; type++) {
        // given
        NSString *typeString = [ZMUpdateEvent eventTypeStringForUpdateEventType:type];
        if (typeString == nil) {
            continue;
        }
        NSDictionary *eventData = @{
                                    @"id" : NSUUID.createUUID.transportString,
                                    @"payload" : @[
                                            @{
                                                @"type" :  typeString,
                                                @"foo" : @"bar"
                                                }
                                            ]
                                    };
        ZMUpdateEvent *event = [ZMUpdateEvent eventsArrayFromPushChannelData:eventData].firstObject;
        if (event.isFlowEvent) {
            [expectedEvents addObject:event];
        }
    }
    [[[(id) self.stateMachine stub] andReturnValue:OCMOCK_VALUE(ZMUpdateEventPolicyProcess)] updateEventsPolicy];
    XCTAssertGreaterThan(expectedEvents.count, 0u);
    
    // expect
    [self expectSyncObjectsToProcessEvents:YES
                                liveEvents:YES
                             decryptEvents:YES
                   returnIDsForPrefetching:YES
                                withEvents:expectedEvents];
    [[self.updateEventsBuffer reject] addUpdateEvent:OCMOCK_ANY];
    
    // when
    [self.sut processUpdateEvents:expectedEvents ignoreBuffer:NO];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItDoesProcessCallEventsIfTheCurrentEventPolicyIsIgnore;
{
    NSDictionary *eventData = @{
                                @"id" : @"5cc1ab91-45f4-49ec-bb7a-a5517b7a4173",
                                @"payload" : @[
                                        @{
                                            @"type" : @"call.state",
                                            @"foo" : @"bar"
                                            }
                                        ]
                                };
    NSMutableArray *expectedEvents = [NSMutableArray array];
    [expectedEvents addObjectsFromArray:[ZMUpdateEvent eventsArrayFromPushChannelData:eventData]];
    XCTAssertGreaterThan(expectedEvents.count, 0u);
    [[[(id) self.stateMachine stub] andReturnValue:OCMOCK_VALUE(ZMUpdateEventPolicyIgnore)] updateEventsPolicy];
    
    
    // expect
    [self expectSyncObjectsToProcessEvents:YES
                                liveEvents:YES
                             decryptEvents:YES
                   returnIDsForPrefetching:YES
                                withEvents:expectedEvents];
    [[self.updateEventsBuffer reject] addUpdateEvent:OCMOCK_ANY];

    // when
    [self.sut processUpdateEvents:expectedEvents ignoreBuffer:NO];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItDoesProcessesCallingUpdateEventsIfTheCurrentEventPolicyIsBuffer;
{
    // given
    NSDictionary *eventData = @{
                                @"id" : @"5cc1ab91-45f4-49ec-bb7a-a5517b7a4173",
                                @"payload" : @[
                                        @{
                                            @"type" : @"call.state",
                                            @"foo" : @"bar"
                                            }
                                        ]
                                };
    NSMutableArray *expectedEvents = [NSMutableArray array];
    [expectedEvents addObjectsFromArray:[ZMUpdateEvent eventsArrayFromPushChannelData:eventData]];
    XCTAssertGreaterThan(expectedEvents.count, 0u);
    
    [[[(id) self.stateMachine stub] andReturnValue:OCMOCK_VALUE(ZMUpdateEventPolicyBuffer)] updateEventsPolicy];
    
    
    // expect
    [self expectSyncObjectsToProcessEvents:NO
                                liveEvents:YES
                             decryptEvents:NO
                   returnIDsForPrefetching:NO
                                withEvents:expectedEvents];
    
    [[self.updateEventsBuffer expect] addUpdateEvent:OCMOCK_ANY];
    
    // when
    [self.sut processUpdateEvents:expectedEvents ignoreBuffer:NO];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItDoesProcessUpdateEventsIfTheCurrentStateShouldIgnoreThemButIgnoreBuffesIsYes
{
    // given
    NSDictionary *eventData = @{
                                @"id" : @"5cc1ab91-45f4-49ec-bb7a-a5517b7a4173",
                                @"payload" : @[
                                        @{
                                            @"type" : @"user.update",
                                            @"foo" : @"bar"
                                            }
                                        ]
                                };
    NSMutableArray *expectedEvents = [NSMutableArray array];
    [expectedEvents addObjectsFromArray:[ZMUpdateEvent eventsArrayFromPushChannelData:eventData]];
    XCTAssertGreaterThan(expectedEvents.count, 0u);
    
    [[[(id) self.stateMachine stub] andReturnValue:OCMOCK_VALUE(ZMUpdateEventPolicyIgnore)] updateEventsPolicy];
    
    
    // expect
    [self expectSyncObjectsToProcessEvents:YES
                                liveEvents:YES
                             decryptEvents:YES
                   returnIDsForPrefetching:YES
                                withEvents:expectedEvents];
    
    // when
    [self.sut processUpdateEvents:expectedEvents ignoreBuffer:YES];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItItCreatesAFetchBatchRequestWithTheNoncesAndRemoteIdentifiersFromUpdateEvents
{
    // given
    id <ZMTransportData> firstPayload = @{
                                          @"conversation" : NSUUID.createUUID,
                                          @"data" : @{
                                                  @"last_read" : @"3.800122000a5efe70"
                                                  },
                                          @"from": NSUUID.createUUID.transportString,
                                          @"time" : NSDate.date.transportString,
                                          @"type" : @"conversation.member-update"
                                          };
    
    id <ZMTransportData> secondPayload = @{
                                           @"conversation" : NSUUID.createUUID,
                                           @"data" : @{
                                                   @"content" : @"www.wire.com",
                                                   @"nonce" : NSUUID.createUUID,
                                                   },
                                           @"from": NSUUID.createUUID.transportString,
                                           @"id" : @"6c9d.800122000a5911ba",
                                           @"time" : NSDate.date.transportString,
                                           @"type" : @"conversation.message-add"
                                           };
    
    NSArray <ZMUpdateEvent *> *events = @[
                                          [ZMUpdateEvent eventFromEventStreamPayload:firstPayload uuid:nil],
                                          [ZMUpdateEvent eventFromEventStreamPayload:secondPayload uuid:nil]
                                          ];
    
    // expect
    [[self.conversationTranscoder expect] conversationRemoteIdentifiersToPrefetchToProcessEvents:events];
    
    for (id obj in self.syncObjects) {
        for (Class class in self.transcodersExpectedToReturnNonces) {
            if ([obj isKindOfClass:class]) {
                [[obj expect] messageNoncesToPrefetchToProcessEvents:events];
            }
        }
    }

    // `returnIDsForPrefetching` is set to NO here because we explicitly
    // expect for the transcoders we expect to conform to the protocol above
    [self expectSyncObjectsToProcessEvents:YES
                                liveEvents:YES
                             decryptEvents:YES
                   returnIDsForPrefetching:NO
                                withEvents:events];
    
    // when
    [self.sut processUpdateEvents:events ignoreBuffer:YES];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItRequestsNoncesAndRemoteIdentifiersToPrefetchFromAllOfItsSyncObjects
{
    // given
    id <ZMTransportData> payload = @{
                                     @"conversation" : NSUUID.createUUID,
                                     @"data" : @{ @"last_read" : @"3.800122000a5efe70" },
                                     @"time" : NSDate.date.transportString,
                                     @"type" : @"conversation.member-update"
                                     };
    
    NSArray <ZMUpdateEvent *> *events = @[[ZMUpdateEvent eventFromEventStreamPayload:payload uuid:nil]];
    
    // expect
    [[self.conversationTranscoder expect] conversationRemoteIdentifiersToPrefetchToProcessEvents:events];
    
    for (id obj in self.syncObjects) {
        for (Class class in self.transcodersExpectedToReturnNonces) {
            if ([obj isKindOfClass:class]) {
                [[obj expect] messageNoncesToPrefetchToProcessEvents:events];
            }
        }
    }
    
    // when
    [self.sut fetchRequestBatchForEvents:events];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatCallingNextRequestFetchesObjectsAndDistributesThemToTheChangeTracker
{
    // given
    [[[(id)self.stateMachine stub] andReturn:OCMOCK_ANY] nextRequest];
    __block ZMUser *user;
    __block ZMConversation *conversation;
    [self.syncMOC performGroupedBlockAndWait:^{
        user = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user.name = @"User1";
        conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.userDefinedName = @"Conversation1";
        [self.syncMOC saveOrRollback];
    }];
    
    // expect
    for (id<ZMObjectStrategy> syncObject in self.syncObjects) {
        [(ZMUpstreamModifiedObjectSync*)[[self.mockUpstreamSync1 stub] andReturn:self.fetchRequestForTrackedObjects1] fetchRequestForTrackedObjects];
        [(ZMUpstreamModifiedObjectSync*)[[self.mockUpstreamSync2 stub] andReturn:self.fetchRequestForTrackedObjects2] fetchRequestForTrackedObjects];
        [[self.mockUpstreamSync1 expect] addTrackedObjects:[NSSet setWithObject:user]];
        [[self.mockUpstreamSync2 expect] addTrackedObjects:[NSSet setWithObject:conversation]];
        [self verifyMockLater:syncObject];
    }
    
    // when
    (void)[self.sut nextRequest];
}


- (void)testThatNextRequestReturnsTheRequestReturnedByTheStateMachine
{
    // given
    ZMTransportRequest *dummyRequest = [OCMockObject mockForClass:ZMTransportRequest.class];
    [(ZMUpstreamModifiedObjectSync*)[self.mockUpstreamSync1 stub] fetchRequestForTrackedObjects];
    [(ZMUpstreamModifiedObjectSync*)[self.mockUpstreamSync2 stub] fetchRequestForTrackedObjects];

    // expect
    [[[(id)self.stateMachine expect] andReturn:dummyRequest] nextRequest];
    
    // when
    ZMTransportRequest *request = [self.sut nextRequest];
    
    // then
    XCTAssertEqualObjects(dummyRequest, request);

}

- (void)testThatManagedObjectChangesArePassedToAllSyncObjectsCaches
{
    
    // given
    id firstObject = [OCMockObject niceMockForClass:ZMManagedObject.class];
    id secondObject = [OCMockObject niceMockForClass:ZMManagedObject.class];
    
    [[[firstObject stub] andReturn:nil] entity];
    [[[secondObject stub] andReturn:nil] entity];
    
    NSSet *cacheInsertSet = [NSSet setWithObject:firstObject];
    NSSet *cacheUpdateSet = [NSSet setWithObject:secondObject];
    
    NSMutableSet *totalSet = [NSMutableSet setWithSet:cacheInsertSet];
    [totalSet unionSet:cacheUpdateSet];
    
    // expect
    for (id<ZMObjectStrategy> syncObject in self.syncObjects) {
        [[self.mockUpstreamSync1 expect] objectsDidChange:totalSet];
        [[self.mockUpstreamSync2 expect] objectsDidChange:totalSet];
        
        [self verifyMockLater:syncObject];
    }
    
    // when
    [self.sut processSaveWithInsertedObjects:cacheInsertSet updateObjects:cacheUpdateSet];
    WaitForAllGroupsToBeEmpty(0.5);
}


- (void)testThatItSynchronizesChangesInUIContextToSyncContext
{
    // given
    
    [[self.mockUpstreamSync1 stub] objectsDidChange:OCMOCK_ANY];
    [[self.mockUpstreamSync2 stub] objectsDidChange:OCMOCK_ANY];
    
    ZMUser *uiUser = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    XCTAssertTrue([self.uiMOC saveOrRollback]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.sut.syncMOC performGroupedBlockAndWaitWithReasonableTimeout:^{
        ZMUser *syncUser =  (ZMUser *)[self.sut.syncMOC objectWithID:uiUser.objectID];
        XCTAssertNotNil(syncUser);
        XCTAssertNil(syncUser.name);
    }];
    
    NSString *name = @"very-unique-name_w938ruojfdmnsf";

    // when
    uiUser.name = name;
    XCTAssertTrue([self.uiMOC saveOrRollback]);
    WaitForAllGroupsToBeEmpty(0.5);
    // sut automagically synchronizes objects

    // then
    [self.sut.syncMOC performGroupedBlockAndWaitWithReasonableTimeout:^{
        ZMUser *syncUser =  (ZMUser *)[self.sut.syncMOC objectWithID:uiUser.objectID];
        XCTAssertNotNil(syncUser);
        XCTAssertEqualObjects(syncUser.name, name);
    }];
}

- (void)testThatItSynchronizesCallStateChangesInUIContextToSyncContext
{
    // expect
    [[self.mockUpstreamSync1 stub] objectsDidChange:OCMOCK_ANY];
    [[self.mockUpstreamSync2 stub] objectsDidChange:OCMOCK_ANY];
    
    
    // given
    ZMConversation *uiConversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    XCTAssertTrue([self.uiMOC saveOrRollback]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.sut.syncMOC performGroupedBlockAndWaitWithReasonableTimeout:^{
        ZMConversation *syncConversation =  (ZMConversation *)[self.sut.syncMOC objectWithID:uiConversation.objectID];
        XCTAssertNotNil(syncConversation);
        XCTAssertFalse(syncConversation.callDeviceIsActive);
    }];

    // when
    uiConversation.callDeviceIsActive = YES;
    XCTAssertTrue([self.uiMOC saveOrRollback]);
    WaitForAllGroupsToBeEmpty(0.5);
    // sut automagically synchronizes objects
    
    // then
    XCTAssertTrue(uiConversation.callDeviceIsActive);

    [self.sut.syncMOC performGroupedBlockAndWaitWithReasonableTimeout:^{
        ZMConversation *syncConversation =  (ZMConversation *)[self.sut.syncMOC objectWithID:uiConversation.objectID];
        XCTAssertNotNil(syncConversation);
        XCTAssertTrue(syncConversation.callDeviceIsActive);
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
}



- (void)testThatItSynchronizesChangesInSyncContextToUIContext
{
    __block ZMUser *syncUser;
    
    // expect
    [self expectationForNotification:NSManagedObjectContextObjectsDidChangeNotification object:self.uiMOC handler:nil];
    
    // when
    [self.syncMOC performGroupedBlockAndWaitWithReasonableTimeout:^{
        syncUser = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        XCTAssertTrue([self.syncMOC saveOrRollback]);
    }];
    
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
    
    ZMUser *uiUser =  (ZMUser *)[self.uiMOC objectWithID:syncUser.objectID];
    XCTAssertNotNil(uiUser);
    XCTAssertNil(uiUser.name);
    
    NSString *name = @"very-unique-name_ps9ijsdnmf";

    // and expect
    [self expectationForNotification:NSManagedObjectContextObjectsDidChangeNotification object:self.uiMOC handler:^BOOL(NSNotification *notification ZM_UNUSED) {
        return uiUser.name != nil;
    }];
    
    // when
    [self.syncMOC performGroupedBlockAndWaitWithReasonableTimeout:^{
        syncUser.name = name;
        XCTAssertTrue([self.syncMOC saveOrRollback]);
    }];
    
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.2]);
    
    // then
    XCTAssertEqualObjects(name, uiUser.name);
}

- (void)testThatItFlushesTheInternalBufferWhenAsked
{
    // expect
    [[self.updateEventsBuffer expect] processAllEventsInBuffer];
    
    // when
    [self.sut processAllEventsInBuffer];
}

- (void)testThatItCallsDataDidChangeOnStateMachineWhenDataDidChange
{
    // expect
    [[self.stateMachine expect] dataDidChange];
    
    // when
    [self.sut dataDidChange];
}

- (void)testThatARollbackTriggersAnObjectsDidChange;
{
    //
    
    // given
    __block ZMConversation *syncConversation;
    __block NSManagedObjectID *moid;
    [self.syncMOC performGroupedBlockAndWait:^{
        syncConversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        syncConversation.conversationType = ZMConversationTypeOneOnOne;
        [self.syncMOC saveOrRollback];
        moid = syncConversation.objectID;
    }];
    ZMConversation *uiConversation = (id) [self.uiMOC objectWithID:moid];
    WaitForAllGroupsToBeEmpty(0.5);
    //
    self.sut.contextMergingDisabled = YES;
    NSMutableArray *objectsDidChangeNotifications = [NSMutableArray array];
    id token1 = [[NSNotificationCenter defaultCenter] addObserverForName:NSManagedObjectContextObjectsDidChangeNotification object:self.uiMOC queue:nil usingBlock:^(NSNotification *note) {
        
        [objectsDidChangeNotifications addObject:note];
    }];
    NSMutableArray *didSaveNotificationsA = [NSMutableArray array];
    id token2A = [[NSNotificationCenter defaultCenter] addObserverForName:NSManagedObjectContextDidSaveNotification object:self.uiMOC queue:nil usingBlock:^(NSNotification *note) {
        
        [didSaveNotificationsA addObject:note];
    }];
    NSMutableArray *didSaveNotificationsB = [NSMutableArray array];
    id token2B = [[NSNotificationCenter defaultCenter] addObserverForName:NSManagedObjectContextDidSaveNotification object:self.syncMOC queue:nil usingBlock:^(NSNotification *note) {
        
        [didSaveNotificationsB addObject:note];
    }];
    //
    uiConversation.userDefinedName = @"UI";
    [self.syncMOC performGroupedBlockAndWait:^{
        syncConversation.userDefinedName = @"SYNC";
    }];
    [self.uiMOC saveOrRollback];
    [self.syncMOC performGroupedBlockAndWait:^{
        [self.syncMOC saveOrRollback];
    }];
    
    // stub
    [[self.mockUpstreamSync1 stub] objectsDidChange:OCMOCK_ANY];
    [[self.mockUpstreamSync2 stub] objectsDidChange:OCMOCK_ANY];

    // when
    //
    // The conversation in the UI context is still 'USER', and we expect
    // 1 objects-did-cahnge about it changing to 'SYNC'
    [objectsDidChangeNotifications removeAllObjects];
    XCTAssertEqualObjects(uiConversation.userDefinedName, @"UI");
    // MERGE:
    self.sut.contextMergingDisabled = NO;
    [[NSNotificationCenter defaultCenter] removeObserver:token2A];
    [[NSNotificationCenter defaultCenter] removeObserver:token2B];
    for (NSNotification *note in didSaveNotificationsA) {
        [[NSNotificationCenter defaultCenter] postNotification:note];
    }
    for (NSNotification *note in didSaveNotificationsB) {
        [[NSNotificationCenter defaultCenter] postNotification:note];
    }
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqualObjects(uiConversation.userDefinedName, @"SYNC");
    XCTAssertEqual(objectsDidChangeNotifications.count, 1u);
    NSDictionary *userInfo = [(NSNotification *) objectsDidChangeNotifications.lastObject userInfo];
    XCTAssertEqual([userInfo[NSRefreshedObjectsKey] anyObject], uiConversation);
    
    // finally
    [[NSNotificationCenter defaultCenter] removeObserver:token1];
}


- (void)testThatItReturnsTrueForCoversationsThatHasBufferedCallStateEvents
{
    // given
    NSUUID *remoteId = NSUUID.createUUID;
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.remoteIdentifier = remoteId;
        [self.syncMOC saveOrRollback];
    }];

    NSDictionary *eventData = @{
                                @"id" : @"5cc1ab91-45f4-49ec-bb7a-a5517b7a4173",
                                @"payload" : @[
                                        @{
                                            @"type" : @"call.state",
                                            @"conversation" : remoteId.transportString
                                            }
                                        ]
                                };

    NSArray *events = [ZMUpdateEvent eventsArrayFromPushChannelData:eventData];
    
    [[[(id) self.stateMachine stub] andReturnValue:OCMOCK_VALUE(ZMUpdateEventPolicyBuffer)] updateEventsPolicy];
    
    // expect
    for(id obj in events) {
        [[self.updateEventsBuffer expect] addUpdateEvent:obj];
    }
    
    [self expectSyncObjectsToProcessEvents:NO
                                liveEvents:YES
                             decryptEvents:NO
                   returnIDsForPrefetching:NO
                                withEvents:events];
    
    [[[self.updateEventsBuffer expect] andReturn:events] updateEvents];
    
    [self.sut processUpdateEvents:events ignoreBuffer:NO];
    
    // when
    NSArray *ids = [self.sut conversationIdsThatHaveBufferedUpdatesForCallState];
    
    // then
    XCTAssertTrue([ids containsObject:remoteId]);
}

- (void)testThatItReturnsFalseForConversationsThatHasNoBufferedCallStateEvents
{
    // given
    NSUUID *remoteId = NSUUID.createUUID;
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.remoteIdentifier = remoteId;
        [self.syncMOC saveOrRollback];
    }];
    
    NSDictionary *eventData = @{
                                @"id" : @"5cc1ab91-45f4-49ec-bb7a-a5517b7a4173",
                                @"payload" : @[
                                        @{
                                            @"type" : @"call.state",
                                            @"conversation" : NSUUID.createUUID.transportString
                                            }
                                        ]
                                };
    
    NSArray *events = [ZMUpdateEvent eventsArrayFromPushChannelData:eventData];
    
    [[[(id) self.stateMachine stub] andReturnValue:OCMOCK_VALUE(ZMUpdateEventPolicyBuffer)] updateEventsPolicy];
    
    // expect
    for(id obj in events) {
        [[self.updateEventsBuffer expect] addUpdateEvent:obj];
    }
    
    [self expectSyncObjectsToProcessEvents:NO
                                liveEvents:YES
                             decryptEvents:NO
                   returnIDsForPrefetching:NO
                                withEvents:events];
    
    [[[self.updateEventsBuffer expect] andReturn:events] updateEvents];

    [self.sut processUpdateEvents:events ignoreBuffer:NO];
    
    // when
    NSArray *ids = [self.sut conversationIdsThatHaveBufferedUpdatesForCallState];
    
    // then
    XCTAssertFalse([ids containsObject:remoteId]);
}

#pragma mark - Helper

- (NSSet <Class> *)transcodersExpectedToReturnNonces
{
    return @[
             ZMAssetTranscoder.class,
             ZMClientMessageTranscoder.class,
             ZMKnockTranscoder.class
             ].set;
}

- (void)expectSyncObjectsToProcessEvents:(BOOL)process liveEvents:(BOOL)liveEvents decryptEvents:(BOOL)decyptEvents returnIDsForPrefetching:(BOOL)returnIDs withEvents:(id)events;
{
    NOT_USED(decyptEvents);
    
    for (id obj in self.syncObjects) {
        if (process) {
            [[obj expect] processEvents:[OCMArg checkWithBlock:^BOOL(NSArray *receivedEvents) {
                return [receivedEvents isEqualToArray:events];
            }] liveEvents:liveEvents prefetchResult:OCMOCK_ANY];
        } else {
            [[obj reject] processEvents:OCMOCK_ANY liveEvents:liveEvents prefetchResult:OCMOCK_ANY];
        }
        
        if (returnIDs) {
            if ([obj respondsToSelector:@selector(messageNoncesToPrefetchToProcessEvents:)]) {
                [[obj expect] messageNoncesToPrefetchToProcessEvents:[OCMArg checkWithBlock:^BOOL(NSArray *receivedEvents) {
                    return [receivedEvents isEqualToArray:events];
                }]];
            }
            if ([obj respondsToSelector:@selector(conversationRemoteIdentifiersToPrefetchToProcessEvents:)]) {
                [[obj expect] conversationRemoteIdentifiersToPrefetchToProcessEvents:[OCMArg checkWithBlock:^BOOL(NSArray *receivedEvents) {
                    return [receivedEvents isEqualToArray:events];
                }]];
            }
        }
    }
}

- (ZMUpdateEvent *)otrMessageAddPayloadFromClient:(UserClient *)client text:(NSString *)text nonce:(NSUUID *)nonce
{
    ZMGenericMessage *message = [ZMGenericMessage messageWithText:text nonce:nonce.transportString];
    __block NSError *error;
    __block NSData *encryptedData;
    
    [self.syncMOC.zm_cryptKeyStore.encryptionContext perform:^(EncryptionSessionsDirectory * _Nonnull sessionsDirectory) {
        encryptedData =  [sessionsDirectory encrypt:message.data recipientClientId:client.remoteIdentifier error:&error];
    }];
    XCTAssertNil(error);
    
    NSDictionary *payload = @{
                              @"type" : @"conversation.otr-message-add",
                              @"data" : @{
                                      @"recipient" : client.remoteIdentifier,
                                      @"sender" : client.remoteIdentifier,
                                      @"text" : encryptedData.base64String
                                      },
                              @"conversation": NSUUID.createUUID.transportString,
                              @"time" : [NSDate dateWithTimeIntervalSince1970:555555].transportString
                              };
    
    return [ZMUpdateEvent eventFromEventStreamPayload:payload uuid:nil];
}

@end



@implementation ZMSyncStrategyTests (Background)

- (void)goToBackground
{
    [self.application simulateApplicationDidEnterBackground];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)goToForeground
{
    [self.application simulateApplicationWillEnterForeground];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItForwardsToStateMachineWhenTheAppEntersBackground
{
    // expect
    [[self.stateMachine expect] enterBackground];
    
    // when
    [self goToBackground];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [self.stateMachine verify];
}


- (void)testThatItForwardsToStateMachineWhenTheAppWillEnterForeground
{
    // expect
    [[self.stateMachine expect] enterForeground];
    
    // when
    [self goToForeground];
    
    // then
    [self.stateMachine verify];
}

- (void)testThatItNotifiesTheOperationLoopOfNewOperationWhenEnteringBackground
{
    // given
    [[self.stateMachine stub] enterBackground];
    [[self.stateMachine stub] enterForeground];

    
    // expect
    id mockLoop = [OCMockObject mockForClass:ZMOperationLoop.class];
    [[[mockLoop expect] classMethod] notifyNewRequestsAvailable:OCMOCK_ANY];

    // when
    [self goToBackground];
    
    // then
    [mockLoop verify];
    [mockLoop stopMocking];
}

- (void)testThatItNotifiesTheOperationLoopOfNewOperationWhenEnteringForeground
{
    // given
    [[self.stateMachine stub] enterBackground];
    [[self.stateMachine stub] enterForeground];
    
    // expect
    id mockLoop = [OCMockObject mockForClass:ZMOperationLoop.class];
    [[mockLoop expect] notifyNewRequestsAvailable:OCMOCK_ANY];
    
    // when
    [self goToForeground];
    
    // then
    [mockLoop verify];
    [mockLoop stopMocking];
}

- (void)testThatItUpdatesTheBadgeCount
{
    // given
    [[self.stateMachine stub] enterBackground];
    
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.conversationType = ZMConversationTypeGroup;
        conversation.internalEstimatedUnreadCount = 1;
        [self.syncMOC saveOrRollback];
        
        // when
        [self.sut updateBadgeCount];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.application.applicationIconBadgeNumber, 1);
}

- (void)testThatItForwardsTheBackgroundFetchRequestToTheStateMachine
{
    // given
    XCTestExpectation *expectation = [self expectationWithDescription:@"Background fetch completed"];
    ZMBackgroundFetchHandler handler = ^(ZMBackgroundFetchResult result) {
        XCTAssertEqual(result, ZMBackgroundFetchResultNewData);
        [expectation fulfill];
    };
    
    // expect
    [(ZMSyncStrategy *)[[(id) self.stateMachine expect] andCall:@selector(forward_startBackgroundFetchWithCompletionHandler:) onObject:self] startBackgroundFetchWithCompletionHandler:OCMOCK_ANY];
    
    // when
    [self.sut startBackgroundFetchWithCompletionHandler:handler];
    
    // then
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
    [(id) self.stateMachine verify];
}

- (void)forward_startBackgroundFetchWithCompletionHandler:(ZMBackgroundFetchHandler)handler;
{
    handler(ZMBackgroundFetchResultNewData);
}

@end
