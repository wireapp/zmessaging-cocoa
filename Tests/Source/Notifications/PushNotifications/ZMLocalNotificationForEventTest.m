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


@import ZMTesting;

#import "ZMLocalNotificationForEventTest.h"
#import "UILocalNotification+UserInfo.h"
#import <zmessaging/zmessaging-Swift.h>

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

- (ZMLocalNotificationForEvent *)notificationForType:(NSString *)type
                              inConversation:(ZMConversation *)conversation
                                    fromUser:(ZMUser *)fromUser
                                unreadCrount:(NSUInteger)unreadCount
                                 application:(id)application;
{
    NSDictionary *data = @{@"content": @"Hello Hello!"};
    
    NSMutableArray *events = [NSMutableArray array];
    for (NSUInteger i = 0; i < unreadCount; i++) {
        NSDictionary *payload = [self payloadForMessageInConversation:conversation type:type data:data fromUserID:fromUser.remoteIdentifier];
        ZMUpdateEvent *event = [ZMUpdateEvent eventFromEventStreamPayload:payload uuid:nil];
        [events addObject:event];
    }
    conversation.internalEstimatedUnreadCount = [@(unreadCount) integerValue];
    
    if ([type isEqualToString:EventConversationAdd] || [type isEqualToString:EventConversationAddAsset]){
        return [[ZMLocalNotificationForMessage alloc] initWithEvents:events conversation:conversation managedObjectContext:self.syncMOC application:application copyFromNote:nil];
    }
    return nil;
}

- (ZMLocalNotificationForEvent *)noteWithPayload:(NSDictionary *)data fromUserID:(NSUUID *)fromUserID inConversation:(ZMConversation *)conversation type:(NSString *)type application:(UIApplication *)application
{
    __block ZMLocalNotificationForEvent *note;
    [self.syncMOC performGroupedBlockAndWait:^{
        NSDictionary *payload = [self payloadForMessageInConversation:conversation type:type data:data fromUserID:fromUserID];
        ZMUpdateEvent *event = [ZMUpdateEvent eventFromEventStreamPayload:payload uuid:nil];
        note = [ZMLocalNotificationForEvent notificationForEvent:event managedObjectContext:self.syncMOC application:application];
    }];
    
    return note;
}

- (ZMLocalNotificationForEvent *)noteWithPayload:(NSDictionary *)data fromUser:(ZMUser *)fromUser inConversation:(ZMConversation *)conversation type:(NSString *)type
{
    return [self noteWithPayload:data
                      fromUserID:fromUser.remoteIdentifier
                  inConversation:conversation
                            type:type
                     application:nil];
}

- (ZMLocalNotificationForEvent *)copyNote:(ZMLocalNotificationForEvent*)note withPayload:(NSDictionary *)data fromUser:(ZMUser *)fromUser inConversation:(ZMConversation *)conversation type:(NSString *)type
{
    __block ZMLocalNotificationForEvent *note2;
    [self.syncMOC performGroupedBlockAndWait:^{
        NSUUID *senderID = fromUser.remoteIdentifier;
        if (senderID == nil) {
            senderID = [note.uiNotifications.lastObject zm_senderUUID];
        }
        NSDictionary *payload = [self payloadForMessageInConversation:conversation type:type data:data fromUserID:senderID];
        ZMUpdateEvent *event = [ZMUpdateEvent eventFromEventStreamPayload:payload uuid:nil];
        note2 = [note copyByAddingEvent:event];
    }];
    
    return note2;
}

- (NSMutableDictionary *)payloadForMessageInConversation:(ZMConversation *)conversation type:(NSString *)type data:(NSDictionary *)data fromUserID:(NSUUID *)fromUserID;
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

- (NSString *)objectURLStringForObject:(NSManagedObject *)object
{
    NSError *error = nil;
    if (object.objectID.isTemporaryID) {
        if (! [self.uiMOC obtainPermanentIDsForObjects:@[object] error:&error]) {
            return nil;
        }
    }
    
    return [[object.objectID URIRepresentation] absoluteString];
}

@end

@implementation ZMLocalNotificationForEventTest (General)

- (ZMLocalNotificationForEvent *)zmNotificationForMessageAddEventFromUser:(ZMUser *)sender inConversation:(ZMConversation *)conversation
{
    NSString *text = @"Hello Hello!";
    NSString *nonceString = NSUUID.createUUID.transportString;

    NSDictionary *data = @{@"content": text, ZMLocalNotificationUserInfoNonceKey: nonceString};
    
    ZMLocalNotificationForEvent *note = [self noteWithPayload:data fromUser:sender inConversation:conversation type:EventConversationAdd];
    
    return note;
}

- (void)testThatItSavesTheSenderOfANotification
{
    // given
    ZMUser *sender =  self.sender;
    
    // when
    ZMLocalNotificationForEvent *note = [self zmNotificationForMessageAddEventFromUser:sender inConversation:self.oneOnOneConversation];
    
    // then
    XCTAssertNotNil(note);
    
    XCTAssertNotNil(note.sender);
    XCTAssertEqualObjects(sender, note.sender);
}

- (void)testThatItSetsTheConversationOnTheNotification
{
    // given
    ZMUser *sender =  self.sender;
    
    // when
    ZMLocalNotificationForEvent *note = [self zmNotificationForMessageAddEventFromUser:sender inConversation:self.oneOnOneConversation];
    
    // then
    ZMConversation *conversation = [note.uiNotifications.firstObject conversationInManagedObjectContext:self.oneOnOneConversation.managedObjectContext];
    XCTAssertEqual(conversation, self.oneOnOneConversation);
}

- (void)testThatItSavesTheConversationOfANotification
{
    // given
    ZMConversation *conversation =  self.oneOnOneConversation;
    
    // when
    ZMLocalNotificationForEvent *note = [self zmNotificationForMessageAddEventFromUser:self.sender inConversation:conversation];
    
    // then
    XCTAssertNotNil(note);
    
    XCTAssertNotNil(note.uiNotifications);
    
    XCTAssertNotNil(note.conversation);
    XCTAssertEqualObjects(conversation, note.conversation);
}

- (void)testThatItDoesNotCreateANotificationWhenTheConversationIsSilenced
{
    // given
    ZMConversation *conversation = [self insertConversationWithRemoteID:[NSUUID createUUID] name:@"Super Conversation" type:ZMConversationTypeOneOnOne isSilenced:YES];
    
    // when
    ZMLocalNotificationForEvent *note = [self zmNotificationForMessageAddEventFromUser:self.sender inConversation:conversation];
    
    // then
    XCTAssertNil(note);
}

- (void)testThatItDoesNotReturnANotificationWhenThereIsNoConversation
{
    // given
    ZMConversation *conversation =  nil;
    
    // when
    __block ZMLocalNotificationForEvent *note;
    [self performIgnoringZMLogError:^{
        note = [self zmNotificationForMessageAddEventFromUser:self.sender inConversation:conversation];
    }];
    
    // then
    XCTAssertNil(note);
}


- (void)testThatItStoresTheConversationObjectURLInTheUserInfo
{
    // given
    ZMLocalNotificationForEvent *note = [self zmNotificationForMessageAddEventFromUser:self.sender inConversation:self.oneOnOneConversation];

    // then
    XCTAssertNotNil(note);
    
    XCTAssertNotNil(note.uiNotifications);
    UILocalNotification *notification = note.uiNotifications.lastObject;
    
    XCTAssertEqualObjects(notification.zm_conversationRemoteID, self.oneOnOneConversation.remoteIdentifier);
    
}


- (void)testThatItStoresTheNonceStringInTheUserInfo
{
    // given
    NSUUID *nonce = NSUUID.createUUID;
    NSString *text = @"Hello Hello!";
    NSDictionary *data = @{@"content": text,
                           ZMLocalNotificationUserInfoNonceKey: nonce.transportString};
    
    // when
    ZMLocalNotificationForEvent *note = [self noteWithPayload:data fromUser:self.sender inConversation:self.oneOnOneConversation type:EventConversationAdd];
    
    // then
    XCTAssertNotNil(note);
    
    XCTAssertNotNil(note.uiNotifications);
    UILocalNotification *notification = note.uiNotifications.lastObject;
    
    XCTAssertEqualObjects(notification.zm_messageNonce, nonce);
}

- (void)testThatItStoresTheSenderUUUIDStringInTheUserInfo
{
    // given
    NSString *nonceString = NSUUID.createUUID.transportString;
    NSString *text = @"Hello Hello!";
    NSDictionary *data = @{@"content": text,
                           ZMLocalNotificationUserInfoNonceKey: nonceString};
    
    // when
    ZMLocalNotificationForEvent *note = [self noteWithPayload:data fromUser:self.sender inConversation:self.oneOnOneConversation type:EventConversationAdd];
    
    // then
    XCTAssertNotNil(note);
    
    XCTAssertNotNil(note.uiNotifications);
    UILocalNotification *notification = note.uiNotifications.lastObject;
    
    XCTAssertEqualObjects(notification.zm_senderUUID, self.sender.remoteIdentifier);
}

@end


@implementation ZMLocalNotificationForEventTest (MessageAddEvents)


- (UILocalNotification *)notificationForMessageAddEventFromUser:(ZMUser *)sender inConversation:(ZMConversation *)conversation
{
    ZMLocalNotificationForEvent *note = [self zmNotificationForMessageAddEventFromUser:sender inConversation:conversation];
    XCTAssertNotNil(note);
    
    XCTAssertEqualObjects(conversation, note.conversation);
    if (sender != nil) {
        XCTAssertEqualObjects(sender, note.sender);
    } else {
        XCTAssertNil(note.sender);
    }
    
    XCTAssertNotNil(note.uiNotifications);
    UILocalNotification *notification = note.uiNotifications.lastObject;
    return notification;
}

