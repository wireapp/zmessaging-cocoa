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

@import zmessaging;

#import "ZMLocalNotificationForEventTest.h"
#import "zmessaging_iOS_Tests-Swift.h"

@interface ZMLocalNotificationForCallEventTest : ZMLocalNotificationForEventTest

@property (nonatomic) SessionTracker *sessionTracker;

@end


@implementation ZMLocalNotificationForCallEventTest

- (void)setUp {
    [super setUp];
    self.sessionTracker = [[SessionTracker alloc] initWithManagedObjectContext:self.syncMOC];
}

- (void)tearDown {
    [self.sessionTracker tearDown];
    self.sessionTracker = nil;
    [super tearDown];
}

- (ZMLocalNotificationForCallEvent *)callNotificationForConversation:(ZMConversation *)conversation
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
    [self.sessionTracker addEvent:event];
    return (id)[ZMLocalNotificationForEvent notificationForEvent:event conversation:conversation managedObjectContext:self.syncMOC application:self.application sessionTracker:self.sessionTracker];
}

- (void)testThatItCreatesANotificationWhenTheConversationIsSilenced_CallStartedEevnt
{
    // given
    self.oneOnOneConversation.isSilenced = YES;
    ZMLocalNotificationForEvent *note = [self callNotificationForConversation:self.oneOnOneConversation otherUser:self.sender othersAreJoined:YES selfIsJoined:NO sequence:nil session:@"session1"];
    
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
    ZMLocalNotificationForCallEvent *note1 = [self callNotificationForConversation:self.oneOnOneConversation otherUser:self.sender othersAreJoined:YES selfIsJoined:NO sequence:@1 session:@"session1"];
    ZMUpdateEvent *event = [self callStateEventInConversation:self.oneOnOneConversation joinedUsers:@[] videoSendingUsers:@[] sequence:@2 session:@"session1"];
    [self.sessionTracker addEvent:event];
    XCTAssertNotNil(note1);
    ZMLocalNotificationForEvent *note2 = [note1 copyByAddingEvent:event conversation:self.oneOnOneConversation];
    
    // then
    XCTAssertNotNil(note2);
    XCTAssertEqualObjects([note2.uiNotifications.lastObject soundName], @"new_message_apns.caf");
    XCTAssertEqualObjects([note2.uiNotifications.lastObject category], ZMMissedCallCategory);
}

- (void)testThatItDoesNotAddCallStartedEventWithSameSessionNumber
{
    // given
    ZMLocalNotificationForCallEvent *note1 = [self callNotificationForConversation:self.oneOnOneConversation otherUser:self.sender othersAreJoined:YES selfIsJoined:NO sequence:@1 session:@"session1"];
    ZMUpdateEvent *event2 = [self callStateEventInConversation:self.oneOnOneConversation joinedUsers:@[self.sender] videoSendingUsers:@[] sequence:@2 session:@"session1"];
    [self.sessionTracker addEvent:event2];

    // when
    ZMLocalNotificationForEvent *note2 = [note1 copyByAddingEvent:event2 conversation:self.oneOnOneConversation];
    
    // then
    XCTAssertNotNil(note1);
    XCTAssertNil(note2);
}

- (void)testThatItDoesAddsCallStartedEventWithDifferentSessionNumber
{
    // given
    ZMLocalNotificationForCallEvent *note1 = [self callNotificationForConversation:self.oneOnOneConversation otherUser:self.sender othersAreJoined:YES selfIsJoined:NO sequence:@1 session:@"session1"];
    ZMUpdateEvent *event2 = [self callStateEventInConversation:self.oneOnOneConversation joinedUsers:@[self.sender] videoSendingUsers:@[] sequence:@2 session:@"session2"];
    [self.sessionTracker addEvent:event2];

    // when
    ZMLocalNotificationForEvent *note2 = [note1 copyByAddingEvent:event2 conversation:self.oneOnOneConversation];
    
    // then
    XCTAssertNotNil(note1);
    XCTAssertEqual(note1.uiNotifications.count, 1u);
    XCTAssertNotNil(note2);
    XCTAssertEqual(note2.uiNotifications.count, 1u);
}

