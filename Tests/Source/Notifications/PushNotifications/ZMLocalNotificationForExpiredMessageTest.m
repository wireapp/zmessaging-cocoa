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

@import WireDataModel;

#import "MessagingTest.h"
#import "ZMLocalNotification.h"

@interface ZMLocalNotificationForExpiredMessageTest : MessagingTest
@property (nonatomic) ZMUser *userWithNoName;
@property (nonatomic) ZMUser *userWithName;
@property (nonatomic) ZMConversation *oneOnOneConversation;

@property (nonatomic) ZMConversation *groupConversation;
@property (nonatomic) ZMConversation *groupConversationWithoutName;
@end

@implementation ZMLocalNotificationForExpiredMessageTest

- (void)setUp {
    [super setUp];

    [self.syncMOC performGroupedBlockAndWait:^{
        self.userWithName = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        self.userWithName.name = @"Karl";
        
        self.userWithNoName = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        
        self.groupConversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        self.groupConversation.userDefinedName = @"This is a group conversation";
        self.groupConversation.conversationType = ZMConversationTypeGroup;
        self.groupConversation.remoteIdentifier = [NSUUID createUUID];

        self.groupConversationWithoutName = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        self.groupConversationWithoutName.conversationType = ZMConversationTypeGroup;
        self.groupConversationWithoutName.remoteIdentifier = [NSUUID createUUID];

        self.oneOnOneConversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        self.oneOnOneConversation.remoteIdentifier = [NSUUID createUUID];
        self.oneOnOneConversation.conversationType = ZMConversationTypeOneOnOne;
        
        [self.syncMOC saveOrRollback];
    }];
}

- (void)tearDown {

    self.userWithNoName = nil;
    self.userWithName = nil;
    self.groupConversation = nil;
    self.groupConversationWithoutName = nil;
    self.oneOnOneConversation = nil;
    
    [super tearDown];
}

- (void)testThatItSetsTheConversationOnTheNotification
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        ZMMessage *message = [ZMMessage insertNewObjectInManagedObjectContext:self.syncMOC];
        [self.oneOnOneConversation.mutableMessages addObject:message];
        
        // when
        ZMLocalNotificationForExpiredMessage *note = [[ZMLocalNotificationForExpiredMessage alloc] initWithExpiredMessage:message];
        
        // then
        ZMConversation *conversation = [note.uiNotification conversationInManagedObjectContext:message.managedObjectContext];
        XCTAssertEqualObjects(conversation, self.oneOnOneConversation);

    }];
}

- (void)testThatItSetsTheConversationOnTheNotification_InitWithConversation
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        ZMMessage *message = [ZMMessage insertNewObjectInManagedObjectContext:self.syncMOC];
        [self.oneOnOneConversation.mutableMessages addObject:message];
        
        // when
        ZMLocalNotificationForExpiredMessage *note = [[ZMLocalNotificationForExpiredMessage alloc] initWithConversation:message.conversation];
        
        // then
        ZMConversation *conversation = [note.uiNotification conversationInManagedObjectContext:message.managedObjectContext];
        XCTAssertEqualObjects(conversation, self.oneOnOneConversation);
    }];
}

- (void)testThatItCreatesANotificationWithTheRightTextForFailedMessageInGroupConversation {

    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        ZMMessage *message = [ZMTextMessage insertNewObjectInManagedObjectContext:self.syncMOC];
        [self.groupConversation.mutableMessages addObject:message];
        
        // when
        ZMLocalNotificationForExpiredMessage *note = [[ZMLocalNotificationForExpiredMessage alloc] initWithExpiredMessage:message];

        // then
        XCTAssertNotNil(note);
        XCTAssertEqual(note.message, message);
        UILocalNotification *uiNote = note.uiNotification;
        
        NSString *expectedText = [NSString stringWithFormat:@"Unable to send a message in %@", self.groupConversation.userDefinedName];
        XCTAssertEqualObjects(uiNote.alertBody, expectedText);
    }];
    
}


- (void)testThatItCreatesANotificationWithTheRightTextForFailedMessageInGroupConversation_NoConversationName
{
    
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        ZMMessage *message = [ZMTextMessage insertNewObjectInManagedObjectContext:self.syncMOC];
        [self.groupConversationWithoutName.mutableMessages addObject:message];
        
        // when
        ZMLocalNotificationForExpiredMessage *note = [[ZMLocalNotificationForExpiredMessage alloc] initWithExpiredMessage:message];
        
        // then
        XCTAssertNotNil(note);
        XCTAssertEqual(note.message, message);
        UILocalNotification *uiNote = note.uiNotification ;
        
        NSString *expectedText = @"Unable to send a message";
        XCTAssertEqualObjects(uiNote.alertBody, expectedText);
    }];
    
}


- (void)testThatItCreatesANotificationWithTheRightTextForFailedMessageInOneOnOneConversation
{
    
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        ZMMessage *message = [ZMTextMessage insertNewObjectInManagedObjectContext:self.syncMOC];
        [self.oneOnOneConversation.mutableMessages addObject:message];
        ZMConnection *connection = [ZMConnection insertNewObjectInManagedObjectContext:self.syncMOC];
        connection.conversation = self.oneOnOneConversation;
        connection.to = self.userWithName;
        
        // when
        ZMLocalNotificationForExpiredMessage *note = [[ZMLocalNotificationForExpiredMessage alloc] initWithExpiredMessage:message];
        
        // then
        XCTAssertNotNil(note);
        XCTAssertEqual(note.message, message);
        UILocalNotification *uiNote = note.uiNotification ;
        
        NSString *expectedText = [NSString stringWithFormat:@"Unable to send a message to %@", self.userWithName.name];
        XCTAssertEqualObjects(uiNote.alertBody, expectedText);
    }];
    
}

- (void)testThatItCreatesANotificationWithTheRightTextForFailedMessageInOneOnOneConversation_NoUserName
{
    
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // given
        ZMMessage *message = [ZMTextMessage insertNewObjectInManagedObjectContext:self.syncMOC];
        [self.oneOnOneConversation.mutableMessages addObject:message];
        ZMConnection *connection = [ZMConnection insertNewObjectInManagedObjectContext:self.syncMOC];
        connection.conversation = self.oneOnOneConversation;
        connection.to = self.userWithNoName;
        
        // when
        ZMLocalNotificationForExpiredMessage *note = [[ZMLocalNotificationForExpiredMessage alloc] initWithExpiredMessage:message];
        
        // then
        XCTAssertNotNil(note);
        XCTAssertEqual(note.message, message);
        UILocalNotification *uiNote = note.uiNotification ;
        
        NSString *expectedText = @"Unable to send a message";
        XCTAssertEqualObjects(uiNote.alertBody, expectedText);
    }];
    
}

@end
