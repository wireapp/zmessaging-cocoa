//
// Wire
// Copyright (C) 2017 Wire Swiss GmbH
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

#import <XCTest/XCTest.h>

@import WireTesting;

@class SessionManager;
@class ZMTransportSession;
@class MockTransportSession;
@class ApplicationMock;
@class ZMUserSession;
@class AVSMediaManager;
@class ZMAPNSEnvironment;
@class UnauthenticatedSession;
@class MockUser;
@class MockConversation;
@class MockConnection;

@interface IntegrationTest : ZMTBaseTest

@property (nonatomic, nullable) SessionManager *sessionManager;
@property (nonatomic, nullable) MockTransportSession *mockTransportSession;
@property (nonatomic, readonly, nullable) ZMTransportSession *transportSession;
@property (nonatomic, nullable) AVSMediaManager *mediaManager;
@property (nonatomic, nullable) ZMAPNSEnvironment *apnsEnvironment;
@property (nonatomic, nullable) ApplicationMock *application;
@property (nonatomic, nullable) ZMUserSession *userSession;
@property (nonatomic, nullable) UnauthenticatedSession *unauthenticatedSession;
@property (nonatomic, readonly) BOOL useInMemoryStore;
@property (nonatomic, readonly) BOOL useRealKeychain;

@property (nonatomic, nullable) MockUser *selfUser;
@property (nonatomic, nullable) MockConversation *selfConversation;
@property (nonatomic, nullable) MockUser *user1; // connected, with profile picture
@property (nonatomic, nullable) MockUser *user2; // connected
@property (nonatomic, nullable) MockUser *user3; // not connected, with profile picture, in a common group conversation
@property (nonatomic, nullable) MockUser *user4; // not connected, with profile picture, no shared conversations
@property (nonatomic, nullable) MockUser *user5; // not connected, no shared conversation
@property (nonatomic, nullable) MockConversation *selfToUser1Conversation;
@property (nonatomic, nullable) MockConversation *selfToUser2Conversation;
@property (nonatomic, nullable) MockConversation *groupConversation;
@property (nonatomic, nullable) MockConnection *connectionSelfToUser1;
@property (nonatomic, nullable) MockConnection *connectionSelfToUser2;

@end
