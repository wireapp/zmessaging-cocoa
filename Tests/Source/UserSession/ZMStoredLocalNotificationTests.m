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
@import ZMCDataModel;

#import "MessagingTest.h"
#import "ZMLocalNotification.h"
#import "ZMStoredLocalNotification.h"
#import "ZMUserSession+UserNotificationCategories.h"
#import <zmessaging/zmessaging-Swift.h>
#import "zmessaging_iOS_Tests-Swift.h"

@interface ZMStoredLocalNotificationTests : MessagingTest
@property (nonatomic) ZMConversation *conversation;
@property (nonatomic) ZMUser *sender;
@end

@implementation ZMStoredLocalNotificationTests

- (void)setUp {
    [super setUp];

    self.sender = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    self.sender.remoteIdentifier = NSUUID.createUUID;
    
    self.conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    self.conversation.remoteIdentifier = NSUUID.createUUID;
    
    [self.uiMOC saveOrRollback];
    
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (NSDictionary *)pushPayloadForEventPayload:(NSDictionary *)eventPayload
{
    return @{
             @"aps": @{@"content-available": @1},
             @"data": @{@"data":  eventPayload}
             };
}

- (NSDictionary *)oldStyleAlertPushPayload
{
    return @{
             @"aps": @{@"content-available": @1,
                       @"alert": @{@"foo": @"bar"},
                       @"conversation_id": self.conversation.remoteIdentifier.transportString,
                       @"msg_type": @"conversation.message-add",
                       },
             @"data" : @{},
             };
}

- (NSDictionary *)newStyleAlertPushPayloadForEventPayload:(NSDictionary *)eventPayload
{
    return @{
             @"aps": @{@"content-available": @1,
                       @"alert": @{@"foo": @"bar"}
                       },
             @"data": @{@"data": eventPayload
                        }
             };
}


- (NSDictionary *)dataPayLoadForMessageAddEvent
{
    return @{
             @"id": [[NSUUID createUUID] transportString],
             @"payload": @[@{
                     @"conversation": [self.conversation.remoteIdentifier transportString],
                     @"time": [NSDate date],
                     @"data": @{
                             @"content": @"saf",
                             @"nonce": [[NSUUID createUUID] transportString],
                             },
                     @"from": [self.sender.remoteIdentifier transportString],
                     @"type": @"conversation.message-add"
                     }]
             };
}

- (void)testThatItCreatesAStoredLocalNotificationFromALocalNotification
{
    // given
    NSDictionary *eventPayload = [self dataPayLoadForMessageAddEvent];
    NSArray *events = [ZMUpdateEvent eventsArrayFromPushChannelData:eventPayload];
    NSString *textInput = @"Text";
    ZMLocalNotificationForEvent *note = [[ZMLocalNotificationForEvent alloc] initWithEvents:@[events.firstObject] conversation:self.conversation managedObjectContext:self.uiMOC application:nil];
    XCTAssertNotNil(note);
    
    // when
    ZMStoredLocalNotification *storedNote = [[ZMStoredLocalNotification alloc] initWithNotification:note.uiNotifications.firstObject managedObjectContext:self.uiMOC actionIdentifier:nil textInput:textInput];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(storedNote.conversation, self.conversation);
    XCTAssertEqualObjects(storedNote.senderUUID, self.sender.remoteIdentifier);
    XCTAssertEqualObjects(storedNote.category, ZMConversationCategory);
    XCTAssertEqualObjects(storedNote.textInput, textInput);
}

@end