- (void)testThatItCanAddACallEndedNotification
{
    ZMLocalNotificationForCallEvent *note1 = [self callNotificationForConversation:self.oneOnOneConversation otherUser:self.sender othersAreJoined:YES selfIsJoined:NO sequence:@1 session:@"session1"];
    ZMUpdateEvent *event2 = [self callStateEventInConversation:self.oneOnOneConversation joinedUsers:@[] videoSendingUsers:@[] sequence:@2 session:@"session1"];
    [self.sessionTracker addEvent:event2];

    // when
    ZMLocalNotificationForEvent *note2 = [note1 copyByAddingEvent:event2 conversation:self.oneOnOneConversation];
    
    // then
    XCTAssertNotNil(note1);
    XCTAssertEqual(note1.uiNotifications.count, 1u);
    XCTAssertNotNil(note2);
    XCTAssertEqual(note2.uiNotifications.count, 1u);
}

- (void)testThatItCancelsTheNotificationsWhenTheSelfUserJoins
{
    ZMLocalNotificationForCallEvent *note1 = [self callNotificationForConversation:self.oneOnOneConversation otherUser:self.sender othersAreJoined:YES selfIsJoined:NO sequence:@1 session:@"session1"];
    ZMUpdateEvent *event2 = [self callStateEventInConversation:self.oneOnOneConversation joinedUsers:@[self.sender, self.selfUser] videoSendingUsers:@[] sequence:@2 session:@"session1"];
    [self.sessionTracker addEvent:event2];

    // when
    ZMLocalNotificationForEvent *note2 = [note1 copyByAddingEvent:event2 conversation:self.oneOnOneConversation];
    
    // then
    XCTAssertNotNil(note1);
    XCTAssertTrue(note1.shouldBeDiscarded);
    XCTAssertNil(note2);
}


- (void)testThatAfterJoiningItDoesNotCreateACallEndedNotificationForTheSameSession
{
    ZMLocalNotificationForCallEvent *note1 = [self callNotificationForConversation:self.oneOnOneConversation otherUser:self.sender othersAreJoined:YES selfIsJoined:NO sequence:@1 session:@"session1"];
    
    // The self user joins
    ZMUpdateEvent *event2 = [self callStateEventInConversation:self.oneOnOneConversation joinedUsers:@[self.sender, self.selfUser] videoSendingUsers:@[] sequence:@2 session:@"session1"];
    [self.sessionTracker addEvent:event2];

    ZMLocalNotificationForCallEvent *note1Copy = [note1 copyByAddingEvent:event2 conversation:self.oneOnOneConversation];
    ZMLocalNotificationForCallEvent *note2 = (id)[ZMLocalNotificationForEvent notificationForEvent:event2 conversation:self.oneOnOneConversation managedObjectContext:self.syncMOC application:self.application sessionTracker:self.sessionTracker];
    
    // then
    XCTAssertNotNil(note1);
    XCTAssertTrue(note1.shouldBeDiscarded);
    XCTAssertNil(note1Copy);
    XCTAssertNil(note2);

    
    // and when
    ZMUpdateEvent *event3 = [self callStateEventInConversation:self.oneOnOneConversation joinedUsers:@[] videoSendingUsers:@[] sequence:@3 session:@"session1"];
    [self.sessionTracker addEvent:event3];

    // when
    ZMLocalNotificationForCallEvent *note3 = (id)[ZMLocalNotificationForEvent notificationForEvent:event3 conversation:self.oneOnOneConversation managedObjectContext:self.syncMOC application:self.application sessionTracker:self.sessionTracker];

    // then
    XCTAssertNil(note3);
}

- (void)testThatAfterJoiningItCreatesACallEndedNotificationForADifferentSession
{
    ZMLocalNotificationForCallEvent *note1 = [self callNotificationForConversation:self.groupConversation otherUser:self.sender othersAreJoined:YES selfIsJoined:NO sequence:@1 session:@"session1"];
    XCTAssertNotNil(note1);
    XCTAssertEqual(note1.uiNotifications.count, 1u);
    
    // when self user joins
    ZMUpdateEvent *event2 = [self callStateEventInConversation:self.groupConversation joinedUsers:@[self.sender, self.selfUser] videoSendingUsers:@[] sequence:@2 session:@"session1"];
    [self.sessionTracker addEvent:event2];
    ZMLocalNotificationForCallEvent *note2 = [note1 copyByAddingEvent:event2 conversation:self.groupConversation];

    // then
    XCTAssertNotNil(note1);
    XCTAssertTrue(note1.shouldBeDiscarded);
    XCTAssertNil(note2);

    
    // and when second session in same conversation
    ZMUpdateEvent *event3 = [self callStateEventInConversation:self.groupConversation joinedUsers:@[] videoSendingUsers:@[] sequence:@2 session:@"session2"];
    [self.sessionTracker addEvent:event3];
    ZMLocalNotificationForCallEvent *note3 = (id)[ZMLocalNotificationForEvent notificationForEvent:event3 conversation:self.groupConversation managedObjectContext:self.syncMOC application:self.application sessionTracker:self.sessionTracker];
    
    // then
    XCTAssertNotNil(note3);
    XCTAssertEqual(note3.uiNotifications.count, 1u);
    UILocalNotification *lastNote = note3.uiNotifications.firstObject;
    XCTAssertEqualObjects(lastNote.alertBody, @"Someone called in Super Conversation");
    
}

