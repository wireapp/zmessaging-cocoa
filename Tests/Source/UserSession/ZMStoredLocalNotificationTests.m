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


@import WireTransport;
@import WireDataModel;

#import "MessagingTest.h"
#import "ZMLocalNotification.h"
#import "ZMStoredLocalNotification.h"
#import "ZMUserSession+UserNotificationCategories.h"
#import "WireSyncEngine_iOS_Tests-Swift.h"

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
}

- (NSDictionary *)pushPayloadForEventPayload:(NSDictionary *)eventPayload
{
    return @{
             @"aps": @{@"content-available": @1},
             @"data": @{@"data":  eventPayload}
             };
}

- (void)testThatItCreatesAStoredLocalNotificationFromALocalNotification
{
    // given
    NSString *textInput = @"Foobar";
    ZMClientMessage *message = [ZMClientMessage insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMGenericMessage *genericMessage = [ZMGenericMessage messageWithText:textInput nonce:[NSUUID createUUID].transportString expiresAfter:nil];
    [message addData:genericMessage.data];
    message.sender = self.sender;
    message.visibleInConversation = self.conversation;
    [self.uiMOC saveOrRollback];
    ZMLocalNotificationForMessage *note = [[ZMLocalNotificationForMessage alloc] initWithMessage:message application:self.application];
    XCTAssertNotNil(note);
    
    // when
    ZMStoredLocalNotification *storedNote = [[ZMStoredLocalNotification alloc] initWithNotification:note.uiNotifications.firstObject managedObjectContext:self.uiMOC actionIdentifier:nil textInput:textInput];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(storedNote.conversation, self.conversation);
    XCTAssertEqualObjects(storedNote.senderUUID, self.sender.remoteIdentifier);
    XCTAssertEqualObjects(storedNote.category, ZMConversationCategoryIncludingLike);
    XCTAssertEqualObjects(storedNote.textInput, textInput);
}

@end