- (void)testItCreatesMessageAddNotificationsCorrectly
{
//    "push.notification.add.message.group" = "%1$@ in %2$@: %3$@";
//    "push.notification.add.message.group.nousername" = "New message in %1$@: %2$@";
//    "push.notification.add.message.group.nousername.noconversationname" = "New message: %1$@";
//    "push.notification.add.message.group.noconversationname" = "%1$@ in a conversation: %2$@";
//    
//    "push.notification.add.message.oneonone" = "%1$@: %2$@";
//    "push.notification.add.message.oneonone.nousername" = "New message: %1$@";

    NSDictionary *cases = @{@"Super User: Hello Hello!" : @[self.sender, self.oneOnOneConversation],
                            @"New message: Hello Hello!" : @[self.oneOnOneConversation],
                            
                            @"Super User in Super Conversation: Hello Hello!":  @[self.sender, self.groupConversation],
                            @"New message in Super Conversation: Hello Hello!": @[self.groupConversation],
                            @"New message: Hello Hello!": @[self.groupConversationWithoutName],
                            @"Super User in a conversation: Hello Hello!":  @[self.sender, self.groupConversationWithoutName],
                            };
    
    [cases enumerateKeysAndObjectsUsingBlock:^(NSString *expectedAlert, NSArray *arguments, BOOL *stop) {
        NOT_USED(stop);
        UILocalNotification *notification;
        if (arguments.count == 2) {
            notification = [self notificationForMessageAddEventFromUser:arguments[0] inConversation:arguments[1]];
        }
        else {
            notification = [self notificationForMessageAddEventFromUser:nil inConversation:arguments[0]];
        }
        XCTAssertNotNil(notification);
        XCTAssertEqualObjects(notification.alertBody, expectedAlert);
    }];

}

- (void)testThatItDoesNotCreateACopyStoringTheNotificationsInternalWhenTheUnreadCountIsSmallerThanFive_OneOnOne
{
    // given
    NSDictionary *data1 = @{@"content": @"Hello Hello!"};
    NSDictionary *data2 = @{@"content": @"Ahhhhh!"};

    NSUInteger unreadCount = 3;

    // when
    ZMLocalNotificationForEvent *note1 = [self noteWithPayload:data1 fromUser:self.sender inConversation:self.oneOnOneConversation type:EventConversationAdd];
    [self insertMessagesIntoConversation:self.oneOnOneConversation messageCount:unreadCount];

    ZMLocalNotificationForEvent *note2 = [self copyNote:note1 withPayload:data2 fromUser:self.sender inConversation:self.oneOnOneConversation type:EventConversationAdd];
    
    // then
    XCTAssertNil(note2);
}


- (void)testThatItDoesNotBundleTheNotificationsInternalWhenTheUnreadCountIsBiggerThanFive_Group
{
    // given
    NSDictionary *data2 = @{@"content": @"Ahhhhh!"};
    
    id mockApplication = [OCMockObject mockForClass:[UIApplication class]];
    ZMLocalNotificationForEvent *note1 = [self notificationForType:EventConversationAdd inConversation:self.groupConversation fromUser:self.sender unreadCrount:6 application:mockApplication];
    XCTAssertNotNil(note1);
    
    // expect
    [[mockApplication reject] cancelLocalNotification:note1.uiNotifications.firstObject];
    
    // when
    ZMLocalNotificationForEvent *note2 = [self copyNote:note1 withPayload:data2 fromUser:self.sender inConversation:self.groupConversation type:EventConversationAdd];
    
    // then
    XCTAssertNil(note2);
    [mockApplication verify];
}


- (void)insertMessagesIntoConversation:(ZMConversation *)conversation messageCount:(NSUInteger)messageCount
{
    for (NSUInteger idx = 0; idx < messageCount; idx++) {
        ZMMessage *message = [ZMMessage insertNewObjectInManagedObjectContext:self.syncMOC];
        message.serverTimestamp = [conversation.lastServerTimeStamp dateByAddingTimeInterval:5];
        [conversation resortMessagesWithUpdatedMessage:message];
        conversation.lastServerTimeStamp = message.serverTimestamp;
    }
}


- (void)testThatItDuplicatesPercentageSignsInTextAndConversationName
{
    NSDictionary *data = @{@"content": @"Today we grew by 100%"};
    
    ZMConversation *conversation = [self insertConversationWithRemoteID:[NSUUID createUUID] name:@"100% Wire" type:ZMConversationTypeGroup isSilenced:NO];
    
    // when
    ZMLocalNotificationForEvent *note = [self noteWithPayload:data fromUser:self.sender inConversation:conversation type:EventConversationAdd];
    
    // then
    XCTAssertNotNil(note);
    
    XCTAssertEqualObjects(conversation, note.conversation);
    XCTAssertNotNil(note.uiNotifications);
    UILocalNotification *notification = note.uiNotifications.lastObject;
    XCTAssertEqualObjects(notification.alertBody, @"Super User in 100%% Wire: Today we grew by 100%%");
}

@end




@implementation ZMLocalNotificationForEventTest (AssetAdd)

- (UILocalNotification *)notificationForImageAddEventFromUser:(ZMUser *)sender inConversation:(ZMConversation *)conversation
{
    NSDictionary *data = @{@"info": @{@"tag": @"medium"}};
    ZMLocalNotificationForEvent *note = [self noteWithPayload:data fromUser:sender inConversation:conversation type:EventConversationAddAsset];
    
    XCTAssertNotNil(note);
    
    XCTAssertEqualObjects(conversation, note.conversation);
    if (sender != nil) {
        XCTAssertEqualObjects(sender, note.sender);
    } else {
        XCTAssertNil(note.sender);
    }
    
    XCTAssertNotNil(note.uiNotifications);
    UILocalNotification *notification = note.uiNotifications.lastObject;
    
    return notification;
}


- (void)testThatItCreatesImageAddNotificationsCorrectly
{
    //    "push.notification.add.image.oneonone" = "%1$@ shared a picture";
    //    "push.notification.add.image.oneonone.nousername" = "New picture in a conversation";
    
    //    "push.notification.add.image.group" = "%1$@ shared a picture in %2$@";
    //    "push.notification.add.image.group.nousername" = "New picture in %1$@";
    //    "push.notification.add.image.group.nousername.noconversationname" = "New picture in a conversation";
    //    "push.notification.add.image.group.noconversationname" = "%1$@ shared a picture";
    
    NSDictionary *cases = @{@"Super User shared a picture": @[self.sender, self.oneOnOneConversation],
                            @"New picture in a conversation" : @[self.oneOnOneConversation],
                            
                            @"Super User shared a picture in Super Conversation": @[self.sender, self.groupConversation],
                            @"New picture in Super Conversation":@[ self.groupConversation],
                            @"New picture in a conversation":@[ self.groupConversationWithoutName],
                            @"Super User shared a picture": @[self.sender, self.groupConversationWithoutName],
                            };
    
    [cases enumerateKeysAndObjectsUsingBlock:^(NSString *expectedAlert, NSArray *arguments, BOOL *stop) {
        NOT_USED(stop);
        UILocalNotification *notification;
        if (arguments.count == 2) {
            notification = [self notificationForImageAddEventFromUser:arguments[0] inConversation:arguments[1]];
        }
        else {
            notification = [self notificationForImageAddEventFromUser:nil inConversation:arguments[0]];
        }
        XCTAssertNotNil(notification);
        XCTAssertEqualObjects(notification.alertBody, expectedAlert);
    }];
}

- (void)testThatItDoesNotCreateAnImageAddNotificationForTheWrongPayload
{
    // given
    NSDictionary *data = @{@"info": @{@"tag": @"small"}};
    
    // when
    ZMLocalNotificationForEvent *note = [self noteWithPayload:data fromUser:self.sender inConversation:self.oneOnOneConversation type:EventConversationAddAsset];
    
    // then
    XCTAssertNil(note);
}

- (NSDictionary *)payloadForEncryptedOTRMessageWithFileNonce:(NSUUID *)nonce mimeType:(NSString *)mimeType sender:(ZMUser *)sender conversation:(ZMConversation *)conversation
{
    ZMAssetRemoteDataBuilder* dataBuilder = [[ZMAssetRemoteDataBuilder alloc] init];
    [dataBuilder setSha256:[NSData secureRandomDataOfLength:32]];
    [dataBuilder setOtrKey:[NSData secureRandomDataOfLength:32]];
    
    ZMAssetOriginalBuilder *originalBuilder = [[ZMAssetOriginalBuilder alloc] init];
    [originalBuilder setMimeType:mimeType];
    [originalBuilder setSize:0];
    
    ZMAssetBuilder* assetBuilder = [[ZMAssetBuilder alloc] init];
    [assetBuilder setUploaded:[dataBuilder build]];
    [assetBuilder setOriginal:[originalBuilder build]];
    
    ZMGenericMessageBuilder* genericAssetMessageBuilder = [[ZMGenericMessageBuilder alloc] init];
    [genericAssetMessageBuilder setAsset:[assetBuilder build]];
    [genericAssetMessageBuilder setMessageId:nonce.transportString];
    
    ZMGenericMessage *message = [genericAssetMessageBuilder build];
    NSString *base64EncodedString = message.data.base64String;
    return @{@"info": base64EncodedString,
             @"conversation" : conversation.remoteIdentifier.transportString,
             @"type": EventConversationAddOTRMessage,
             @"from": sender ? sender.remoteIdentifier.transportString : @""
             };
}

- (UILocalNotification *)notificationForFileAddEventWithMimeType:(NSString *)mimeType fromUser:(ZMUser *)sender inConversation:(ZMConversation *)conversation
{
    ZMLocalNotificationForEvent *note = [self noteWithPayload:[self payloadForEncryptedOTRMessageWithFileNonce:[NSUUID UUID] mimeType:mimeType sender:sender conversation:conversation]
                                                     fromUser:sender
                                               inConversation:conversation
                                                         type:EventConversationAddOTRAsset];
    
    XCTAssertNotNil(note);
    
    XCTAssertEqualObjects(conversation, note.conversation);
    if (sender != nil) {
        XCTAssertEqualObjects(sender, note.sender);
    } else {
        XCTAssertNil(note.sender);
    }
    
    XCTAssertNotNil(note.uiNotifications);
    UILocalNotification *notification = note.uiNotifications.lastObject;
    
    return notification;
}