- (void)testThatItDoesNotCreateACallNotificationWhenTheSendingUserTogglesTheVideoOnAndOff
{
    ZMLocalNotificationForCallEvent *note1 = [self callNotificationForConversation:self.oneOnOneConversation otherUser:self.sender othersAreJoined:YES selfIsJoined:NO sequence:@1 session:@"session1"];
    
    // when user toggles video on
    ZMUpdateEvent *event2 = [self callStateEventInConversation:self.oneOnOneConversation joinedUsers:@[self.sender] videoSendingUsers:@[self.sender] sequence:@2 session:@"session1"];
    [self.sessionTracker addEvent:event2];
    ZMLocalNotificationForCallEvent *note2 = [note1 copyByAddingEvent:event2 conversation:self.oneOnOneConversation];
    
    // when user toggles video off
    ZMUpdateEvent *event3 = [self callStateEventInConversation:self.oneOnOneConversation joinedUsers:@[self.sender] videoSendingUsers:@[] sequence:@3 session:@"session1"];
    [self.sessionTracker addEvent:event3];
    ZMLocalNotificationForEvent *note3 = [note1 copyByAddingEvent:event3 conversation:self.oneOnOneConversation];
    
    // then
    XCTAssertNotNil(note1);
    XCTAssertEqual(note1.uiNotifications.count, 1u);
    XCTAssertNil(note2);
    XCTAssertNil(note3);
}

- (void)testThatItDoesNotCreateACallNotificationWhenTheSendingUserTogglesTheVideoOnAndOff_AfterJoining
{
    ZMLocalNotificationForCallEvent *note1 = [self callNotificationForConversation:self.oneOnOneConversation otherUser:self.sender othersAreJoined:YES selfIsJoined:NO sequence:@1 session:@"session1"];
    XCTAssertNotNil(note1);
    XCTAssertEqual(note1.uiNotifications.count, 1u);
    
    // when user toggles video on
    ZMUpdateEvent *event2 = [self callStateEventInConversation:self.oneOnOneConversation joinedUsers:@[self.sender, self.selfUser] videoSendingUsers:@[] sequence:@2 session:@"session1"];
    [self.sessionTracker addEvent:event2];
    ZMLocalNotificationForCallEvent *note2 = [note1 copyByAddingEvent:event2 conversation:self.oneOnOneConversation];
    
    // then
    XCTAssertNil(note2);

    // when user toggles video off
    ZMUpdateEvent *event3 = [self callStateEventInConversation:self.oneOnOneConversation joinedUsers:@[self.sender, self.selfUser] videoSendingUsers:@[self.sender] sequence:@2 session:@"session1"];
    [self.sessionTracker addEvent:event2];
    ZMLocalNotificationForEvent *note3 = [note2 copyByAddingEvent:event3 conversation:self.oneOnOneConversation];
    
    // then
    XCTAssertNil(note3);
}

