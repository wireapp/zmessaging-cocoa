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


@import ZMTransport;
@import ZMCMockTransport;
@import Cryptobox;
@import zmessaging;
@import ZMCDataModel;

#import "ZMMessageTranscoderTests.h"
#import "ZMMessageTranscoder+Internal.h"
#import "ZMSyncStrategy.h"
#import "ZMMessageExpirationTimer.h"
#import "ZMLocalNotificationDispatcher.h"
#import <zmessaging/zmessaging-Swift.h>

static NSString const *EventTypeMessageAdd = @"conversation.message-add";

static NSString const *GetConversationURL = @"/conversations/%@/events?start=%@&end=%@";


@implementation ZMMessageTranscoderTests

- (void)setUp
{
    [super setUp];
    
    self.mockExpirationTimer = [OCMockObject mockForClass:ZMMessageExpirationTimer.class];
    self.upstreamObjectSync = [OCMockObject mockForClass:ZMUpstreamInsertedObjectSync.class];
    self.notificationDispatcher =
#if TARGET_OS_IPHONE
    [OCMockObject mockForClass:ZMLocalNotificationDispatcher.class];
#else
    nil;
#endif

    [self verifyMockLater:self.upstreamObjectSync];
    [self setupSelfConversation];
}

- (ZMMessageTranscoder *)sut
{
    if (!_sut) {
        _sut = [ZMMessageTranscoder systemMessageTranscoderWithManagedObjectContext:self.syncMOC
                                                        localNotificationDispatcher:self.notificationDispatcher];
    }
    return _sut;
}

- (void)tearDown
{
    [[self.mockExpirationTimer expect] tearDown];
    [self.sut tearDown];
    self.mockExpirationTimer = nil;
    self.sut = nil;
    self.upstreamObjectSync = nil;
    [super tearDown];
}

- (void)setupSelfConversation
{
    self.selfUser = [ZMUser selfUserInContext:self.uiMOC];
    self.selfUser.remoteIdentifier = [NSUUID createUUID];
    ZMConversation *selfConversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    selfConversation.remoteIdentifier = self.selfUser.remoteIdentifier;
    selfConversation.conversationType = ZMConversationTypeSelf;
    [self.uiMOC saveOrRollback];
}

- (ZMConversation *)insertGroupConversationInMoc:(NSManagedObjectContext *)moc
{
    ZMUser *user1 = [ZMUser insertNewObjectInManagedObjectContext:moc];
    user1.remoteIdentifier = [NSUUID createUUID];
    self.user1 = user1;
    
    ZMUser *user2 = [ZMUser insertNewObjectInManagedObjectContext:moc];
    user2.remoteIdentifier = [NSUUID createUUID];
    
    ZMUser *user3 = [ZMUser insertNewObjectInManagedObjectContext:moc];
    user3.remoteIdentifier = [NSUUID createUUID];
    
    ZMConversation *conversation = [ZMConversation insertGroupConversationIntoManagedObjectContext:moc withParticipants:@[user1, user2, user3]];
    conversation.remoteIdentifier = [NSUUID createUUID];
    return conversation;
}

- (ZMConversation *)insertGroupConversation
{
    ZMConversation *result = [self insertGroupConversationInMoc:self.syncMOC];
    XCTAssertTrue([self.syncMOC saveOrRollback]);
    return result;
}


- (void)testThatItIsCreatedWithSlowSyncComplete
{
    XCTAssertTrue(self.sut.isSlowSyncDone);
}

- (void)testThatItDoesNotNeedsSlowSyncEvenAfterSetNeedsSlowSync
{
    // when
    [self.sut setNeedsSlowSync];
    
    // then
    XCTAssertTrue(self.sut.isSlowSyncDone);
}



@end