- (void)testThatItCreatesFileAddNotificationsCorrectly
{
    
//    "push.notification.add.file.group" = "%1$@ shared a file in %2$@";
//    "push.notification.add.file.group.nousername" = "New file in %1$@";
//    "push.notification.add.file.group.nousername.noconversationname" = "New file in a conversation";
//    "push.notification.add.file.group.noconversationname" = "%1$@ shared a file in a conversation";
//    
//    "push.notification.add.file.oneonone" = "%1$@ shared a file";
//    "push.notification.add.file.oneonone.nousername" = "New file in a conversation";
//    
    NSDictionary *cases = @{@"Super User shared a file": @[self.sender, self.oneOnOneConversation],
                            @"New file in a conversation" : @[self.oneOnOneConversation],
                            
                            @"Super User shared a file in Super Conversation": @[self.sender, self.groupConversation],
                            @"New file in Super Conversation":@[self.groupConversation],
                            @"New file in a conversation":@[self.groupConversationWithoutName],
                            @"Super User shared a file": @[self.sender, self.groupConversationWithoutName],
                            };
    
    [cases enumerateKeysAndObjectsUsingBlock:^(NSString *expectedAlert, NSArray *arguments, BOOL *stop) {
        NOT_USED(stop);
        UILocalNotification *notification;
        if (arguments.count == 2) {
            notification = [self notificationForFileAddEventWithMimeType:@"application/pdf" fromUser:arguments[0] inConversation:arguments[1]];
        }
        else {
            notification = [self notificationForFileAddEventWithMimeType:@"application/pdf" fromUser:nil inConversation:arguments[0]];
        }
        XCTAssertNotNil(notification);
        XCTAssertEqualObjects(notification.alertBody, expectedAlert);
    }];
}

- (void)testThatItDoesntBundleFileAddNotification
{
    // given
    ZMLocalNotificationForEvent *note1 = [self notificationForType:EventConversationAdd inConversation:self.oneOnOneConversation fromUser:self.sender unreadCrount:4 application:nil];
    
    // when
    ZMLocalNotificationForEvent *note2 = [self copyNote:note1 withPayload:[self payloadForEncryptedOTRMessageWithFileNonce:[NSUUID UUID] mimeType:@"application/pdf" sender:self.sender conversation:self.oneOnOneConversation] fromUser:self.sender inConversation:self.oneOnOneConversation type:EventConversationAddOTRAsset];
    
    // then
    XCTAssertNil(note2);
}

- (void)testThatItCreatesVideoAddNotificationsCorrectly
{
    
    //    "push.notification.add.video.group" = "%1$@ shared a video in %2$@";
    //    "push.notification.add.video.group.nousername" = "New video in %1$@";
    //    "push.notification.add.video.group.nousername.noconversationname" = "New video in a conversation";
    //    "push.notification.add.video.group.noconversationname" = "%1$@ shared a video in a conversation";
    //
    //    "push.notification.add.video.oneonone" = "%1$@ shared a video";
    //    "push.notification.add.video.oneonone.nousername" = "New video in a conversation";
    //
    NSDictionary *cases = @{@"Super User shared a video": @[self.sender, self.oneOnOneConversation],
                            @"New video in a conversation" : @[self.oneOnOneConversation],
                            
                            @"Super User shared a video in Super Conversation": @[self.sender, self.groupConversation],
                            @"New video in Super Conversation":@[self.groupConversation],
                            @"New video in a conversation":@[self.groupConversationWithoutName],
                            @"Super User shared a video": @[self.sender, self.groupConversationWithoutName],
                            };
    
    [cases enumerateKeysAndObjectsUsingBlock:^(NSString *expectedAlert, NSArray *arguments, BOOL *stop) {
        NOT_USED(stop);
        UILocalNotification *notification;
        if (arguments.count == 2) {
            notification = [self notificationForFileAddEventWithMimeType:@"video/mp4" fromUser:arguments[0] inConversation:arguments[1]];
        }
        else {
            notification = [self notificationForFileAddEventWithMimeType:@"video/mp4" fromUser:nil inConversation:arguments[0]];
        }
        XCTAssertNotNil(notification);
        XCTAssertEqualObjects(notification.alertBody, expectedAlert);
    }];
}

- (void)testThatItDoesntBundleVideoAddNotification
{
    // given
    ZMLocalNotificationForEvent *note1 = [self notificationForType:EventConversationAdd inConversation:self.oneOnOneConversation fromUser:self.sender unreadCrount:4 application:nil];
    
    // when
    ZMLocalNotificationForEvent *note2 = [self copyNote:note1 withPayload:[self payloadForEncryptedOTRMessageWithFileNonce:[NSUUID UUID] mimeType:@"video/mp4" sender:self.sender conversation:self.oneOnOneConversation] fromUser:self.sender inConversation:self.oneOnOneConversation type:EventConversationAddOTRAsset];
    
    // then
    XCTAssertNil(note2);
}


- (void)testThatItCreatesAudioAddNotificationsCorrectly
{
    
    //    "push.notification.add.audio.group" = "%1$@ shared an audio message in %2$@";
    //    "push.notification.add.audio.group.nousername" = "New audio message in %1$@";
    //    "push.notification.add.audio.group.nousername.noconversationname" = "New audio message in a conversation";
    //    "push.notification.add.audio.group.noconversationname" = "%1$@ shared an audio message in a conversation";
    //
    //    "push.notification.add.audio.oneonone" = "%1$@ shared an audio message";
    //    "push.notification.add.audio.oneonone.nousername" = "New audio message in a conversation";
    //
    NSDictionary *cases = @{@"Super User shared an audio message": @[self.sender, self.oneOnOneConversation],
                            @"New audio message in a conversation" : @[self.oneOnOneConversation],
                            
                            @"Super User shared an audio message in Super Conversation": @[self.sender, self.groupConversation],
                            @"New audio message in Super Conversation":@[self.groupConversation],
                            @"New audio message in a conversation":@[self.groupConversationWithoutName],
                            @"Super User shared an audio message": @[self.sender, self.groupConversationWithoutName],
                            };
    
    [cases enumerateKeysAndObjectsUsingBlock:^(NSString *expectedAlert, NSArray *arguments, BOOL *stop) {
        NOT_USED(stop);
        UILocalNotification *notification;
        if (arguments.count == 2) {
            notification = [self notificationForFileAddEventWithMimeType:@"audio/x-m4a" fromUser:arguments[0] inConversation:arguments[1]];
        }
        else {
            notification = [self notificationForFileAddEventWithMimeType:@"audio/x-m4a" fromUser:nil inConversation:arguments[0]];
        }
        XCTAssertNotNil(notification);
        XCTAssertEqualObjects(notification.alertBody, expectedAlert);
    }];
}


- (void)testThatItDoesntBundleAudioAddNotification
{
    // given
    ZMLocalNotificationForEvent *note1 = [self notificationForType:EventConversationAdd inConversation:self.oneOnOneConversation fromUser:self.sender unreadCrount:4 application:nil];
    
    // when
    ZMLocalNotificationForEvent *note2 = [self copyNote:note1 withPayload:[self payloadForEncryptedOTRMessageWithFileNonce:[NSUUID UUID] mimeType:@"audio/x-m4a" sender:self.sender conversation:self.oneOnOneConversation] fromUser:self.sender inConversation:self.oneOnOneConversation type:EventConversationAddOTRAsset];
    
    // then
    XCTAssertNil(note2);
}

@end


@implementation ZMLocalNotificationForEventTest (Knocking)

- (UILocalNotification *)notificationForKnockNotificationFromUser:(ZMUser *)sender inConversation:(ZMConversation *)conversation {
    ZMLocalNotificationForEvent *note = [self noteWithPayload:nil fromUser:sender inConversation:conversation type:EventConversationKnock];
    
    XCTAssertNotNil(note);
    
    XCTAssertNotNil(note.conversation);
    XCTAssertEqualObjects(conversation, note.conversation);
    
    if (sender != nil) {
        XCTAssertNotNil(note.sender);
        XCTAssertEqualObjects(sender, note.sender);
    } else {
        XCTAssertNil(note.sender);
    }
    
    XCTAssertNotNil(note.uiNotifications);
    UILocalNotification *notification = note.uiNotifications.lastObject;
    
    return notification;
}

- (UILocalNotification *)notificationForCopyOfKnockNotificationFromUser:(ZMUser *)sender inConversation:(ZMConversation *)conversation {
    ZMLocalNotificationForEvent *note1 = [self noteWithPayload:nil fromUser:sender inConversation:conversation type:EventConversationKnock];
    ZMLocalNotificationForEvent *note = [self copyNote:note1 withPayload:nil fromUser:sender inConversation:conversation type:EventConversationKnock];
    
    XCTAssertNotNil(note1);
    XCTAssertNotNil(note);
    
    XCTAssertNotNil(note.conversation);
    XCTAssertEqualObjects(conversation, note.conversation);
    
    if (sender != nil) {
        XCTAssertNotNil(note.sender);
        XCTAssertEqualObjects(sender, note.sender);
    } else {
        XCTAssertNil(note.sender);
    }
    
    XCTAssertNotNil(note.uiNotifications);
    UILocalNotification *notification = note.uiNotifications.lastObject;
    
    return notification;
}

- (void)testThatItCreatesKnockNotificationsCorrectly
{
    //"push.notification.knock.group" = "%1$@ pinged %3$@ times in %2$@";
    //"push.notification.knock.group.nousername" = "%2$@ pings in %1$@";
    //"push.notification.knock.group.nousername.noconversationname" = "%1$@ pings in a conversation";
    //"push.notification.knock.group.noconversationname" = "%1$@ pinged %2$@ times in a conversation";
    
    //"push.notification.knock.oneonone" = "%1$@ pinged you %2$@ times";
    //"push.notification.knock.oneonone.nousername" = "You were pinged %1$@ times";
    
    NSDictionary *cases = @{ @"Super User pinged " : @[self.sender, self.oneOnOneConversation],
                             @"Ping": @[self.oneOnOneConversation],
                             
                             @"Super User pinged in Super Conversation" : @[self.sender, self.groupConversation],
                             @"Super User pinged in a conversation" : @[self.sender, self.groupConversationWithoutName],
                             @"Ping in Super Conversation" : @[self.groupConversation],
                             @"Ping in a conversation" : @[self.groupConversationWithoutName],
                             };
    
    [cases enumerateKeysAndObjectsUsingBlock:^(NSString *expectedAlert, NSArray *arguments, BOOL *stop) {
        NOT_USED(stop);
        UILocalNotification *notification;
        if (arguments.count == 2) {
            notification = [self notificationForKnockNotificationFromUser:arguments[0] inConversation:arguments[1]];
        }
        else {
            notification = [self notificationForKnockNotificationFromUser:nil inConversation:arguments[0]];
        }
        XCTAssertNotNil(notification);
        XCTAssertEqualObjects(notification.alertBody, expectedAlert);
    }];
}

