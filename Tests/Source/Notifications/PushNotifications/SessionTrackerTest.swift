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