- (void)testThatItDoesNotCreateANotificationWhenMoreUsersAreJoining
{
    // first user joins
    ZMUpdateEvent *event1 = [self callStateEventInConversation:self.groupConversation joinedUsers:@[self.sender] videoSendingUsers:@[] sequence:@2 session:@"session1"];
    [self.sessionTracker addEvent:event1];
    ZMLocalNotificationForCallEvent *note1 = (id)[ZMLocalNotificationForEvent notificationForEvent:event1 conversation:self.groupConversation managedObjectContext:self.syncMOC application:self.application sessionTracker:self.sessionTracker];
    
    // when second user joins
    ZMUpdateEvent *event2 = [self callStateEventInConversation:self.groupConversation joinedUsers:@[self.sender, self.otherUser] videoSendingUsers:@[] sequence:@2 session:@"session1"];
    [self.sessionTracker addEvent:event2];
    ZMLocalNotificationForEvent *note1Copy = [note1 copyByAddingEvent:event2  conversation:self.oneOnOneConversation];
    ZMLocalNotificationForCallEvent *note2 = (id)[ZMLocalNotificationForEvent notificationForEvent:event2 conversation:self.oneOnOneConversation managedObjectContext:self.syncMOC application:self.application sessionTracker:self.sessionTracker];

    // then
    XCTAssertNotNil(note1);
    XCTAssertEqual(note1.uiNotifications.count, 1u);
    XCTAssertNil(note1Copy);
    XCTAssertNil(note2);
}

- (void)testThatItDoesNotCreateANotificationWhenUsersAreJoiningAfterSelfUserJoined
{
    // first user joins
    ZMUpdateEvent *event1 = [self callStateEventInConversation:self.groupConversation joinedUsers:@[self.sender] videoSendingUsers:@[] sequence:@1 session:@"session1"];
    [self.sessionTracker addEvent:event1];

    ZMLocalNotificationForCallEvent *note1 = (id)[ZMLocalNotificationForEvent notificationForEvent:event1 conversation:self.groupConversation managedObjectContext:self.syncMOC application:self.application sessionTracker:self.sessionTracker];
    
    // then
    XCTAssertNotNil(note1);
    XCTAssertEqual(note1.uiNotifications.count, 1u);

    
    // when selfUser joins
    ZMUpdateEvent *event2 = [self callStateEventInConversation:self.groupConversation joinedUsers:@[self.sender, self.selfUser] videoSendingUsers:@[] sequence:@2 session:@"session1"];
    [self.sessionTracker addEvent:event2];
    ZMLocalNotificationForCallEvent *note2 = [note1 copyByAddingEvent:event2  conversation:self.groupConversation];
    
    // then
    XCTAssertEqual(note1.uiNotifications.count, 0u);
    XCTAssertTrue(note1.shouldBeDiscarded);
    XCTAssertNil(note2);
    
    // when second user joins
    ZMUpdateEvent *event3 = [self callStateEventInConversation:self.groupConversation joinedUsers:@[self.sender, self.selfUser, self.otherUser] videoSendingUsers:@[] sequence:@3 session:@"session1"];
    [self.sessionTracker addEvent:event3];
    ZMLocalNotificationForCallEvent *note3 = (id)[ZMLocalNotificationForEvent notificationForEvent:event3  conversation:self.groupConversation managedObjectContext:self.syncMOC application:self.application sessionTracker:self.sessionTracker];
    
    // then
    XCTAssertNil(note3);
}

- (void)testThatItDoesNotCreateANotificationWhenUsersAreJoiningAfterSelfUserJoinedAndLeft
{
    // first user joins
    ZMUpdateEvent *event1 = [self callStateEventInConversation:self.groupConversation joinedUsers:@[self.sender] videoSendingUsers:@[] sequence:@1 session:@"session1"];
    [self.sessionTracker addEvent:event1];
    ZMLocalNotificationForCallEvent *note1 = (id)[ZMLocalNotificationForEvent notificationForEvent:event1 conversation:self.groupConversation managedObjectContext:self.syncMOC application:self.application sessionTracker:self.sessionTracker];
    
    // then
    XCTAssertNotNil(note1);
    XCTAssertEqual(note1.uiNotifications.count, 1u);
    
    // when selfUser joins
    ZMUpdateEvent *event2 = [self callStateEventInConversation:self.groupConversation joinedUsers:@[self.sender, self.selfUser] videoSendingUsers:@[] sequence:@2 session:@"session1"];
    [self.sessionTracker addEvent:event2];
    ZMLocalNotificationForCallEvent *note2 = [note1 copyByAddingEvent:event2  conversation:self.groupConversation];
    
    // then
    XCTAssertEqual(note1.uiNotifications.count, 0u);
    XCTAssertTrue(note1.shouldBeDiscarded);
    XCTAssertNil(note2);
    
    // when selfUser leaves
    ZMUpdateEvent *event3 = [self callStateEventInConversation:self.groupConversation joinedUsers:@[self.sender] videoSendingUsers:@[] sequence:@3 session:@"session1"];
    [self.sessionTracker addEvent:event3];
    ZMLocalNotificationForCallEvent *note3 = (id)[ZMLocalNotificationForEvent notificationForEvent:event3 conversation:self.groupConversation managedObjectContext:self.syncMOC application:self.application sessionTracker:self.sessionTracker];
    
    // then
    XCTAssertNil(note3);
    
    // when second user joins
    ZMUpdateEvent *event4 = [self callStateEventInConversation:self.groupConversation joinedUsers:@[self.sender, self.otherUser] videoSendingUsers:@[] sequence:@4 session:@"session1"];
    [self.sessionTracker addEvent:event4];
    ZMLocalNotificationForCallEvent *note4 = (id)[ZMLocalNotificationForEvent notificationForEvent:event4  conversation:self.groupConversation managedObjectContext:self.syncMOC application:self.application sessionTracker:self.sessionTracker];
    
    // then
    XCTAssertNil(note4);
}