- (void)testThatItCopiesKnocksCorrectly
{
    //"push.notification.knock.group" = "%1$@ pinged you %3$@ times in “%2$@“";
    //"push.notification.knock.group.nousername" = "%2$@ pings in “%1$@“";
    //"push.notification.knock.group.nousername.noconversationname" = "%1$@ pings in a conversation";
    //"push.notification.knock.group.noconversationname" = "%1$@ pinged you %2$@ times in a conversation";
    //
    //"push.notification.knock.oneonone" = "%1$@ pinged you %2$@ times";
    //"push.notification.knock.oneonone.nousername" = "Someone pinged you %1$@ times";
    
    NSDictionary *cases = @{ @"Super User pinged 2 times" : @[self.sender, self.oneOnOneConversation],
                             @"2 pings": @[self.oneOnOneConversation],
                             
                             @"Super User pinged 2 times in Super Conversation" : @[self.sender, self.groupConversation],
                             @"Super User pinged 2 times in a conversation" : @[self.sender, self.groupConversationWithoutName],
                             @"2 pings in Super Conversation" : @[self.groupConversation],
                             @"2 pings in a conversation" : @[self.groupConversationWithoutName],
                             };
    
    [cases enumerateKeysAndObjectsUsingBlock:^(NSString *expectedAlert, NSArray *arguments, BOOL *stop) {
        NOT_USED(stop);
        UILocalNotification *notification;
        if (arguments.count == 2) {
            notification = [self notificationForCopyOfKnockNotificationFromUser:arguments[0] inConversation:arguments[1]];
        }
        else {
            notification = [self notificationForCopyOfKnockNotificationFromUser:nil inConversation:arguments[0]];
        }
        XCTAssertNotNil(notification);
        XCTAssertEqualObjects(notification.alertBody, expectedAlert);
    }];
}

- (void)testThatItDoesNotCopyAKnockNotificationWhenTheSenderDiffersInGroupConversations
{
    //given
    ZMUser *user2 = [self insertUserWithRemoteID:[NSUUID createUUID] name:@"Super User2"];

    // when
    ZMLocalNotificationForEvent *note = [self noteWithPayload:nil fromUser:self.sender inConversation:self.groupConversation type:EventConversationKnock];
    
    NSString *expectedAlertText1 = @"Super User pinged in Super Conversation";
    
    XCTAssertNotNil(note);
    XCTAssertNotNil(note.uiNotifications);
    UILocalNotification *notification1 = note.uiNotifications.lastObject;
    XCTAssertEqualObjects(notification1.alertBody, expectedAlertText1);
    
    ZMLocalNotificationForEvent *note2 = [self copyNote:note withPayload:nil fromUser:user2 inConversation:self.groupConversation type:EventConversationKnock];
    
    // then
    XCTAssertNil(note2);
}

- (void)testThatItDoesNotReturnsACopyIfThereWasNoPriorKnockEvent
{
    // given
    NSDictionary *data = @{@"content": @"Hello Hello!"};

    // when
    ZMLocalNotificationForEvent *note = [self noteWithPayload:data fromUser:self.sender inConversation:self.oneOnOneConversation type:EventConversationAdd];
    ZMLocalNotificationForEvent *note2 = [self copyNote:note withPayload:nil fromUser:self.sender inConversation:self.oneOnOneConversation type:EventConversationKnock];
    
    // then
    XCTAssertNil(note2);
}

@end





@implementation ZMLocalNotificationForEventTest (MemberJoinAndLeave)

- (UILocalNotification *)notificationForMemberAddedWithSenderID:(NSUUID *)userID conversation:(ZMConversation *)conversation otherUsers:(NSArray *)otherUserIDs;
{
    return [self notificationForEvent:EventConversationMemberJoin WithSenderID:userID conversation:conversation otherUsers:otherUserIDs];
}

- (UILocalNotification *)notificationForMemberLeaveWithSenderID:(NSUUID *)userID conversation:(ZMConversation *)conversation otherUsers:(NSArray *)otherUserIDs;
{
    return[self notificationForEvent:EventConversationMemberLeave WithSenderID:userID conversation:conversation otherUsers:otherUserIDs];
}


- (UILocalNotification *)notificationForEvent:(NSString *)event WithSenderID:(NSUUID *)userID conversation:(ZMConversation *)conversation otherUsers:(NSArray *)otherUserIDs;
{
    NSMutableArray *users = [NSMutableArray array];
    if (otherUserIDs == nil || otherUserIDs.count == 0) {
        [users addObject:NSUUID.createUUID.transportString];
    }
    else {
        for (NSUUID *newUserID in otherUserIDs) {
            [users addObject:newUserID.transportString];
        }
    }
    
    NSDictionary *data = @{@"user_ids" : users};
    
    // when
    ZMLocalNotificationForEvent *note1 = [self noteWithPayload:data fromUserID:userID inConversation:conversation type:event application:nil];
    
    // then
    
    XCTAssertNotNil(note1);
    
    XCTAssertNotNil(note1.conversation);
    XCTAssertEqualObjects(conversation, note1.conversation);
    
    XCTAssertNotNil(note1.uiNotifications);
    UILocalNotification *notification = note1.uiNotifications.lastObject;
    return notification;
}


- (void)testThatItCreatesMemberJoinNotificationsCorrectly
{
    //    "push.notification.member.join.self" = "%1$@ added you to %2$@";
    //    "push.notification.member.join.self.noconversationname" = "%1$@ added you to a conversation";
    //    "push.notification.member.join.self.nousername.noconversationname" = "You were added to a conversation";
    //    "push.notification.member.join.self.nousername" = "You were added to %1$@";
    //
    //    "push.notification.member.join" = "%1$@ added %3$@ to %2$@";
    //    "push.notification.member.join.noconversationname" = "%1$@ added %2$@ to a conversation";
    //    "push.notification.member.join.nousername.noconversationname" = "%1$@ was added to a conversation";
    //    "push.notification.member.join.nousername" = "%2$@ was added to %1$@";
    //
    //    "push.notification.member.join.many.nootherusername" = "%1$@ added people to %2$@";
    //    "push.notification.member.join.many.nootherusername.noconversationname" = "%1$@ added people to a conversation";
    //    "push.notification.member.join.many.nootherusername.nousername" = "People were added to %1$@";
    //    "push.notification.member.join.many.nootherusername.nousername.noconversationname" = "People were added to a conversation";
    //
    //    "push.notification.member.join.nootherusername" = "%1$@ added people to %2$@";
    //    "push.notification.member.join.nootherusername.noconversationname" = "%1$@ added people to a conversation";
    //    "push.notification.member.join.nootherusername.nousername.noconversationname" = "People were added to a conversation";
    //    "push.notification.member.join.nootherusername.nousername" = "People were added to %1$@";
    
    NSUUID *senderID = self.sender.remoteIdentifier;
    NSUUID *otherUserID = self.otherUser.remoteIdentifier;
    NSUUID *selfUserID = self.selfUser.remoteIdentifier;
    
    NSDictionary *cases = @{@"Super User added you to Super Conversation" : @[senderID, self.groupConversation, @[selfUserID]],
                             @"Super User added you to a conversation" :  @[senderID, self.groupConversationWithoutName, @[selfUserID]],
                             @"You were added to a conversation" :  @[self.groupConversationWithoutName, @[selfUserID]],
                             @"You were added to Super Conversation" : @[self.groupConversation, @[selfUserID]],

                             @"Super User added Other User to Super Conversation": @[senderID, self.groupConversation, @[otherUserID]],
                             @"Super User added Other User to a conversation" :  @[senderID, self.groupConversationWithoutName, @[otherUserID]],
                            @"Other User was added to a conversation" :  @[self.groupConversationWithoutName, @[otherUserID]],
                             @"Other User was added to Super Conversation" :  @[self.groupConversation, @[otherUserID]],

                             @"Super User added people to Super Conversation": @[senderID, self.groupConversation, @[otherUserID, senderID]],
                             @"Super User added people to a conversation" :  @[senderID, self.groupConversationWithoutName, @[senderID, otherUserID]],
                            @"People were added to a conversation" :  @[self.groupConversationWithoutName, @[senderID, otherUserID]],
                             @"People were added to Super Conversation": @[self.groupConversation, @[otherUserID, senderID]],
                            
                            @"Super User added people to Super Conversation": @[senderID, self.groupConversation, @[]],
                            @"Super User added people to a conversation" :  @[senderID, self.groupConversationWithoutName, @[]],
                            @"People were added to a conversation" :  @[self.groupConversationWithoutName, @[]],
                            @"People were added to Super Conversation": @[self.groupConversation, @[]],
                             };
    
    [cases enumerateKeysAndObjectsUsingBlock:^(NSString *expectedAlert, NSArray *arguments, BOOL *stop) {
        NOT_USED(stop);
        UILocalNotification *notification;
        if (arguments.count == 3) {
            NSArray *users = arguments[2];
            notification = [self notificationForMemberAddedWithSenderID:arguments[0] conversation:arguments[1] otherUsers: (users.count == 0) ? nil : users];
        }
        else {
            notification = [self notificationForMemberAddedWithSenderID:nil conversation:arguments[0] otherUsers:arguments[1]];
        }
        XCTAssertNotNil(notification);
        XCTAssertEqualObjects(notification.alertBody, expectedAlert);
    }];
}

