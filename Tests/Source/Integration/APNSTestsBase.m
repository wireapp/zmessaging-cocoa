//
// Wire
// Copyright (C) 2020 Wire Swiss GmbH
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

@import WireMockTransport;

#import "IntegrationTest.h"
#import "WireSyncEngine_iOS_Tests-Swift.h"
#import "APNSTestsBase.h"

@implementation APNSTestsBase

- (void)setUp
{
    [super setUp];
    
    [self createSelfUserAndConversation];
    [self createExtraUsersAndConversations];
}

- (void)closePushChannelAndWaitUntilClosed
{
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        session.pushChannel.keepOpen = NO;
        [session simulatePushChannelClosed];
    }];
    WaitForAllGroupsToBeEmpty(0.2);
}

- (NSDictionary *)noticePayloadForLastEvent
{
    ZMUpdateEvent *lastEvent = self.mockTransportSession.updateEvents.lastObject;
    return [self noticePayloadWithIdentifier:lastEvent.uuid];
}

- (NSDictionary *)noticePayloadWithIdentifier:(NSUUID *)uuid
{
    return @{
             @"aps" : @{},
             @"data" : @{
                     @"data" : @{ @"id" : uuid.transportString },
                     @"type" : @"notice"
                     }
             };
}

@end