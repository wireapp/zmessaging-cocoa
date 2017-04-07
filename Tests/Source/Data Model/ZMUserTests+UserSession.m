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


@import WireTesting;
@import WireDataModel;

#import "MessagingTest.h"
#import "ZMBareUser+UserSession.h"
#import "ZMUserSession+Internal.h"

static NSString * const InvitationToConnectBaseURL = @"https://www.wire.com/c/";

@interface ZMUserTests_UserSession : MessagingTest

@end

@implementation ZMUserTests_UserSession

- (void)setUp {
    [super setUp];
    
    self.syncMOC.zm_userImageCache = [[UserImageLocalCache alloc] initWithLocation:nil];
    self.uiMOC.zm_userImageCache = self.syncMOC.zm_userImageCache;

}

- (void)testThatItRequestsTheMediumImageDataOnDemand
{
    // given
    NSUUID *uuid = [NSUUID createUUID];
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.remoteIdentifier = uuid;

    id mockRequestAvailableNotification = [OCMockObject mockForClass:ZMRequestAvailableNotification.class];
    [[mockRequestAvailableNotification expect] notifyNewRequestsAvailable:OCMOCK_ANY];

    // when
    [user requestMediumProfileImageInUserSession:nil];

    // then
    [mockRequestAvailableNotification verify];
}

- (void)testThatTheCommonContactsSearchIsForwardedToTheUserSession
{
    // given
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.remoteIdentifier = [NSUUID createUUID];

    id token = [OCMockObject mockForProtocol:@protocol(ZMCommonContactsSearchToken)];
    id session = [OCMockObject mockForClass:ZMUserSession.class];
    id delegate = [OCMockObject mockForProtocol:@protocol(ZMCommonContactsSearchDelegate)];

    // expect
    [[[session expect] andReturn:token] searchCommonContactsWithUserID:user.remoteIdentifier searchDelegate:delegate];

    // when
    [user searchCommonContactsInUserSession:session withDelegate:delegate];

    // then
    [session verify];
    [delegate verify];
    [token verify];

}

@end