- (void)testThatItCreatesMemberLeaveNotificationsCorrectly
{
    
    //    "push.notification.member.leave.self" = "%1$@ removed you from %2$@";
    //    "push.notification.member.leave.self.noconversationname" = "%1$@ removed you from a conversation";
    //    "push.notification.member.leave.self.nousername.noconversationname" = "You were removed from a conversation";
    //    "push.notification.member.leave.self.nousername" = "You were removed from %1$@";
    //
    //    "push.notification.member.leave" = "%1$@ removed %3$@ from %2$@";
    //    "push.notification.member.leave.noconversationname" = "%1$@ removed %2$@ from a conversation";
    //    "push.notification.member.leave.nousername.noconversationname" = "%1$@ was removed from a conversation";
    //    "push.notification.member.leave.nousername" = "%2$@ was removed from %1$@";
    //
    //    "push.notification.member.leave.nootherusername" = "%1$@ removed people from %2$@";
    //    "push.notification.member.leave.nootherusername.noconversationname" = "%1$@ removed people from a conversation";
    //    "push.notification.member.leave.nootherusername.nousername.noconversationname" = "People were removed from a conversation";
    //    "push.notification.member.leave.nootherusername.nousername" = "People were removed from %1$@";
    //
    //    "push.notification.member.leave.sender.nootherusername" = "%1$@ left %2$@";
    //    "push.notification.member.leave.sender.nootherusername.noconversationname" = "%1$@ left a conversation";
    //    "push.notification.member.leave.sender.nootherusername.nousername.noconversationname" = "Someone left a conversation";
    //    "push.notification.member.leave.sender.nootherusername.nousername" = "Someone left %1$@";
    //
    //    "push.notification.member.leave.many.nootherusername" = "%1$@ removed people from %2$@";
    //    "push.notification.member.leave.many.nootherusername.noconversationname" = "%1$@ removed people from a conversation";
    //    "push.notification.member.leave.many.nootherusername.nousername" = "People were removed from %1$@";
    //    "push.notification.member.leave.many.nootherusername.nousername.noconversationname" = "People were removed from a conversation";
    //
    
    NSUUID *senderID = self.sender.remoteIdentifier;
    NSUUID *otherUserID = self.otherUser.remoteIdentifier;
    NSUUID *selfUserID = self.selfUser.remoteIdentifier;
    NSUUID *unknownUserID = NSUUID.createUUID;
    
    NSDictionary *cases = @{@"Super User removed you from Super Conversation" : @[senderID, self.groupConversation, @[selfUserID]],
                             @"Super User removed you from a conversation" :  @[senderID, self.groupConversationWithoutName, @[selfUserID]],
                             @"You were removed from a conversation" :  @[self.groupConversationWithoutName, @[selfUserID]],
                             @"You were removed from Super Conversation" : @[self.groupConversation, @[selfUserID]],
                             
                             @"Super User removed Other User from Super Conversation": @[senderID, self.groupConversation, @[otherUserID]],
                             @"Super User removed Other User from a conversation" :  @[senderID, self.groupConversationWithoutName, @[otherUserID]],
                             @"Other User was removed from Super Conversation" :  @[self.groupConversation, @[otherUserID]],
                             @"Other User was removed from a conversation" :  @[self.groupConversationWithoutName, @[otherUserID]],
                             
                             @"Super User removed people from Super Conversation": @[senderID, self.groupConversation, @[otherUserID, senderID]],
                             @"Super User removed people from a conversation" :  @[senderID, self.groupConversationWithoutName, @[senderID, otherUserID]],
                             @"People were removed from Super Conversation": @[self.groupConversation, @[otherUserID, senderID]],
                             @"People were removed from a conversation" :  @[self.groupConversationWithoutName, @[senderID, otherUserID]],
                             
                             @"Super User left Super Conversation": @[senderID, self.groupConversation, @[senderID]],
                             @"Super User left a conversation" :  @[senderID, self.groupConversationWithoutName, @[senderID]],
                            
                            @"People left Super Conversation": @[unknownUserID, self.groupConversation, @[unknownUserID]],
                            @"People left a conversation" :  @[unknownUserID, self.groupConversationWithoutName, @[unknownUserID]],
                            
                            @"Super User removed people from Super Conversation": @[senderID, self.groupConversation, @[]],
                            @"Super User removed people from a conversation" :  @[senderID, self.groupConversationWithoutName, @[]],
                            @"People were removed from a conversation" :  @[self.groupConversationWithoutName, @[]],
                            @"People were removed from Super Conversation": @[self.groupConversation, @[]],
                             };
    
    [cases enumerateKeysAndObjectsUsingBlock:^(NSString *expectedAlert, NSArray *arguments, BOOL *stop) {
        NOT_USED(stop);
        UILocalNotification *notification;
        if (arguments.count == 3) {
            NSArray *users = arguments[2];
            notification = [self notificationForMemberLeaveWithSenderID:arguments[0] conversation:arguments[1] otherUsers:(users.count == 0) ? nil : users];
        }
        else {
            notification = [self notificationForMemberLeaveWithSenderID:nil conversation:arguments[0] otherUsers:arguments[1]];
        }
        XCTAssertNotNil(notification);
        XCTAssertEqualObjects(notification.alertBody, expectedAlert, "%@", arguments);
    }];
}


- (void)testThatItCopiesANotificationIfAnotherUserIsAddedByTheSameSender
{
    // "push.notification.member.join.many.nootherusername" = "%1$@ added people to “%2$@“";

    // given
    ZMUser *user1 = [self insertUserWithRemoteID:[NSUUID createUUID] name:@"Super User2"];
    ZMUser *user2 = [self insertUserWithRemoteID:[NSUUID createUUID] name:@"Super User3"];
    
    NSDictionary *data1 = @{@"user_ids" : @[user1.remoteIdentifier.transportString]};
    NSDictionary *data2 = @{@"user_ids" : @[user2.remoteIdentifier.transportString]};
    
    // when
    ZMLocalNotificationForEvent *note1 = [self noteWithPayload:data1 fromUser:self.sender inConversation:self.groupConversation type:EventConversationMemberJoin];
    ZMLocalNotificationForEvent *note2 = [self copyNote:note1 withPayload:data2 fromUser:self.sender inConversation:self.groupConversation type:EventConversationMemberJoin];
    
    // then
    
    NSString *expectedAlertBody = @"Super User added people to Super Conversation";
    
    XCTAssertNotNil(note2);
    
    XCTAssertNotNil(note2.uiNotifications);
    UILocalNotification *notification = note2.uiNotifications.lastObject;
    XCTAssertEqualObjects(notification.alertBody, expectedAlertBody);
    
    XCTAssertNotNil(note2.conversation);
    XCTAssertEqualObjects(self.groupConversation, note2.conversation);
}

- (void)testThatItCopiesANotificationIfAnotherUserIsAddedByAnotherSender
{
    // "push.notification.member.join.many.nootherusername.nousername" = "People were added to “%1$@“";

    // given
    ZMUser *user1 = [self insertUserWithRemoteID:[NSUUID createUUID] name:@"Super User1"];
    ZMUser *user2 = [self insertUserWithRemoteID:[NSUUID createUUID] name:@"Super User2"];
    ZMUser *user3 = [self insertUserWithRemoteID:[NSUUID createUUID] name:@"Super User3"];

    NSDictionary *data1 = @{@"user_ids" : @[user1.remoteIdentifier.transportString]};
    NSDictionary *data2 = @{@"user_ids" : @[user2.remoteIdentifier.transportString]};
    
    // when
    ZMLocalNotificationForEvent *note1 = [self noteWithPayload:data1 fromUser:self.sender inConversation:self.groupConversation type:EventConversationMemberJoin];
    ZMLocalNotificationForEvent *note2 = [self copyNote:note1 withPayload:data2 fromUser:user3 inConversation:self.groupConversation type:EventConversationMemberJoin];
    
    
    // then
    NSString *expectedAlertBody = @"People were added to Super Conversation";
    
    XCTAssertNotNil(note1);
    XCTAssertNotNil(note2);
    
    XCTAssertNotNil(note2.uiNotifications);
    UILocalNotification *notification = note2.uiNotifications.lastObject;
    XCTAssertEqualObjects(notification.alertBody, expectedAlertBody);
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




@implementation ZMLocalNotificationForEventTest (ConversationRename)

- (void)testThatItCreatesConversationRenameNotifications
{
    // "push.notification.conversation.rename" = "%1$@ renamed a conversation to %2$@";

    // given
    NSDictionary *data1 = @{@"name" : @"New Conversation Name"};
    
    // when
    ZMLocalNotificationForEvent *note1 = [self noteWithPayload:data1 fromUser:self.sender inConversation:self.groupConversation type:EventConversationRename];

    // then
    NSString *expectedAlertText = @"Super User renamed a conversation to New Conversation Name";
    
    XCTAssertNotNil(note1);
    
    XCTAssertNotNil(note1.uiNotifications);
    UILocalNotification *notification = note1.uiNotifications.lastObject;
    XCTAssertEqualObjects(notification.alertBody, expectedAlertText);
}

- (void)testThatItCreatesConversationRenameNotifications_NoUserName
{
    // "push.notification.conversation.rename.nousername" = "A conversation was renamed to %1$@";

    // given
    NSDictionary *data1 = @{@"name" : @"New Conversation Name"};
    
    // when
    ZMLocalNotificationForEvent *note1 = [self noteWithPayload:data1 fromUser:nil inConversation:self.groupConversation type:EventConversationRename];
    
    // then
    NSString *expectedAlertText = @"A conversation was renamed to New Conversation Name";
    
    XCTAssertNotNil(note1);
    
    XCTAssertNotNil(note1.uiNotifications);
    UILocalNotification *notification = note1.uiNotifications.lastObject;
    XCTAssertEqualObjects(notification.alertBody, expectedAlertText);
}

- (void)testThatItDoesNotCreateAConversationRenameNotificationWhenTheDataIsNil
{
    // given
    NSDictionary *data1 = nil;
    
    // when
    ZMLocalNotificationForEvent *note1 = [self noteWithPayload:data1 fromUser:self.sender inConversation:self.groupConversation type:EventConversationRename];
    
    // then
    XCTAssertNil(note1);
}

@end


@implementation ZMLocalNotificationForEventTest (Connection)

- (void)testThatItCreatesAConnectionRequestNotification
{
    // given
    NSDictionary *data1 = @{@"name" : @"User Name",
                            @"message": @"Hallo"};
    
    // when
    ZMLocalNotificationForEvent *note1 = [self noteWithPayload:data1 fromUser:self.sender inConversation:self.oneOnOneConversation type:EventConversationConnectionRequest];
    
    // then
    
    NSString *expectedAlertText = @"User Name wants to connect";
    
    XCTAssertNotNil(note1);
    
    XCTAssertNotNil(note1.uiNotifications);
    UILocalNotification *notification = note1.uiNotifications.lastObject;
    XCTAssertEqualObjects(notification.alertBody, expectedAlertText);
    
    XCTAssertNotNil(note1.conversation);
    XCTAssertEqualObjects(self.oneOnOneConversation, note1.conversation);
}

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
        note = [ZMLocalNotificationForEvent notificationForEvent:event managedObjectContext:self.syncMOC application:nil];
    }];
    
    return note;
}

