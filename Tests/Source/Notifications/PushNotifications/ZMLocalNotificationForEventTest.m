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

#import "ZMLocalNotificationForEventTest.h"
#import "UILocalNotification+UserInfo.h"
#import <WireSyncEngine/WireSyncEngine-Swift.h>
#import "WireSyncEngine_iOS_Tests-Swift.h"

@implementation ZMLocalNotificationForEventTest

- (void)setUp {
    [super setUp];
    
    self.sender = [self insertUserWithRemoteID:[NSUUID createUUID] name:@"Super User"];
    
    self.otherUser = [self insertUserWithRemoteID:[NSUUID createUUID] name:@"Other User"];
    
    self.otherUser2 = [self insertUserWithRemoteID:[NSUUID createUUID] name:@"Other User2"];

    self.oneOnOneConversation = [self insertConversationWithRemoteID:[NSUUID createUUID] name:@"Super Conversation" type:ZMConversationTypeOneOnOne isSilenced:NO];
    
    self.groupConversation = [self insertConversationWithRemoteID:[NSUUID createUUID] name:@"Super Conversation" type:ZMConversationTypeGroup isSilenced:NO];
    
    self.groupConversationWithoutName = [self insertConversationWithRemoteID:[NSUUID createUUID] name:nil type:ZMConversationTypeGroup isSilenced:NO];
    
    [self.syncMOC performGroupedBlockAndWait:^{
        self.selfUser = [ZMUser selfUserInContext:self.syncMOC];
        self.selfUser.remoteIdentifier = [NSUUID createUUID];
        [self.syncMOC saveOrRollback];
    }];
}

- (void)tearDown {
    self.sender = nil;
    self.otherUser = nil;
    self.oneOnOneConversation = nil;
    self.groupConversation =  nil;
    self.groupConversationWithoutName =  nil;
    self.selfUser.remoteIdentifier = nil;
    [super tearDown];
}


- (ZMConversation *)insertConversationWithRemoteID:(NSUUID *)uuid name:(NSString *)userDefinedName type:(ZMConversationType)type isSilenced:(BOOL)isSilenced
{
    __block ZMConversation *conversation;
    
    [self.syncMOC performGroupedBlockAndWait:^{
        conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.remoteIdentifier = uuid;
        conversation.userDefinedName = userDefinedName;
        conversation.conversationType = type;
        conversation.isSilenced = isSilenced;
        conversation.lastServerTimeStamp = [NSDate date];
        conversation.lastReadServerTimeStamp = conversation.lastServerTimeStamp;
        [conversation.mutableOtherActiveParticipants addObjectsFromArray:@[self.sender, self.otherUser]];
        [self.syncMOC saveOrRollback];
    }];
    
    return conversation;
}

- (ZMUser *)insertUserWithRemoteID:(NSUUID *)uuid name:(NSString *)name
{
    __block ZMUser *user;
    [self.syncMOC performGroupedBlockAndWait:^{
        user = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user.name = name;
        user.remoteIdentifier = uuid;
        
        [self.syncMOC saveOrRollback];
    }];
    
    return user;
}

- (ZMLocalNotificationForEvent *)noteWithPayload:(NSDictionary *)data fromUserID:(NSUUID *)fromUserID inConversation:(ZMConversation *)conversation type:(NSString *)type application:(id<ZMApplication>)application
{
    __block ZMLocalNotificationForEvent *note;
    [self.syncMOC performGroupedBlockAndWait:^{
        NSDictionary *payload = [self payloadForEventInConversation:conversation type:type data:data fromUserID:fromUserID];
        ZMUpdateEvent *event = [ZMUpdateEvent eventFromEventStreamPayload:payload uuid:nil];
        note = [ZMLocalNotificationForEvent notificationForEvent:event conversation:conversation managedObjectContext:self.syncMOC application:application];
    }];
    
    return note;
}

