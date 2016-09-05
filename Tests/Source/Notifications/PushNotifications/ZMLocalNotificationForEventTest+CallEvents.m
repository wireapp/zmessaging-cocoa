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


#import "ZMLocalNotificationForEventTest.h"


@implementation ZMLocalNotificationForEventTest (MissedCall)

- (ZMLocalNotificationForEvent *)callNotificationForConversation:(ZMConversation *)conversation
                                                       otherUser:(ZMUser *)otherUser
                                                 othersAreJoined:(BOOL)othersAreJoined
                                                    selfIsJoined:(BOOL)selfIsJoined
                                                        sequence:(NSNumber *)sequence
                                                         session:(NSString *)session
{
    if (otherUser == nil) {
        otherUser = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        otherUser.remoteIdentifier = [NSUUID UUID];
    }
    if (conversation.conversationType == ZMConversationTypeGroup) {
        [conversation addParticipant:otherUser];
    } else if (conversation.conversationType == ZMConversationTypeOneOnOne) {
        conversation.connection = [ZMConnection insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.connection.to = otherUser;
        conversation.connection.status = ZMConnectionStatusAccepted;
    } else {
        return nil;
    }
    NSMutableArray *joinedUsers = [NSMutableArray array];
    if (selfIsJoined){
        [joinedUsers addObject:self.selfUser];
    }
    if (othersAreJoined) {
        [joinedUsers addObject:otherUser];
    }
    ZMUpdateEvent *event= [self callStateEventInConversation:conversation
                                                 joinedUsers:joinedUsers
                                           videoSendingUsers:conversation.isVideoCall ? joinedUsers : @[]
                                                    sequence:sequence
                                                     session:session];
    XCTAssertNotNil(event);
    
    return [ZMLocalNotificationForEvent notificationForEvent:event managedObjectContext:self.syncMOC application:nil];
}

- (void)testThatItCreatesANotificationWhenTheConversationIsSilenced_CallStartedEevnt
{
    // given
    self.oneOnOneConversation.isSilenced = YES;
    ZMLocalNotificationForEvent *note = [self callNotificationForConversation:self.oneOnOneConversation otherUser:self.sender othersAreJoined:YES selfIsJoined:NO sequence:nil session:nil];
    
    // then
    XCTAssertNotNil(note);
    XCTAssertEqualObjects([note.uiNotifications.lastObject soundName], @"ringing_from_them_long.caf");
    XCTAssertEqualObjects([note.uiNotifications.lastObject category], ZMIncomingCallCategory);
}

- (void)testThatItCreatesANotificationWhenTheConversationIsSilenced_CallEndedEvent
{
    // given
    self.oneOnOneConversation.isSilenced = YES;
    
    // when
    ZMLocalNotificationForEvent *note1 = [self callNotificationForConversation:self.oneOnOneConversation otherUser:self.sender othersAreJoined:YES selfIsJoined:NO sequence:nil session:nil];
    ZMUpdateEvent *event = [self callStateEventInConversation:self.oneOnOneConversation othersAreJoined:NO selfIsJoined:NO otherIsSendingVideo:NO selfIsSendingVideo:NO sequence:nil];
    ZMLocalNotificationForEvent *note2 = [note1 copyByAddingEvent:event];
    
    // then
    XCTAssertNotNil(note2);
    XCTAssertEqualObjects([note2.uiNotifications.lastObject soundName], @"new_message_apns.caf");
    XCTAssertEqualObjects([note2.uiNotifications.lastObject category], ZMMissedCallCategory);
}

- (void)testThatItDoesNotAddCallStartedEventWithSameSessionNumber
{
    // given
    ZMLocalNotificationForEvent *note1 = [self callNotificationForConversation:self.oneOnOneConversation otherUser:self.sender othersAreJoined:YES selfIsJoined:NO sequence:@1 session:@"session1"];
    ZMUpdateEvent *event2 = [self callStateEventInConversation:self.oneOnOneConversation joinedUsers:@[self.sender] videoSendingUsers:@[] sequence:@2 session:@"session1"];
    
    // when
    ZMLocalNotificationForEvent *note2 = [note1 copyByAddingEvent:event2];
    
    // then
    XCTAssertNotNil(note1);
    XCTAssertNil(note2);
}

- (void)testThatItDoesAddsCallStartedEventWithDifferentSessionNumber
{
    // given
    ZMLocalNotificationForEvent *note1 = [self callNotificationForConversation:self.oneOnOneConversation otherUser:self.sender othersAreJoined:YES selfIsJoined:NO sequence:@1 session:@"session1"];
    ZMUpdateEvent *event2 = [self callStateEventInConversation:self.oneOnOneConversation joinedUsers:@[self.sender] videoSendingUsers:@[] sequence:@2 session:@"session2"];
    
    // when
    ZMLocalNotificationForEvent *note2 = [note1 copyByAddingEvent:event2];
    
    // then
    XCTAssertNotNil(note1);
    XCTAssertEqual(note1.uiNotifications.count, 1u);
    XCTAssertNotNil(note2);
    XCTAssertEqual(note2.uiNotifications.count, 1u);
}

- (void)testThatItCanAddACallEndedNotification
{
    ZMLocalNotificationForEvent *note1 = [self callNotificationForConversation:self.oneOnOneConversation otherUser:self.sender othersAreJoined:YES selfIsJoined:NO sequence:@1 session:@"session1"];
    ZMUpdateEvent *event2 = [self callStateEventInConversation:self.oneOnOneConversation joinedUsers:@[] videoSendingUsers:@[] sequence:@2 session:@"session1"];
    
    // when
    ZMLocalNotificationForEvent *note2 = [note1 copyByAddingEvent:event2];
    
    // then
    XCTAssertNotNil(note1);
    XCTAssertEqual(note1.uiNotifications.count, 1u);
    XCTAssertNotNil(note2);
    XCTAssertEqual(note2.uiNotifications.count, 1u);
}

- (void)testThatItCancelsTheNotificationsWhenTheSelfUserJoins
{
    ZMLocalNotificationForEvent *note1 = [self callNotificationForConversation:self.oneOnOneConversation otherUser:self.sender othersAreJoined:YES selfIsJoined:NO sequence:@1 session:@"session1"];
    ZMUpdateEvent *event2 = [self callStateEventInConversation:self.oneOnOneConversation joinedUsers:@[self.sender, self.selfUser] videoSendingUsers:@[] sequence:@2 session:@"session1"];
    
    // when
    ZMLocalNotificationForEvent *note2 = [note1 copyByAddingEvent:event2];
    
    // then
    XCTAssertNotNil(note1);

    XCTAssertNotNil(note2);
    XCTAssertEqual(note2.uiNotifications.count, 0u);
}


- (void)testThatAfterJoiningItDoesNotCreateACallEndedNotificationForTheSameSession
{
    ZMLocalNotificationForEvent *note1 = [self callNotificationForConversation:self.oneOnOneConversation otherUser:self.sender othersAreJoined:YES selfIsJoined:NO sequence:@1 session:@"session1"];
    ZMUpdateEvent *event2 = [self callStateEventInConversation:self.oneOnOneConversation joinedUsers:@[self.sender, self.selfUser] videoSendingUsers:@[] sequence:@2 session:@"session1"];
    ZMLocalNotificationForEvent *note2 = [note1 copyByAddingEvent:event2];

    ZMUpdateEvent *event3 = [self callStateEventInConversation:self.oneOnOneConversation joinedUsers:@[] videoSendingUsers:@[] sequence:@2 session:@"session1"];
    
    // when
    ZMLocalNotificationForEvent *note3 = [note2 copyByAddingEvent:event3];

    // then
    XCTAssertNotNil(note1);
    XCTAssertNotNil(note2);
    XCTAssertEqual(note2.uiNotifications.count, 0u);

    XCTAssertNil(note3);
}

- (void)testThatAfterJoiningItCreatesACallEndedNotificationForADifferentSession
{
    ZMLocalNotificationForEvent *note1 = [self callNotificationForConversation:self.groupConversation otherUser:self.sender othersAreJoined:YES selfIsJoined:NO sequence:@1 session:@"session1"];
    ZMUpdateEvent *event2 = [self callStateEventInConversation:self.groupConversation joinedUsers:@[self.sender, self.selfUser] videoSendingUsers:@[] sequence:@2 session:@"session1"];
    ZMLocalNotificationForEvent *note2 = [note1 copyByAddingEvent:event2];
    
    ZMUpdateEvent *event3 = [self callStateEventInConversation:self.groupConversation joinedUsers:@[] videoSendingUsers:@[] sequence:@2 session:@"session2"];
    
    // when
    ZMLocalNotificationForEvent *note3 = [note2 copyByAddingEvent:event3];
    
    // then
    XCTAssertNotNil(note1);
    XCTAssertEqual(note1.uiNotifications.count, 1u);
    
    XCTAssertNotNil(note2);
    XCTAssertEqual(note2.uiNotifications.count, 0u);

    XCTAssertNotNil(note3);
    XCTAssertEqual(note3.uiNotifications.count, 1u);
    UILocalNotification *lastNote = note3.uiNotifications.firstObject;
    XCTAssertEqualObjects(lastNote.alertBody, @"Someone called in Super Conversation");
    
}

- (void)testThatItDoesNotCreateACallNotificationWhenTheSendingUserTogglesTheVideoOnAndOff
{
    ZMLocalNotificationForEvent *note1 = [self callNotificationForConversation:self.oneOnOneConversation otherUser:self.sender othersAreJoined:YES selfIsJoined:NO sequence:@1 session:@"session1"];
    
    // when user toggles video on
    ZMUpdateEvent *event2 = [self callStateEventInConversation:self.oneOnOneConversation joinedUsers:@[self.sender] videoSendingUsers:@[self.sender] sequence:@2 session:@"session1"];
    ZMLocalNotificationForEvent *note2 = [note1 copyByAddingEvent:event2];
    
    // when user toggles video off
    ZMUpdateEvent *event3 = [self callStateEventInConversation:self.oneOnOneConversation joinedUsers:@[self.sender] videoSendingUsers:@[] sequence:@2 session:@"session1"];
    ZMLocalNotificationForEvent *note3 = [note1 copyByAddingEvent:event3];
    
    // then
    XCTAssertNotNil(note1);
    XCTAssertEqual(note1.uiNotifications.count, 1u);
    XCTAssertNil(note2);
    XCTAssertNil(note3);
}

- (void)testThatItDoesNotCreateACallNotificationWhenTheSendingUserTogglesTheVideoOnAndOff_AfterJoining
{
    ZMLocalNotificationForEvent *note1 = [self callNotificationForConversation:self.oneOnOneConversation otherUser:self.sender othersAreJoined:YES selfIsJoined:NO sequence:@1 session:@"session1"];
    
    // when user toggles video on
    ZMUpdateEvent *event2 = [self callStateEventInConversation:self.oneOnOneConversation joinedUsers:@[self.sender, self.selfUser] videoSendingUsers:@[] sequence:@2 session:@"session1"];
    ZMLocalNotificationForEvent *note2 = [note1 copyByAddingEvent:event2];
    
    // when user toggles video off
    ZMUpdateEvent *event3 = [self callStateEventInConversation:self.oneOnOneConversation joinedUsers:@[self.sender, self.selfUser] videoSendingUsers:@[self.sender] sequence:@2 session:@"session1"];
    ZMLocalNotificationForEvent *note3 = [note2 copyByAddingEvent:event3];
    
    // then
    XCTAssertNotNil(note1);
    XCTAssertEqual(note1.uiNotifications.count, 1u);
    
    XCTAssertNotNil(note2);
    XCTAssertEqual(note2.uiNotifications.count, 0u);

    XCTAssertNil(note3);
}

- (void)testThatItDoesNotCreateANotificationWhenMoreUsersAreJoining
{
    // first user joins
    ZMUpdateEvent *event1 = [self callStateEventInConversation:self.groupConversation joinedUsers:@[self.sender] videoSendingUsers:@[] sequence:@2 session:@"session1"];
    ZMLocalNotificationForEvent *note1 = [ZMLocalNotificationForEvent notificationForEvent:event1 managedObjectContext:self.syncMOC application:nil];
    
    // when second user joins
    ZMUpdateEvent *event2 = [self callStateEventInConversation:self.groupConversation joinedUsers:@[self.sender, self.otherUser] videoSendingUsers:@[] sequence:@2 session:@"session1"];
    ZMLocalNotificationForEvent *note2 = [note1 copyByAddingEvent:event2];
    
    // then
    XCTAssertNotNil(note1);
    XCTAssertEqual(note1.uiNotifications.count, 1u);
    XCTAssertNil(note2);
}

- (void)testThatItDoesNotCreateANotificationWhenUsersAreJoiningAfterSelfUserJoined
{
    // first user joins
    ZMUpdateEvent *event1 = [self callStateEventInConversation:self.groupConversation joinedUsers:@[self.sender] videoSendingUsers:@[] sequence:@2 session:@"session1"];
    ZMLocalNotificationForEvent *note1 = [ZMLocalNotificationForEvent notificationForEvent:event1 managedObjectContext:self.syncMOC application:nil];
    
    // when selfUser joins
    ZMUpdateEvent *event2 = [self callStateEventInConversation:self.groupConversation joinedUsers:@[self.sender, self.selfUser] videoSendingUsers:@[] sequence:@2 session:@"session1"];
    ZMLocalNotificationForEvent *note2 = [note1 copyByAddingEvent:event2];
    
    // when second user joins
    ZMUpdateEvent *event3 = [self callStateEventInConversation:self.groupConversation joinedUsers:@[self.sender, self.selfUser, self.otherUser] videoSendingUsers:@[] sequence:@2 session:@"session1"];
    ZMLocalNotificationForEvent *note3 = [note2 copyByAddingEvent:event3];
    
    // then
    XCTAssertNotNil(note1);
    XCTAssertEqual(note1.uiNotifications.count, 1u);
    
    XCTAssertNotNil(note2);
    XCTAssertEqual(note2.uiNotifications.count, 0u);

    XCTAssertNil(note3);
}

- (void)testThatItDoesNotCreateANotificationWhenUsersAreJoiningAfterSelfUserJoinedAndLeft
{
    // first user joins
    ZMUpdateEvent *event1 = [self callStateEventInConversation:self.groupConversation joinedUsers:@[self.sender] videoSendingUsers:@[] sequence:@2 session:@"session1"];
    ZMLocalNotificationForEvent *note1 = [ZMLocalNotificationForEvent notificationForEvent:event1 managedObjectContext:self.syncMOC application:mockApplication];
    
    // when selfUser joins
    [[mockApplication expect] cancelLocalNotification:OCMOCK_ANY];
    
    ZMUpdateEvent *event2 = [self callStateEventInConversation:self.groupConversation joinedUsers:@[self.sender, self.selfUser] videoSendingUsers:@[] sequence:@2 session:@"session1"];
    ZMLocalNotificationForEvent *note2 = [note1 copyByAddingEvent:event2];
    
    // when selfUser leaves
    ZMUpdateEvent *event3 = [self callStateEventInConversation:self.groupConversation joinedUsers:@[self.sender] videoSendingUsers:@[] sequence:@2 session:@"session1"];
    ZMLocalNotificationForEvent *note3 = [note2 copyByAddingEvent:event3];
    
    // when second user joins
    ZMUpdateEvent *event4 = [self callStateEventInConversation:self.groupConversation joinedUsers:@[self.sender, self.otherUser] videoSendingUsers:@[] sequence:@2 session:@"session1"];
    ZMLocalNotificationForEvent *note4 = [note2 copyByAddingEvent:event4];
    
    // then
    XCTAssertNotNil(note1);
    XCTAssertEqual(note1.uiNotifications.count, 1u);
    
    XCTAssertNotNil(note2);
    XCTAssertEqual(note2.uiNotifications.count, 0u);

    XCTAssertNil(note3);
    XCTAssertNil(note4);
}


- (void)testThatItUsesFirstSenderIDForCallEndedEvent
{
    // first user joins
    ZMUpdateEvent *event1 = [self callStateEventInConversation:self.groupConversation joinedUsers:@[self.sender] videoSendingUsers:@[] sequence:@2 session:@"session1"];
    ZMLocalNotificationForEvent *note1 = [ZMLocalNotificationForEvent notificationForEvent:event1 managedObjectContext:self.syncMOC application:nil];
    
    // then
    XCTAssertNotNil(note1);
    XCTAssertEqual(note1.uiNotifications.count, 1u);
    UILocalNotification *firstNote = note1.uiNotifications.firstObject;
    XCTAssertEqualObjects(firstNote.alertBody, @"Super User is calling in Super Conversation");
    
    
    // when other user joins
    ZMUpdateEvent *event2 = [self callStateEventInConversation:self.groupConversation joinedUsers:@[self.otherUser, self.sender] videoSendingUsers:@[] sequence:@2 session:@"session1"];
    ZMLocalNotificationForEvent *note2 = [note1 copyByAddingEvent:event2];
    
    // then
    XCTAssertNil(note2);

    
    // when all user leave
    ZMUpdateEvent *event3 = [self callStateEventInConversation:self.groupConversation joinedUsers:@[] videoSendingUsers:@[] sequence:@2 session:@"session1"];
    ZMLocalNotificationForEvent *note3 = [note1 copyByAddingEvent:event3];
    
    // then
    XCTAssertNotNil(note3);
    XCTAssertEqual(note3.uiNotifications.count, 1u);
    UILocalNotification *lastNote = note3.uiNotifications.firstObject;
    XCTAssertEqualObjects(lastNote.alertBody, @"Super User called in Super Conversation");
}


- (void)testThatItUsesUnknownSenderIfSenderBelongsToDifferentSession
{
    // first user joins
    ZMUpdateEvent *event1 = [self callStateEventInConversation:self.groupConversation joinedUsers:@[self.sender] videoSendingUsers:@[] sequence:@2 session:@"session1"];
    ZMLocalNotificationForEvent *note1 = [ZMLocalNotificationForEvent notificationForEvent:event1 managedObjectContext:self.syncMOC application:nil];
    
    // then
    XCTAssertNotNil(note1);
    XCTAssertEqual(note1.uiNotifications.count, 1u);
    UILocalNotification *firstNote = note1.uiNotifications.firstObject;
    XCTAssertEqualObjects(firstNote.alertBody, @"Super User is calling in Super Conversation");
    
    
    // when other user joins
    ZMUpdateEvent *event2 = [self callStateEventInConversation:self.groupConversation joinedUsers:@[self.otherUser, self.sender] videoSendingUsers:@[] sequence:@2 session:@"session1"];
    ZMLocalNotificationForEvent *note2 = [note1 copyByAddingEvent:event2];
    
    // then
    XCTAssertNil(note2);
    
    
    // when all user leave
    ZMUpdateEvent *event3 = [self callStateEventInConversation:self.groupConversation joinedUsers:@[] videoSendingUsers:@[] sequence:@2 session:@"session2"];
    ZMLocalNotificationForEvent *note3 = [note1 copyByAddingEvent:event3];
    
    // then
    XCTAssertNotNil(note3);
    XCTAssertEqual(note3.uiNotifications.count, 1u);
    UILocalNotification *lastNote = note3.uiNotifications.firstObject;
    XCTAssertEqualObjects(lastNote.alertBody, @"Someone called in Super Conversation");
}

- (void)testThatItDoesNotCreateANotificationWhenTheSelfUserStartsAndCancelsACall
{
    // first selfuser joins
    ZMUpdateEvent *event1 = [self callStateEventInConversation:self.groupConversation joinedUsers:@[self.selfUser] videoSendingUsers:@[] sequence:@2 session:@"session1"];
    ZMLocalNotificationForEvent *note1 = [ZMLocalNotificationForEvent notificationForEvent:event1 managedObjectContext:self.syncMOC application:nil];
    
    // then
    XCTAssertNotNil(note1);
    XCTAssertEqual(note1.uiNotifications.count, 0u);
    
    // when selfuser leaves
    ZMUpdateEvent *event2 = [self callStateEventInConversation:self.groupConversation joinedUsers:@[] videoSendingUsers:@[] sequence:@2 session:@"session1"];
    ZMLocalNotificationForEvent *note2 = [note1 copyByAddingEvent:event2];
    
    // then
    XCTAssertNil(note2);
}

- (void)testThatItCreatesSetsTheCorrectBody_CallStartedNotification_SenderKnown
{
    // "push.notification.call.started" = "%1$@ wants to talk";
    // when
    ZMLocalNotificationForEvent *note1 = [self callNotificationForConversation:self.oneOnOneConversation otherUser:self.sender othersAreJoined:YES selfIsJoined:NO sequence:nil session:nil];
    ZMLocalNotificationForEvent *note2 = [self callNotificationForConversation:self.groupConversation otherUser:self.sender othersAreJoined:YES selfIsJoined:NO sequence:nil session:nil];
    ZMLocalNotificationForEvent *note3 = [self callNotificationForConversation:self.groupConversationWithoutName otherUser:self.sender othersAreJoined:YES selfIsJoined:NO sequence:nil session:nil];
    
    // then
    XCTAssertEqualObjects([note1.uiNotifications.lastObject alertBody], @"Super User is calling");
    XCTAssertEqualObjects([note2.uiNotifications.lastObject alertBody], @"Super User is calling in Super Conversation");
    XCTAssertEqualObjects([note3.uiNotifications.lastObject alertBody], @"Super User is calling in a conversation");
}

- (void)testThatItCreatesSetsTheCorrectBody_CallStartedNotification_SenderUnKnown
{
    // "push.notification.call.started" = "%1$@ wants to talk";
    // when
    ZMLocalNotificationForEvent *note4 = [self callNotificationForConversation:self.oneOnOneConversation otherUser:nil othersAreJoined:YES selfIsJoined:NO sequence:nil session:nil];
    ZMLocalNotificationForEvent *note5 = [self callNotificationForConversation:self.groupConversation otherUser:nil othersAreJoined:YES selfIsJoined:NO sequence:nil session:nil];
    ZMLocalNotificationForEvent *note6 = [self callNotificationForConversation:self.groupConversationWithoutName otherUser:nil othersAreJoined:YES selfIsJoined:NO sequence:nil session:nil];
    
    // then
    XCTAssertEqualObjects([note4.uiNotifications.lastObject alertBody], @"Someone is calling");
    XCTAssertEqualObjects([note5.uiNotifications.lastObject alertBody], @"Someone is calling in Super Conversation");
    XCTAssertEqualObjects([note6.uiNotifications.lastObject alertBody], @"Someone is calling in a conversation");
}

- (void)testThatItCreatesSetsTheCorrectBody_CallStartedNotification_SenderKnown_Video
{
    // "push.notification.call.started" = "%1$@ wants to talk";
    // when
    self.oneOnOneConversation.isVideoCall = YES;
    self.groupConversationWithoutName.isVideoCall = YES;
    self.groupConversation.isVideoCall = YES;
    ZMLocalNotificationForEvent *note7 = [self callNotificationForConversation:self.oneOnOneConversation otherUser:self.sender othersAreJoined:YES selfIsJoined:NO sequence:nil session:nil];
    ZMLocalNotificationForEvent *note8 = [self callNotificationForConversation:self.groupConversation otherUser:self.sender othersAreJoined:YES selfIsJoined:NO sequence:nil session:nil];
    ZMLocalNotificationForEvent *note9 = [self callNotificationForConversation:self.groupConversationWithoutName otherUser:self.sender othersAreJoined:YES selfIsJoined:NO sequence:nil session:nil];
    
    // then
    XCTAssertEqualObjects([note7.uiNotifications.lastObject alertBody], @"Super User is video calling");
    XCTAssertEqualObjects([note8.uiNotifications.lastObject alertBody], @"Super User is video calling in Super Conversation");
    XCTAssertEqualObjects([note9.uiNotifications.lastObject alertBody], @"Super User is video calling in a conversation");
}

- (void)testThatItCreatesSetsTheCorrectBody_CallEndedNotification_SenderKnown
{
    // "push.notification.call.started" = "%1$@ wants to talk";
    // when
    ZMLocalNotificationForEvent *note01 = [self callNotificationForConversation:self.oneOnOneConversation otherUser:self.sender othersAreJoined:YES selfIsJoined:NO sequence:nil session:nil];
    ZMUpdateEvent *event1 = [self callStateEventInConversation:self.oneOnOneConversation othersAreJoined:NO selfIsJoined:NO otherIsSendingVideo:NO selfIsSendingVideo:NO sequence:nil];
    ZMLocalNotificationForEvent *note1 = [note01 copyByAddingEvent:event1];
    
    ZMLocalNotificationForEvent *note02 = [self callNotificationForConversation:self.groupConversation otherUser:self.sender othersAreJoined:YES selfIsJoined:NO sequence:nil session:nil];
    ZMUpdateEvent *event2 = [self callStateEventInConversation:self.groupConversation othersAreJoined:NO selfIsJoined:NO otherIsSendingVideo:NO selfIsSendingVideo:NO sequence:nil];
    ZMLocalNotificationForEvent *note2 = [note02 copyByAddingEvent:event2];
    
    ZMLocalNotificationForEvent *note03 = [self callNotificationForConversation:self.groupConversationWithoutName otherUser:self.sender othersAreJoined:YES selfIsJoined:NO sequence:nil session:nil];
    ZMUpdateEvent *event3 = [self callStateEventInConversation:self.groupConversationWithoutName othersAreJoined:NO selfIsJoined:NO otherIsSendingVideo:NO selfIsSendingVideo:NO sequence:nil];
    ZMLocalNotificationForEvent *note3 = [note03 copyByAddingEvent:event3];
    
    // then
    XCTAssertEqualObjects([note1.uiNotifications.lastObject alertBody], @"Super User called");
    XCTAssertEqualObjects([note2.uiNotifications.lastObject alertBody], @"Super User called in Super Conversation");
    XCTAssertEqualObjects([note3.uiNotifications.lastObject alertBody], @"Super User called in a conversation");
}

- (void)testThatItCreatesSetsTheCorrectBody_CallEndedNotification_SenderUnKnown
{
    // "push.notification.call.started" = "%1$@ wants to talk";
    // when
    ZMLocalNotificationForEvent *note01 = [self callNotificationForConversation:self.oneOnOneConversation otherUser:nil othersAreJoined:YES selfIsJoined:NO sequence:nil session:nil];
    ZMUpdateEvent *event1 = [self callStateEventInConversation:self.oneOnOneConversation othersAreJoined:NO selfIsJoined:NO otherIsSendingVideo:NO selfIsSendingVideo:NO sequence:nil];
    ZMLocalNotificationForEvent *note1 = [note01 copyByAddingEvent:event1];
    
    ZMLocalNotificationForEvent *note02 = [self callNotificationForConversation:self.groupConversation otherUser:nil othersAreJoined:YES selfIsJoined:NO sequence:nil session:nil];
    ZMUpdateEvent *event2 = [self callStateEventInConversation:self.groupConversation othersAreJoined:NO selfIsJoined:NO otherIsSendingVideo:NO selfIsSendingVideo:NO sequence:nil];
    ZMLocalNotificationForEvent *note2 = [note02 copyByAddingEvent:event2];
    
    ZMLocalNotificationForEvent *note03 = [self callNotificationForConversation:self.groupConversationWithoutName otherUser:nil othersAreJoined:YES selfIsJoined:NO sequence:nil session:nil];
    ZMUpdateEvent *event3 = [self callStateEventInConversation:self.groupConversationWithoutName othersAreJoined:NO selfIsJoined:NO otherIsSendingVideo:NO selfIsSendingVideo:NO sequence:nil];
    ZMLocalNotificationForEvent *note3 = [note03 copyByAddingEvent:event3];
    
    // then
    XCTAssertEqualObjects([note1.uiNotifications.lastObject alertBody], @"Someone called");
    XCTAssertEqualObjects([note2.uiNotifications.lastObject alertBody], @"Someone called in Super Conversation");
    XCTAssertEqualObjects([note3.uiNotifications.lastObject alertBody], @"Someone called in a conversation");
}

@end