- (UILocalNotification *)noteForConnectionRequestEventTo:(ZMUser *)toUser status:(NSString *)status
{
    ZMLocalNotificationForEvent *note = [self zmNoteForConnectionRequestEventTo:toUser status:status];
    
    XCTAssertNotNil(note);
    XCTAssertNotNil(note.conversation);
    XCTAssertEqualObjects(self.oneOnOneConversation, note.conversation);
    
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
        note = [ZMLocalNotificationForEvent notificationForEvent:event managedObjectContext:self.syncMOC application:nil];
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
    ZMGenericMessage *message = [ZMGenericMessage messageWithText:text nonce:nonce.transportString];
    NSString *base64EncodedString = message.data.base64String;
    return @{@"data": @{ @"text": base64EncodedString},
             @"conversation" : self.oneOnOneConversation.remoteIdentifier.transportString,
             @"type": EventConversationAddOTRMessage,
             @"from": self.sender.remoteIdentifier.transportString,
             @"time": [NSDate date].transportString
             };
}

- (void)testThatItCreatesALocalNotificationFromAnEncryptedEvent
{
    // given
    NSString *text = @"Hallo";
    NSString *expectedText = [NSString stringWithFormat:@"%@: %@", self.sender.name, text];
    NSUUID *nonce = [NSUUID UUID];
    NSDictionary *eventPayload = [self payloadForEncryptedOTRMessageWithText:text nonce:nonce];
    ZMUpdateEvent *event = [ZMUpdateEvent eventFromEventStreamPayload:eventPayload uuid:nil];

    // when
    ZMLocalNotificationForEvent *note = [ZMLocalNotificationForEvent notificationForEvent:event managedObjectContext:self.syncMOC application:nil];
    
    // then
    UILocalNotification *notif = note.uiNotifications.firstObject;
    XCTAssertEqualObjects(notif.alertBody, expectedText);
    XCTAssertEqualObjects(notif.zm_messageNonce, nonce);
    XCTAssertEqualObjects(notif.zm_senderUUID, self.sender.remoteIdentifier);
}

@end

@implementation ZMLocalNotificationForEvent (Reaction)

- (void)testThatItCreatesAReactionNotificationWhenSomeoneReactToSelfUserMessage;
{
    
}

@end



//////
/// To test change "Localization native development region" in Test-Host-Info.plist to "de"
//////