- (ZMLocalNotificationForEvent *)noteWithPayload:(NSDictionary *)data fromUser:(ZMUser *)fromUser inConversation:(ZMConversation *)conversation type:(NSString *)type
{
    return [self noteWithPayload:data
                      fromUserID:fromUser.remoteIdentifier
                  inConversation:conversation
                            type:type
                     application:self.application];
}

- (NSMutableDictionary *)payloadForEventInConversation:(ZMConversation *)conversation type:(NSString *)type data:(NSDictionary *)data fromUserID:(NSUUID *)fromUserID;
{
    NSUUID *userRemoteID = fromUserID ?: [NSUUID createUUID];
    NSUUID *convRemoteID = conversation.remoteIdentifier ?: [NSUUID createUUID];
    data = data ?: @{};
    NSDate *serverTimeStamp = conversation ? [conversation.lastServerTimeStamp dateByAddingTimeInterval:5] : [NSDate date];
    
    return [@{
              @"conversation" : convRemoteID.transportString,
              @"data" : data,
              @"from" : userRemoteID.transportString,
              @"type" : type,
              @"time" : serverTimeStamp.transportString
              } mutableCopy];
}

@end


@implementation ZMLocalNotificationForEventTest (Connection)

- (NSDictionary *)payloadForConnectionRequestTo:(NSUUID *)toRemoteID status:(NSString *)status
{
    return @{@"connection": @{@"conversation" : [self.oneOnOneConversation.remoteIdentifier transportString],
                              @"message" : @"Please add me",
                              @"from" : NSUUID.createUUID.transportString,
                              @"status" : status,
                              @"to": toRemoteID.transportString},
             @"type": @"user.connection",
             @"user" : @{@"name": @"Special User"}};
}

- (ZMLocalNotificationForEvent *)zmNoteForConnectionRequestEventTo:(ZMUser *)toUser status:(NSString *)status
{
    
    NSUUID *remoteID = toUser.remoteIdentifier ?: NSUUID.createUUID;
    __block ZMLocalNotificationForEvent *note;
    
    NSDictionary *payload = [self payloadForConnectionRequestTo:remoteID status:status];
    
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMUpdateEvent *event = [ZMUpdateEvent eventFromEventStreamPayload:payload uuid:nil];
        note = [ZMLocalNotificationForEvent notificationForEvent:event conversation:self.oneOnOneConversation managedObjectContext:self.syncMOC application:self.application];
    }];
    
    return note;
}

- (UILocalNotification *)noteForConnectionRequestEventTo:(ZMUser *)toUser status:(NSString *)status
{
    ZMLocalNotificationForEvent *note = [self zmNoteForConnectionRequestEventTo:toUser status:status];
    
    XCTAssertNotNil(note);
    XCTAssertNotNil(note.conversationID);
    XCTAssertEqualObjects(self.oneOnOneConversation.remoteIdentifier, note.conversationID);
    
    XCTAssertNotNil(note.uiNotifications);
    UILocalNotification *notification = note.uiNotifications.lastObject;
    return notification;
}