- (void)testThatItUsesFirstSenderIDForCallEndedEvent
{
    // first user joins
    ZMUpdateEvent *event1 = [self callStateEventInConversation:self.groupConversation joinedUsers:@[self.sender] videoSendingUsers:@[] sequence:@2 session:@"session1"];
    [self.sessionTracker addEvent:event1];
    ZMLocalNotificationForCallEvent *note1 = (id)[ZMLocalNotificationForEvent notificationForEvent:event1 conversation:self.groupConversation managedObjectContext:self.syncMOC application:self.application sessionTracker:self.sessionTracker];
    
    // then
    XCTAssertNotNil(note1);
    XCTAssertEqual(note1.uiNotifications.count, 1u);
    UILocalNotification *firstNote = note1.uiNotifications.firstObject;
    XCTAssertEqualObjects(firstNote.alertBody, @"Super User is calling in Super Conversation");
    
    
    // when other user joins
    ZMUpdateEvent *event2 = [self callStateEventInConversation:self.groupConversation joinedUsers:@[self.otherUser, self.sender] videoSendingUsers:@[] sequence:@2 session:@"session1"];
    [self.sessionTracker addEvent:event2];
    ZMLocalNotificationForEvent *note2 = [note1 copyByAddingEvent:event2 conversation:self.groupConversation];
    
    // then
    XCTAssertNil(note2);

    
    // when all user leave
    ZMUpdateEvent *event3 = [self callStateEventInConversation:self.groupConversation joinedUsers:@[] videoSendingUsers:@[] sequence:@2 session:@"session1"];
    [self.sessionTracker addEvent:event3];
    ZMLocalNotificationForEvent *note3 = [note1 copyByAddingEvent:event3 conversation:self.groupConversation];
    
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
    [self.sessionTracker addEvent:event1];
    ZMLocalNotificationForCallEvent *note1 = (id)[ZMLocalNotificationForEvent notificationForEvent:event1 conversation:self.groupConversation managedObjectContext:self.syncMOC application:self.application sessionTracker:self.sessionTracker];
    
    // then
    XCTAssertNotNil(note1);
    XCTAssertEqual(note1.uiNotifications.count, 1u);
    UILocalNotification *firstNote = note1.uiNotifications.firstObject;
    XCTAssertEqualObjects(firstNote.alertBody, @"Super User is calling in Super Conversation");
    
    
    // when other user joins
    ZMUpdateEvent *event2 = [self callStateEventInConversation:self.groupConversation joinedUsers:@[self.otherUser, self.sender] videoSendingUsers:@[] sequence:@2 session:@"session1"];
    [self.sessionTracker addEvent:event2];
    ZMLocalNotificationForCallEvent *note2 = [note1 copyByAddingEvent:event2 conversation:self.groupConversation];
    
    // then
    XCTAssertNil(note2);
    
    
    // when all user leave
    ZMUpdateEvent *event3 = [self callStateEventInConversation:self.groupConversation joinedUsers:@[] videoSendingUsers:@[] sequence:@2 session:@"session2"];
    [self.sessionTracker addEvent:event3];
    ZMLocalNotificationForEvent *note3 = [note1 copyByAddingEvent:event3 conversation:self.groupConversation];
    
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
    [self.sessionTracker addEvent:event1];
    ZMLocalNotificationForCallEvent *note1 = (id)[ZMLocalNotificationForEvent notificationForEvent:event1 conversation:self.groupConversation managedObjectContext:self.syncMOC application:self.application sessionTracker:self.sessionTracker];
    
    // then
    XCTAssertNil(note1);
    
    // when selfuser leaves
    ZMUpdateEvent *event2 = [self callStateEventInConversation:self.groupConversation joinedUsers:@[] videoSendingUsers:@[] sequence:@2 session:@"session1"];
    [self.sessionTracker addEvent:event2];
    ZMLocalNotificationForEvent *note2 = [note1 copyByAddingEvent:event2  conversation:self.groupConversation];
    
    // then
    XCTAssertNil(note2);
}

