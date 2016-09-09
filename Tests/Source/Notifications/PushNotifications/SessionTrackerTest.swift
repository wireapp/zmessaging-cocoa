//
//  SessionTrackerTest.swift
//  zmessaging-cocoa
//
//  Created by Sabine Geithner on 09/09/16.
//  Copyright © 2016 Zeta Project Gmbh. All rights reserved.
//

import ZMTesting
@testable import zmessaging

class SessionBaseTest : MessagingTest {
    var conversation : ZMConversation!
    var sender : ZMUser!
    var selfUser : ZMUser!
    var otherUser : ZMUser!
    
    override func setUp() {
        super.setUp()
        let convID = NSUUID.createUUID()
        let senderID = NSUUID.createUUID()
        sender = ZMUser.insertNewObjectInManagedObjectContext(uiMOC)
        sender.remoteIdentifier = senderID
        otherUser = ZMUser.insertNewObjectInManagedObjectContext(uiMOC)
        otherUser.remoteIdentifier = NSUUID.createUUID()
        
        conversation = ZMConversation.insertGroupConversationIntoManagedObjectContext(uiMOC, withParticipants: [sender, otherUser])
        conversation.remoteIdentifier = convID
        
        selfUser = ZMUser.selfUserInContext(uiMOC)
        selfUser.remoteIdentifier = NSUUID.createUUID()
        
    }
}


class SessionTests : SessionBaseTest {
    var sut : Session!

    override func setUp() {
        super.setUp()
        sut = Session(sessionID: "session1", conversationID: conversation.remoteIdentifier!, initiatorID: sender.remoteIdentifier!)
    }
    
    override func tearDown(){
        sut = nil
        super.tearDown()
    }
    
    func testThatItSetsStateToIncoming(){
        // given
        let event = callStateEventInConversation(conversation, joinedUsers: [sender], videoSendingUsers: [], sequence: 1)
        
        // when
        let newState = sut.changeState(event, managedObjectContext:uiMOC)
        
        // then
        XCTAssertEqual(newState, Session.State.Incoming)
    }
    
    func testThatItSetsStateToOngoing(){
        // given
        let event1 = callStateEventInConversation(conversation, joinedUsers: [sender], videoSendingUsers: [], sequence: 1)
        sut.changeState(event1, managedObjectContext:uiMOC)
        let event2 = callStateEventInConversation(conversation, joinedUsers: [sender, otherUser], videoSendingUsers: [], sequence: 1)
        
        // when
        let newState = sut.changeState(event2, managedObjectContext:uiMOC)
        
        // then
        XCTAssertEqual(newState, Session.State.Ongoing)
    }
    
    func testThatItSetsStateToEnded(){
        // given
        let event1 = callStateEventInConversation(conversation, joinedUsers: [sender], videoSendingUsers: [], sequence: 1)
        sut.changeState(event1, managedObjectContext:uiMOC)
        let event2 = callStateEventInConversation(conversation, joinedUsers: [], videoSendingUsers: [], sequence: 1)

        // when
        let newState = sut.changeState(event2, managedObjectContext:uiMOC)
        
        // then
        XCTAssertEqual(newState, Session.State.SessionEnded)
    }
    
    func testThatItSetsStateToSelfUserJoined(){
        // given
        let event1 = callStateEventInConversation(conversation, joinedUsers: [sender], videoSendingUsers: [], sequence: 1)
        sut.changeState(event1, managedObjectContext:uiMOC)
        let event2 = callStateEventInConversation(conversation, joinedUsers: [sender, selfUser], videoSendingUsers: [], sequence: 1)

        // when
        let newState = sut.changeState(event2, managedObjectContext:uiMOC)
        
        // then
        XCTAssertEqual(newState, Session.State.SelfUserJoined)
    }
    
    func testThatItSetsStateToSelfUserEnded(){
        // given
        let event1 = callStateEventInConversation(conversation, joinedUsers: [sender], videoSendingUsers: [], sequence: 1)
        sut.changeState(event1, managedObjectContext:uiMOC)
        let event2 = callStateEventInConversation(conversation, joinedUsers: [sender, selfUser], videoSendingUsers: [], sequence: 1)
        sut.changeState(event2, managedObjectContext:uiMOC)
        let event3 = callStateEventInConversation(conversation, joinedUsers: [], videoSendingUsers: [], sequence: 1)
        
        // when
        let newState = sut.changeState(event3, managedObjectContext:uiMOC)
        
        // then
        XCTAssertEqual(newState, Session.State.SessionEndedSelfJoined)
    }
    
    func testThatItDoesNotAddEventsWithOlderSequence(){
        // given
        let event1 = callStateEventInConversation(conversation, joinedUsers: [sender], videoSendingUsers: [], sequence: 1)
        sut.changeState(event1, managedObjectContext:uiMOC)
        
        let event2 = callStateEventInConversation(conversation, joinedUsers: [], videoSendingUsers: [], sequence: 3)
        sut.changeState(event2, managedObjectContext:uiMOC)
        
        let event3 = callStateEventInConversation(conversation, joinedUsers: [selfUser], videoSendingUsers: [], sequence: 2)
        
        // when
        let newState = sut.changeState(event3, managedObjectContext:uiMOC)
        
        // then
        XCTAssertEqual(newState, Session.State.SessionEnded)
    }
}


class SessionTrackerTest : SessionBaseTest {
    
    var sut: SessionTracker!
    
    override func setUp() {
        super.setUp()
        sut = SessionTracker(managedObjectContext: uiMOC)
    }
    
    override func tearDown(){
        sut.tearDown()
        sut = nil
        super.tearDown()
    }
    
    func testThatItAddsOneSessionPerSessionID(){
        // given
        let event1 = callStateEventInConversation(conversation, joinedUsers: [sender], videoSendingUsers: [], sequence: 1, session: "session1")
        let event2 = callStateEventInConversation(conversation, joinedUsers: [sender, otherUser], videoSendingUsers: [], sequence: 2, session: "session1")
        let event3 = callStateEventInConversation(conversation, joinedUsers: [sender, otherUser], videoSendingUsers: [], sequence: 3, session: "session2")
        
        // when
        sut.addEvent(event1)
        XCTAssertEqual(sut.sessions.count, 1)

        sut.addEvent(event2)
        XCTAssertEqual(sut.sessions.count, 1)
        
        sut.addEvent(event3)
        XCTAssertEqual(sut.sessions.count, 2)
        
        // then
        let missedSessions = sut.missedSessionsFor(conversation.remoteIdentifier)
        XCTAssertEqual(missedSessions.count, 1)
        XCTAssertEqual(missedSessions.first?.sessionID, "session1")
    }
    
    func testThatItReturnsACopyOfASession(){
        // given
        let event1 = callStateEventInConversation(conversation, joinedUsers: [sender], videoSendingUsers: [], sequence: 1, session: "session1")
        let event2 = callStateEventInConversation(conversation, joinedUsers: [], videoSendingUsers: [], sequence: 2, session: "session1")
        sut.addEvent(event1)
        
        // when
        let session1 = sut.sessionForEvent(event1)
        sut.addEvent(event2)
        let session2 = sut.sessionForEvent(event1)

        // then
        XCTAssertNotEqual(session1?.currentState, session2?.currentState)
        XCTAssertEqual(session1?.currentState, Session.State.Incoming)
        XCTAssertEqual(session2?.currentState, Session.State.SessionEnded)
    }
}