- (void)testThatItCreatesNewConnectionNotification
{
    // given
    NSUUID *senderUUID = [NSUUID createUUID];
    NSDictionary *payload = @{
                              @"user" : @{@"id": senderUUID.transportString,
                                          @"name": @"Bernd"},
                              @"type" : EventNewConnection,
                              @"time" : [NSDate date].transportString
                              };
    ZMUpdateEvent *event = [ZMUpdateEvent eventFromEventStreamPayload:payload uuid:nil];

    // when
    __block ZMLocalNotificationForEvent *note;
    [self.syncMOC performGroupedBlockAndWait:^{
        note = [ZMLocalNotificationForEvent notificationForEvent:event conversation:self.oneOnOneConversation managedObjectContext:self.syncMOC application:self.application];
        XCTAssertNotNil(note);
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertNotNil(note);
    UILocalNotification *notif = note.uiNotifications.lastObject;
    XCTAssertEqualObjects(notif.alertBody, @"Bernd just joined Wire");
    XCTAssertEqualObjects(notif.zm_senderUUID, senderUUID);
}

- (void)testThatItCreatesConnectionRequestNotificationsCorrectly
{
    //    "push.notification.connection.request" = "%@ wants to connect";
    //    "push.notification.connection.request.nousername" = "Someone wants to connect";
    //
    //    "push.notification.connection.accepted" = "%@ accepted your connection request";
    //    "push.notification.connection.accepted.nousername" = "Your connection request was accepted";
    
    NSString *accepted = @"accepted";
    NSString *pending = @"pending";
    
    NSDictionary *cases = @{@"You and Super User are now connected": @[self.sender, accepted],
                            @"You and Special User are now connected": @[accepted],
                            @"Super User wants to connect": @[self.sender, pending],
                            @"Special User wants to connect": @[pending]};
    
    [cases enumerateKeysAndObjectsUsingBlock:^(NSString *expectedAlert, NSArray *arguments, BOOL *stop) {
        NOT_USED(stop);
        UILocalNotification *notification;
        if (arguments.count == 2) {
            notification = [self noteForConnectionRequestEventTo:arguments[0] status:arguments[1]];
        } else {
            notification = [self noteForConnectionRequestEventTo:nil status:arguments[0]];
        }
        XCTAssertNotNil(notification);
        XCTAssertEqualObjects(notification.alertBody, expectedAlert);
    }];
}

- (void)testThatItDoesNotCreateAConnectionAcceptedNotificationForAWrongStatus
{
    // given
    NSString *status = @"blablabla";
    
    // when
    ZMLocalNotificationForEvent *note = [self zmNoteForConnectionRequestEventTo:nil status:status];
    // then

    XCTAssertNil(note);
}

- (NSDictionary *)payloadForEncryptedOTRMessageWithText:(NSString *)text nonce:(NSUUID *)nonce
{
    ZMGenericMessage *message = [ZMGenericMessage messageWithText:text nonce:nonce.transportString expiresAfter:nil];
    NSString *base64EncodedString = message.data.base64String;
    return @{@"data": @{ @"text": base64EncodedString},
             @"conversation" : self.oneOnOneConversation.remoteIdentifier.transportString,
             @"type": EventConversationAddOTRMessage,
             @"from": self.sender.remoteIdentifier.transportString,
             @"time": [NSDate date].transportString
             };
}

@end


@implementation ZMLocalNotificationForEventTest (ConversationCreate)

- (void)testThatItCreatesConversationCreateNotification
{
    // "push.notification.conversation.create" = "%1$@ created a group conversation with you";
    
    // when
    ZMLocalNotificationForEvent *note1 = [self noteWithPayload:nil fromUser:self.sender inConversation:self.groupConversation type:EventConversationCreate];
    
    // then
    NSString *expectedAlertText = @"Super User created a group conversation with you";
    
    XCTAssertNotNil(note1);
    
    XCTAssertNotNil(note1.uiNotifications);
    UILocalNotification *notification = note1.uiNotifications.lastObject;
    XCTAssertEqualObjects(notification.alertBody, expectedAlertText);
}

- (void)testThatItCreatesConversationCreateNotification_NoUserName
{
    // "push.notification.conversation.create.nousername" = "Someone created a group conversation with you";
    
    
    // when
    ZMLocalNotificationForEvent *note1 = [self noteWithPayload:nil fromUser:nil inConversation:self.groupConversation type:EventConversationCreate];
    
    // then
    NSString *expectedAlertText = @"Someone created a group conversation with you";
    XCTAssertNotNil(note1);
        XCTAssertNotNil(note1.uiNotifications);
    UILocalNotification *notification = note1.uiNotifications.lastObject;
    XCTAssertEqualObjects(notification.alertBody, expectedAlertText);
}

@end