- (void)testThatItCreatesSetsTheCorrectBody_CallStartedNotification_SenderKnown
{
    // "push.notification.call.started" = "%1$@ wants to talk";
    // when
    ZMLocalNotificationForEvent *note1 = [self callNotificationForConversation:self.oneOnOneConversation otherUser:self.sender othersAreJoined:YES selfIsJoined:NO sequence:@1 session:@"session1"];
    ZMLocalNotificationForEvent *note2 = [self callNotificationForConversation:self.groupConversation otherUser:self.sender othersAreJoined:YES selfIsJoined:NO sequence:@2 session:@"session1"];
    ZMLocalNotificationForEvent *note3 = [self callNotificationForConversation:self.groupConversationWithoutName otherUser:self.sender othersAreJoined:YES selfIsJoined:NO sequence:@3 session:@"session1"];
    
    // then
    XCTAssertEqualObjects([note1.uiNotifications.lastObject alertBody], @"Super User is calling");
    XCTAssertEqualObjects([note2.uiNotifications.lastObject alertBody], @"Super User is calling in Super Conversation");
    XCTAssertEqualObjects([note3.uiNotifications.lastObject alertBody], @"Super User is calling in a conversation");
}

- (void)testThatItCreatesSetsTheCorrectBody_CallStartedNotification_SenderUnKnown
{
    // "push.notification.call.started" = "%1$@ wants to talk";
    // when
    ZMLocalNotificationForEvent *note4 = [self callNotificationForConversation:self.oneOnOneConversation otherUser:nil othersAreJoined:YES selfIsJoined:NO sequence:@1 session:@"session2"];
    ZMLocalNotificationForEvent *note5 = [self callNotificationForConversation:self.groupConversation otherUser:nil othersAreJoined:YES selfIsJoined:NO sequence:@2 session:@"session2"];
    ZMLocalNotificationForEvent *note6 = [self callNotificationForConversation:self.groupConversationWithoutName otherUser:nil othersAreJoined:YES selfIsJoined:NO sequence:@3 session:@"session2"];
    
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
    ZMLocalNotificationForEvent *note7 = [self callNotificationForConversation:self.oneOnOneConversation otherUser:self.sender othersAreJoined:YES selfIsJoined:NO sequence:@1 session:@"session3"];
    ZMLocalNotificationForEvent *note8 = [self callNotificationForConversation:self.groupConversation otherUser:self.sender othersAreJoined:YES selfIsJoined:NO sequence:@2 session:@"session3"];
    ZMLocalNotificationForEvent *note9 = [self callNotificationForConversation:self.groupConversationWithoutName otherUser:self.sender othersAreJoined:YES selfIsJoined:NO sequence:@3 session:@"session3"];
    
    // then
    XCTAssertEqualObjects([note7.uiNotifications.lastObject alertBody], @"Super User is video calling");
    XCTAssertEqualObjects([note8.uiNotifications.lastObject alertBody], @"Super User is video calling in Super Conversation");
    XCTAssertEqualObjects([note9.uiNotifications.lastObject alertBody], @"Super User is video calling in a conversation");
}