//@implementation ZMLocalNotificationForEventTest (German)
//
//
//- (void)testItCreatesMessageAddNotificationsCorrectly_German
//{
////    "push.notification.add.message.group" = "%1$@ in %2$@: %3$@";
////    "push.notification.add.message.group.nousername" = "Neue Nachricht in %1$@: %2$@";
////    "push.notification.add.message.group.nousername.noconversationname" = "Neue Nachricht: %1$@";
////    "push.notification.add.message.group.noconversationname" = "%1$@ in einer Unterhaltung: %2$@";
////    
////    "push.notification.add.message.oneonone" = "%1$@: %2$@";
////    "push.notification.add.message.oneonone.nousername" = "Neue Nachricht: %1$@";
//    
//    NSDictionary *cases = @{@"Super User: Hello Hello!" : @[self.sender, self.oneOnOneConversation],
//                            @"Neue Nachricht: Hello Hello!" : @[self.oneOnOneConversation],
//                            
//                            @"Super User in Super Conversation: Hello Hello!":  @[self.sender, self.groupConversation],
//                            @"Neue Nachricht in Super Conversation: Hello Hello!": @[self.groupConversation],
//                            @"Neue Nachricht: Hello Hello!": @[self.groupConversationWithoutName],
//                            @"Super User in einer Unterhaltung: Hello Hello!":  @[self.sender, self.groupConversationWithoutName],
//                            };
//    
//    [cases enumerateKeysAndObjectsUsingBlock:^(NSString *expectedAlert, NSArray *arguments, BOOL *stop) {
//        NOT_USED(stop);
//        UILocalNotification *notification;
//        if (arguments.count == 2) {
//            notification = [self notificationForMessageAddEventFromUser:arguments[0] inConversation:arguments[1]];
//        }
//        else {
//            notification = [self notificationForMessageAddEventFromUser:nil inConversation:arguments[0]];
//        }
//        XCTAssertNotNil(notification);
//        XCTAssertEqualObjects(notification.alertBody, expectedAlert);
//    }];
//}
//
//
//- (void)testThatItCreatesImageAddNotificationsCorrectly_German
//{
//    //    "push.notification.add.image.group" = "%1$@ hat ein Bild in %2$@ geteilt";
//    //    "push.notification.add.image.group.nousername" = "Jemand hat ein Bild in %1$@ geteilt";
//    //    "push.notification.add.image.group.nousername.noconversationname" = "Jemand hat ein Bild in einer Unterhaltung geteilt";
//    //    "push.notification.add.image.group.noconversationname" = "%1$@ hat ein Bild in einer Unterhaltung geteilt";
//    //
//    //    "push.notification.add.image.oneonone" = "%1$@ hat ein Bild geteilt";
//    //    "push.notification.add.image.oneonone.nousername" = "Jemand hat ein Bild in einer Unterhaltung geteilt";
//    
//    NSDictionary *cases = @{@"Super User hat ein Bild geteilt": @[self.sender, self.oneOnOneConversation],
//                            @"Jemand hat ein Bild in einer Unterhaltung geteilt" : @[self.oneOnOneConversation],
//                            
//                            @"Super User hat ein Bild in Super Conversation geteilt": @[self.sender, self.groupConversation],
//                            @"Jemand hat ein Bild in Super Conversation geteilt":@[ self.groupConversation],
//                            @"Jemand hat ein Bild in einer Unterhaltung geteilt":@[ self.groupConversationWithoutName],
//                            @"Super User hat ein Bild geteilt": @[self.sender, self.groupConversationWithoutName],
//                            };
//    
//    [cases enumerateKeysAndObjectsUsingBlock:^(NSString *expectedAlert, NSArray *arguments, BOOL *stop) {
//        NOT_USED(stop);
//        UILocalNotification *notification;
//        if (arguments.count == 2) {
//            notification = [self notificationForImageAddEventFromUser:arguments[0] inConversation:arguments[1]];
//        }
//        else {
//            notification = [self notificationForImageAddEventFromUser:nil inConversation:arguments[0]];
//        }
//        XCTAssertNotNil(notification);
//        XCTAssertEqualObjects(notification.alertBody, expectedAlert);
//    }];
//}
//
//- (void)testThatItCreatesMemberLeaveNotificationsCorrectly_German
//{
//    NSUUID *senderID = self.sender.remoteIdentifier;
//    NSUUID *otherUserID = self.otherUser.remoteIdentifier;
//    NSUUID *selfUserID = self.selfUser.remoteIdentifier;
//    NSUUID *unknownUserID = NSUUID.createUUID;
//    
//    NSDictionary *cases = @{@"Super User hat dich aus Super Conversation entfernt" : @[senderID, self.groupConversation, @[selfUserID]],
//                            @"Super User hat dich aus einer Unterhaltung entfernt" :  @[senderID, self.groupConversationWithoutName, @[selfUserID]],
//                            @"Du wurdest aus einer Unterhaltung entfernt" :  @[self.groupConversationWithoutName, @[selfUserID]],
//                            @"Du wurdest aus Super Conversation entfernt" : @[self.groupConversation, @[selfUserID]],
//                            
//                            @"Super User hat Other User aus Super Conversation entfernt": @[senderID, self.groupConversation, @[otherUserID]],
//                            @"Super User hat Other User aus einer Unterhaltung entfernt" :  @[senderID, self.groupConversationWithoutName, @[otherUserID]],
//                            @"Other User wurde aus Super Conversation entfernt" :  @[self.groupConversation, @[otherUserID]],
//                            @"Other User wurde aus einer Unterhaltung entfernt" :  @[self.groupConversationWithoutName, @[otherUserID]],
//                            
//                            @"Super User hat Teilnehmer aus Super Conversation entfernt": @[senderID, self.groupConversation, @[otherUserID, senderID]],
//                            @"Super User hat Teilnehmer aus einer Unterhaltung entfernt" :  @[senderID, self.groupConversationWithoutName, @[senderID, otherUserID]],
//                            @"Teilnehmer wurden aus Super Conversation entfernt": @[self.groupConversation, @[otherUserID, senderID]],
//                            @"Teilnehmer wurden aus einer Unterhaltung entfernt" :  @[self.groupConversationWithoutName, @[senderID, otherUserID]],
//                            
//                            @"Super User hat Super Conversation verlassen": @[senderID, self.groupConversation, @[senderID]],
//                            @"Super User hat eine Unterhaltung verlassen" :  @[senderID, self.groupConversationWithoutName, @[senderID]],
//                            
//                            @"Jemand hat Super Conversation verlassen": @[unknownUserID, self.groupConversation, @[unknownUserID]],
//                            @"Jemand hat eine Unterhaltung verlassen" :  @[unknownUserID, self.groupConversationWithoutName, @[unknownUserID]],
//                            
//                            @"Super User hat Teilnehmer aus Super Conversation entfernt": @[senderID, self.groupConversation, @[]],
//                            @"Super User hat Teilnehmer aus einer Unterhaltung entfernt" :  @[senderID, self.groupConversationWithoutName, @[]],
//                            @"Teilnehmer wurden aus einer Unterhaltung entfernt" :  @[self.groupConversationWithoutName, @[]],
//                            @"Teilnehmer wurden aus Super Conversation entfernt": @[self.groupConversation, @[]],
//                            };
//    
//    [cases enumerateKeysAndObjectsUsingBlock:^(NSString *expectedAlert, NSArray *arguments, BOOL *stop) {
//        NOT_USED(stop);
//        UILocalNotification *notification;
//        if (arguments.count == 3) {
//            NSArray *users = arguments[2];
//            notification = [self notificationForMemberLeaveWithSenderID:arguments[0] conversation:arguments[1] otherUsers:(users.count == 0) ? nil : users];
//        }
//        else {
//            notification = [self notificationForMemberLeaveWithSenderID:nil conversation:arguments[0] otherUsers:arguments[1]];
//        }
//        XCTAssertNotNil(notification);
//        XCTAssertEqualObjects(notification.alertBody, expectedAlert);
//    }];
//}
//
//
//- (void)testThatItCreatesMemberJoinNotificationsCorrectly_German
//{
//    NSUUID *senderID = self.sender.remoteIdentifier;
//    NSUUID *otherUserID = self.otherUser.remoteIdentifier;
//    NSUUID *selfUserID = self.selfUser.remoteIdentifier;
//    
//    NSDictionary *cases = @{@"Super User hat dich zu Super Conversation hinzugefügt" : @[senderID, self.groupConversation, @[selfUserID]],
//                            @"Super User hat dich zu einer Unterhaltung hinzugefügt" :  @[senderID, self.groupConversationWithoutName, @[selfUserID]],
//                            @"Du wurdest zu einer Unterhaltung hinzugefügt" :  @[self.groupConversationWithoutName, @[selfUserID]],
//                            @"Du wurdest zu Super Conversation hinzugefügt" : @[self.groupConversation, @[selfUserID]],
//                            
//                            @"Super User hat Other User zu Super Conversation hinzugefügt": @[senderID, self.groupConversation, @[otherUserID]],
//                            @"Super User hat Other User zu einer Unterhaltung hinzugefügt" :  @[senderID, self.groupConversationWithoutName, @[otherUserID]],
//                            @"Other User wurde zu einer Unterhaltung hinzugefügt" :  @[self.groupConversationWithoutName, @[otherUserID]],
//                            @"Other User wurde zu Super Conversation hinzugefügt" :  @[self.groupConversation, @[otherUserID]],
//                            
//                            @"Super User hat Teilnehmer zu Super Conversation hinzugefügt": @[senderID, self.groupConversation, @[otherUserID, senderID]],
//                            @"Super User hat Teilnehmer zu einer Unterhaltung hinzugefügt" :  @[senderID, self.groupConversationWithoutName, @[senderID, otherUserID]],
//                            @"Teilnehmer wurden zu einer Unterhaltung hinzugefügt" :  @[self.groupConversationWithoutName, @[senderID, otherUserID]],
//                            @"Teilnehmer wurden zu Super Conversation hinzugefügt": @[self.groupConversation, @[otherUserID, senderID]],
//                            
//                            @"Super User hat Teilnehmer zu Super Conversation hinzugefügt": @[senderID, self.groupConversation, @[]],
//                            @"Super User hat Teilnehmer zu einer Unterhaltung hinzugefügt" :  @[senderID, self.groupConversationWithoutName, @[]],
//                            @"Teilnehmer wurden zu einer Unterhaltung hinzugefügt" :  @[self.groupConversationWithoutName, @[]],
//                            @"Teilnehmer wurden zu Super Conversation hinzugefügt": @[self.groupConversation, @[]],
//                            };
//    
//    [cases enumerateKeysAndObjectsUsingBlock:^(NSString *expectedAlert, NSArray *arguments, BOOL *stop) {
//        NOT_USED(stop);
//        UILocalNotification *notification;
//        if (arguments.count == 3) {
//            NSArray *users = arguments[2];
//            notification = [self notificationForMemberAddedWithSenderID:arguments[0] conversation:arguments[1] otherUsers: (users.count == 0) ? nil : users];
//        }
//        else {
//            notification = [self notificationForMemberAddedWithSenderID:nil conversation:arguments[0] otherUsers:arguments[1]];
//        }
//        XCTAssertNotNil(notification);
//        XCTAssertEqualObjects(notification.alertBody, expectedAlert);
//    }];
//}
//
//
//- (void)testThatItCreatesKnockNotificationsCorrectly_German
//{
//    
////    "push.notification.knock.oneonone" = "%1$@ hat gepingt";
////    "push.notification.knock.oneonone.nousername" = "Jemand hat gepingt";
////    
////    "push.notification.knock.group" = "%1$@ hat in %2$@ gepingt";
////    "push.notification.knock.group.nousername" = "Jemand hat in %2$@ gepingt";
////    "push.notification.knock.group.noconversationname" = "%1$@ hat in einer Unterhaltung gepingt";
////    "push.notification.knock.group.nousername.noconversationname" = "Jemand hat in einer Unterhaltung gepingt";
//    
//    NSDictionary *cases = @{ @"Super User hat gepingt" : @[self.sender, self.oneOnOneConversation],
//                             @"Jemand hat gepingt": @[self.oneOnOneConversation],
//                             
//                             @"Super User hat in Super Conversation gepingt" : @[self.sender, self.groupConversation],
//                             @"Super User hat in einer Unterhaltung gepingt" : @[self.sender, self.groupConversationWithoutName],
//                             @"Jemand hat in Super Conversation gepingt" : @[self.groupConversation],
//                             @"Jemand hat in einer Unterhaltung gepingt" : @[self.groupConversationWithoutName],
//                             };
//    
//    [cases enumerateKeysAndObjectsUsingBlock:^(NSString *expectedAlert, NSArray *arguments, BOOL *stop) {
//        NOT_USED(stop);
//        UILocalNotification *notification;
//        if (arguments.count == 2) {
//            notification = [self notificationForKnockNotificationFromUser:arguments[0] inConversation:arguments[1]];
//        }
//        else {
//            notification = [self notificationForKnockNotificationFromUser:nil inConversation:arguments[0]];
//        }
//        XCTAssertNotNil(notification);
//        XCTAssertEqualObjects(notification.alertBody, expectedAlert);
//    }];
//}
//
//- (void)testThatItCopiesKnocksCorrectly_German
//{
//    NSDictionary *cases = @{ @"Super User hat 2 mal gepingt" : @[self.sender, self.oneOnOneConversation],
//                             @"Jemand hat 2 mal gepingt": @[self.oneOnOneConversation],
//                             
//                             @"Super User hat 2 mal in Super Conversation gepingt" : @[self.sender, self.groupConversation],
//                             @"Super User hat 2 mal in einer Unterhaltung gepingt" : @[self.sender, self.groupConversationWithoutName],
//                             @"Jemand hat 2 mal in Super Conversation gepingt" : @[self.groupConversation],
//                             @"Jemand hat 2 mal in einer Unterhaltung gepingt" : @[self.groupConversationWithoutName],
//                             };
//    
//    [cases enumerateKeysAndObjectsUsingBlock:^(NSString *expectedAlert, NSArray *arguments, BOOL *stop) {
//        NOT_USED(stop);
//        UILocalNotification *notification;
//        if (arguments.count == 2) {
//            notification = [self notificationForCopyOfKnockNotificationFromUser:arguments[0] inConversation:arguments[1]];
//        }
//        else {
//            notification = [self notificationForCopyOfKnockNotificationFromUser:nil inConversation:arguments[0]];
//        }
//        XCTAssertNotNil(notification);
//        XCTAssertEqualObjects(notification.alertBody, expectedAlert);
//    }];
//}
//
//
//- (void)testThatItCreatesAConnectionRequestNotification_German
//{
//    // "push.notification.connection.request" = "%@ möchte sich mit dir verbinden";
//
//    // given
//    NSDictionary *data1 = @{@"name" : @"User Name",
//                            @"message": @"Hallo"};
//    
//    // when
//    ZMLocalNotificationForEvent *note1 = [self noteWithPayload:data1 fromUser:self.sender inConversation:self.oneOnOneConversation type:EventConversationConnectionRequest];
//    
//    // then
//    
//    NSString *expectedAlertText = @"Super User möchte sich mit dir verbinden";
//    
//    XCTAssertNotNil(note1);
//    
//    XCTAssertNotNil(note1.uiNotifications);
//    UILocalNotification *notification = note1.uiNotifications.lastObject;
//    XCTAssertEqualObjects(notification.alertBody, expectedAlertText);
//    
//    XCTAssertNotNil(note1.conversation);
//    XCTAssertEqualObjects(self.oneOnOneConversation, note1.conversation);
//}
//
//
//- (void)testThatItCreatesConnectionRequestNotificationsCorrectly_German
//{
////    "push.notification.connection.request" = "%@ möchte sich mit dir verbinden";
////    "push.notification.connection.request.nousername" = "%@"; // uses message text
////    
////    "push.notification.connection.accepted" = "Du bist jetzt mit %@ verbunden";
////    "push.notification.connection.accepted.nousername" = "Du hast einen neuen Kontakt";
//    
//    NSString *accepted = @"accepted";
//    NSString *pending = @"pending";
//    
//    NSDictionary *cases = @{@"Du bist jetzt mit Super User verbunden": @[self.sender, accepted],
//                            @"Du hast einen neuen Kontakt": @[accepted],
//                            @"Super User möchte sich mit dir verbinden": @[self.sender, pending],
//                            @"Please add me": @[pending]};
//    
//    [cases enumerateKeysAndObjectsUsingBlock:^(NSString *expectedAlert, NSArray *arguments, BOOL *stop) {
//        NOT_USED(stop);
//        UILocalNotification *notification;
//        if (arguments.count == 2) {
//            notification = [self noteForConnectionRequestEventTo:arguments[0] status:arguments[1]];
//        } else {
//            notification = [self noteForConnectionRequestEventTo:nil status:arguments[0]];
//        }
//        XCTAssertNotNil(notification);
//        XCTAssertEqualObjects(notification.alertBody, expectedAlert);
//    }];
//}
//
//- (BOOL)checkThatItCreatesConversationCreateNotificationForSender:(ZMUser *)sender exptectedText:(NSString *)expected
//{
//    // when
//    ZMLocalNotificationForEvent *note1 = [self noteWithPayload:nil fromUser:sender inConversation:self.groupConversation type:EventConversationCreate];
//    
//    // then
//    XCTAssertNotNil(note1);
//    
//    XCTAssertNotNil(note1.uiNotifications);
//    UILocalNotification *notification = note1.uiNotifications.lastObject;
//    XCTAssertEqualObjects(notification.alertBody, expected);
//    return [notification.alertBody isEqualToString:expected];
//}
//
//- (void)testThatItCreatesConversationCreateNotification_German
//{
//   //    "push.notification.conversation.create" = "%1$@ hat eine Gruppenunterhaltung mit dir begonnen";
//    
//    // then
//    NSString *expectedAlertText = @"Super User hat eine Gruppenunterhaltung mit dir begonnen";
//    
//    XCTAssertTrue([self checkThatItCreatesConversationCreateNotificationForSender:self.sender exptectedText:expectedAlertText]);
//}
//
//- (void)testThatItCreatesConversationCreateNotification_NoUserName
//{
//    //    "push.notification.conversation.create.nousername" = "Jemand hat eine Gruppenunterhaltung mit dir erstellt";
//    
//    // then
//    NSString *expectedAlertText = @"Jemand hat eine Gruppenunterhaltung mit dir erstellt";
//    XCTAssertTrue([self checkThatItCreatesConversationCreateNotificationForSender:nil exptectedText:expectedAlertText]);
//}
//
//- (BOOL)checkThatItCreatesConversationRenameNotificationsForUser:(ZMUser *)user expectedAlertText:(NSString *)expectedAlertText
//{
//    // given
//    NSDictionary *data1 = @{@"name" : @"New Conversation Name"};
//    
//    // when
//    ZMLocalNotificationForEvent *note1 = [self noteWithPayload:data1 fromUser:user inConversation:self.groupConversation type:EventConversationRename];
//    
//    // then
//    XCTAssertNotNil(note1);
//    XCTAssertNotNil(note1.uiNotifications);
//    UILocalNotification *notification = note1.uiNotifications.lastObject;
//    XCTAssertEqualObjects(notification.alertBody, expectedAlertText);
//
//    return [notification.alertBody isEqualToString:expectedAlertText];
//}
//
//
//- (void)testThatItCreatesConversationRenameNotifications
//{
//    // "push.notification.conversation.rename" = "%1$@ hat die Unterhaltung in %2$@ umbenannt";
//    // then
//    NSString *expectedAlertText = @"Super User hat die Unterhaltung in New Conversation Name umbenannt";
//    
//    XCTAssertTrue([self checkThatItCreatesConversationRenameNotificationsForUser:self.sender expectedAlertText:expectedAlertText]);
//}
//
//- (void)testThatItCreatesConversationRenameNotifications_NoUserName
//{
//    // "push.notification.conversation.rename.nousername" = "Eine Unterhaltung wurde in %1$@ umbenannt";
//
//    // then
//    NSString *expectedAlertText = @"Eine Unterhaltung wurde in New Conversation Name umbenannt";
//    
//    XCTAssertTrue([self checkThatItCreatesConversationRenameNotificationsForUser:nil expectedAlertText:expectedAlertText]);
//}
//
//- (void)testThatItCreatesACallNotification_German
//{
//    // "push.notification.call.started" = "%1$@ wants to talk";
//    // when
//    ZMLocalNotificationForEvent *note1 = [self noteWithPayload:nil fromUser:self.sender inConversation:self.oneOnOneConversation type:EventConversationVoiceChannelActivate];
//    ZMLocalNotificationForEvent *note2 = [self noteWithPayload:nil fromUser:self.sender inConversation:self.groupConversation type:EventConversationVoiceChannelActivate];
//    ZMLocalNotificationForEvent *note3 = [self noteWithPayload:nil fromUser:self.sender inConversation:self.groupConversationWithoutName type:EventConversationVoiceChannelActivate];
//    ZMLocalNotificationForEvent *note4 = [self noteWithPayload:nil fromUser:nil inConversation:self.oneOnOneConversation type:EventConversationVoiceChannelActivate];
//    ZMLocalNotificationForEvent *note5 = [self noteWithPayload:nil fromUser:nil inConversation:self.groupConversation type:EventConversationVoiceChannelActivate];
//    ZMLocalNotificationForEvent *note6 = [self noteWithPayload:nil fromUser:nil inConversation:self.groupConversationWithoutName type:EventConversationVoiceChannelActivate];
//    
//    // then
//    NSString *expectedAlertText1 = @"Super User ruft an";
//    NSString *expectedAlertText2 = @"Super User ruft in Super Conversation an";
//    NSString *expectedAlertText3 = @"Super User ruft in einer Unterhaltung an";
//    NSString *expectedAlertText4 = @"Jemand ruft an";
//    NSString *expectedAlertText5 = @"Jemand ruft in Super Conversation an";
//    NSString *expectedAlertText6 = @"Jemand ruft in einer Unterhaltung an";
//
//    XCTAssertEqualObjects([note1.uiNotifications.lastObject alertBody], expectedAlertText1);
//    XCTAssertEqualObjects([note2.uiNotifications.lastObject alertBody], expectedAlertText2);
//    XCTAssertEqualObjects([note3.uiNotifications.lastObject alertBody], expectedAlertText3);
//    XCTAssertEqualObjects([note4.uiNotifications.lastObject alertBody], expectedAlertText4);
//    XCTAssertEqualObjects([note5.uiNotifications.lastObject alertBody], expectedAlertText5);
//    XCTAssertEqualObjects([note6.uiNotifications.lastObject alertBody], expectedAlertText6);
//}
//
//
//- (void)testThatItCreatesAllMissedCallNotification_German
//{
//    NSDictionary *data = @{@"reason": @"missed"};
//
//    
//    // when
//    ZMLocalNotificationForEvent *note1 = [self noteWithPayload:data fromUser:self.sender inConversation:self.oneOnOneConversation type:EventConversationVoiceChannelDeactivate];
//    ZMLocalNotificationForEvent *note2 = [self noteWithPayload:data fromUser:self.sender inConversation:self.groupConversation type:EventConversationVoiceChannelDeactivate];
//    ZMLocalNotificationForEvent *note3 = [self noteWithPayload:data fromUser:self.sender inConversation:self.groupConversationWithoutName type:EventConversationVoiceChannelDeactivate];
//    ZMLocalNotificationForEvent *note4 = [self noteWithPayload:data fromUser:nil inConversation:self.oneOnOneConversation type:EventConversationVoiceChannelDeactivate];
//    ZMLocalNotificationForEvent *note5 = [self noteWithPayload:data fromUser:nil inConversation:self.groupConversation type:EventConversationVoiceChannelDeactivate];
//    ZMLocalNotificationForEvent *note6 = [self noteWithPayload:data fromUser:nil inConversation:self.groupConversationWithoutName type:EventConversationVoiceChannelDeactivate];
//    
//    // then
//    NSString *expectedAlertText1 = @"Super User hat versucht dich anzurufen";
//    NSString *expectedAlertText2 = @"Super User hat versucht in Super Conversation anzurufen";
//    NSString *expectedAlertText3 = @"Super User hat versucht in einer Unterhaltung anzurufen";
//    NSString *expectedAlertText4 = @"Jemand hat versucht dich anzurufen";
//    NSString *expectedAlertText5 = @"Jemand hat versucht in Super Conversation anzurufen";
//    NSString *expectedAlertText6 = @"Jemand hat versucht in einer Unterhaltung anzurufen";
//    
//    XCTAssertEqualObjects([note1.uiNotifications.lastObject alertBody], expectedAlertText1);
//    XCTAssertEqualObjects([note2.uiNotifications.lastObject alertBody], expectedAlertText2);
//    XCTAssertEqualObjects([note3.uiNotifications.lastObject alertBody], expectedAlertText3);
//    XCTAssertEqualObjects([note4.uiNotifications.lastObject alertBody], expectedAlertText4);
//    XCTAssertEqualObjects([note5.uiNotifications.lastObject alertBody], expectedAlertText5);
//    XCTAssertEqualObjects([note6.uiNotifications.lastObject alertBody], expectedAlertText6);
//}
//
//
//- (ZMLocalNotificationForEvent *)createCopyOfPreviousMissedCallNoteForSender:(ZMUser *)sender inConversation:(ZMConversation *)conversation
//{
//    NSDictionary *data = @{@"reason": @"missed"};
//    ZMLocalNotificationForEvent *original = [self noteWithPayload:data fromUser:sender inConversation:conversation type:EventConversationVoiceChannelDeactivate];
//    
//    return [self copyNote:original withPayload:data fromUser:sender inConversation:conversation type:EventConversationVoiceChannelDeactivate];
//}
//
//- (void)testThatItCopiesMissedCallNotification_German
//{
//    // when
//    ZMLocalNotificationForEvent *note1 = [self createCopyOfPreviousMissedCallNoteForSender:self.sender inConversation:self.oneOnOneConversation];
//    ZMLocalNotificationForEvent *note2 = [self createCopyOfPreviousMissedCallNoteForSender:self.sender inConversation:self.groupConversation];
//    ZMLocalNotificationForEvent *note3 = [self createCopyOfPreviousMissedCallNoteForSender:self.sender inConversation:self.groupConversationWithoutName];
//    ZMLocalNotificationForEvent *note4 = [self createCopyOfPreviousMissedCallNoteForSender:nil inConversation:self.oneOnOneConversation];
//    ZMLocalNotificationForEvent *note5 = [self createCopyOfPreviousMissedCallNoteForSender:nil inConversation:self.groupConversation];
//    ZMLocalNotificationForEvent *note6 = [self createCopyOfPreviousMissedCallNoteForSender:nil inConversation:self.groupConversationWithoutName];
//    
//    // then
//    NSString *expectedAlertText1 = @"Super User hat 2 mal versucht dich anzurufen";
//    NSString *expectedAlertText2 = @"Super User hat 2 mal versucht in Super Conversation anzurufen";
//    NSString *expectedAlertText3 = @"Super User hat 2 mal versucht in einer Unterhaltung anzurufen";
//    NSString *expectedAlertText4 = @"Jemand hat 2 mal versucht dich anzurufen";
//    NSString *expectedAlertText5 = @"Jemand hat 2 mal versucht in Super Conversation anzurufen";
//    NSString *expectedAlertText6 = @"Jemand hat 2 mal versucht in einer Unterhaltung anzurufen";
//    
//    XCTAssertEqualObjects([note1.uiNotifications.lastObject alertBody], expectedAlertText1);
//    XCTAssertEqualObjects([note2.uiNotifications.lastObject alertBody], expectedAlertText2);
//    XCTAssertEqualObjects([note3.uiNotifications.lastObject alertBody], expectedAlertText3);
//    XCTAssertEqualObjects([note4.uiNotifications.lastObject alertBody], expectedAlertText4);
//    XCTAssertEqualObjects([note5.uiNotifications.lastObject alertBody], expectedAlertText5);
//    XCTAssertEqualObjects([note6.uiNotifications.lastObject alertBody], expectedAlertText6);
//}
//
//
//@end