- (void)testThatItCreatesSetsTheCorrectBody_CallEndedNotification_SenderKnown
{
    // "push.notification.call.started" = "%1$@ wants to talk";
    // when
    ZMLocalNotificationForCallEvent *note01 = [self callNotificationForConversation:self.oneOnOneConversation otherUser:self.sender othersAreJoined:YES selfIsJoined:NO sequence:@1 session:@"session1"];
    ZMUpdateEvent *event1 = [self callStateEventInConversation:self.oneOnOneConversation joinedUsers:@[] videoSendingUsers:@[] sequence:@2 session:@"session1"];
    [self.sessionTracker addEvent:event1];
    ZMLocalNotificationForEvent *note1 = [note01 copyByAddingEvent:event1 conversation:self.oneOnOneConversation];
    
    ZMLocalNotificationForCallEvent *note02 = [self callNotificationForConversation:self.groupConversation otherUser:self.sender othersAreJoined:YES selfIsJoined:NO sequence:@1 session:@"session1"];
    ZMUpdateEvent *event2 = [self callStateEventInConversation:self.groupConversation joinedUsers:@[] videoSendingUsers:@[] sequence:@2 session:@"session1"];
    [self.sessionTracker addEvent:event2];
    ZMLocalNotificationForEvent *note2 = [note02 copyByAddingEvent:event2 conversation:self.groupConversation];
    
    ZMLocalNotificationForCallEvent *note03 = [self callNotificationForConversation:self.groupConversationWithoutName otherUser:self.sender othersAreJoined:YES selfIsJoined:NO sequence:@1 session:@"session1"];
    ZMUpdateEvent *event3 = [self callStateEventInConversation:self.groupConversationWithoutName joinedUsers:@[] videoSendingUsers:@[] sequence:@2 session:@"session1"];
    [self.sessionTracker addEvent:event3];
    ZMLocalNotificationForEvent *note3 = [note03 copyByAddingEvent:event3 conversation:self.groupConversationWithoutName];
    
    // then
    XCTAssertEqualObjects([note1.uiNotifications.lastObject alertBody], @"Super User called");
    XCTAssertEqualObjects([note2.uiNotifications.lastObject alertBody], @"Super User called in Super Conversation");
    XCTAssertEqualObjects([note3.uiNotifications.lastObject alertBody], @"Super User called in a conversation");
}

- (void)testThatItCreatesSetsTheCorrectBody_CallEndedNotification_SenderUnKnown
{
    // "push.notification.call.started" = "%1$@ wants to talk";
    // when
    NSString *session = @"session1";
    self.sender.name = @"";
    
    ZMLocalNotificationForCallEvent *note01 = [self callNotificationForConversation:self.oneOnOneConversation otherUser:self.sender othersAreJoined:YES selfIsJoined:NO sequence:@1 session:session];
    ZMUpdateEvent *event1 = [self callStateEventInConversation:self.oneOnOneConversation joinedUsers:@[] videoSendingUsers:@[] sequence:@2 session:session];
    [self.sessionTracker addEvent:event1];
    ZMLocalNotificationForEvent *note1 = [note01 copyByAddingEvent:event1 conversation:self.oneOnOneConversation];
    XCTAssertNotNil(note1);
    
    ZMLocalNotificationForCallEvent *note02 = [self callNotificationForConversation:self.groupConversation otherUser:self.sender othersAreJoined:YES selfIsJoined:NO sequence:@1 session:session];
    ZMUpdateEvent *event2 = [self callStateEventInConversation:self.groupConversation joinedUsers:@[] videoSendingUsers:@[] sequence:@2 session:session];
    [self.sessionTracker addEvent:event2];
    ZMLocalNotificationForEvent *note2 = [note02 copyByAddingEvent:event2 conversation:self.groupConversation];
    XCTAssertNotNil(note2);

    ZMLocalNotificationForCallEvent *note03 = [self callNotificationForConversation:self.groupConversationWithoutName otherUser:self.sender othersAreJoined:YES selfIsJoined:NO sequence:@1 session:session];
    ZMUpdateEvent *event3 = [self callStateEventInConversation:self.groupConversationWithoutName joinedUsers:@[] videoSendingUsers:@[] sequence:@2 session:session];
    [self.sessionTracker addEvent:event3];
    ZMLocalNotificationForEvent *note3 = [note03 copyByAddingEvent:event3 conversation:self.groupConversationWithoutName];
    XCTAssertNotNil(note3);

    // then
    XCTAssertEqualObjects([note1.uiNotifications.lastObject alertBody], @"Someone called");
    XCTAssertEqualObjects([note2.uiNotifications.lastObject alertBody], @"Someone called in Super Conversation");
    XCTAssertEqualObjects([note3.uiNotifications.lastObject alertBody], @"Someone called in a conversation");
}

@end

