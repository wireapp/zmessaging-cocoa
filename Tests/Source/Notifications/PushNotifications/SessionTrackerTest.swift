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

import WireTesting
@testable import WireSyncEngine

class SessionBaseTest : MessagingTest {
    var conversation : ZMConversation!
    var sender : ZMUser!
    var selfUser : ZMUser!
    var otherUser : ZMUser!
    
    override func setUp() {
        super.setUp()
        let convID = UUID.create()
        let senderID = UUID.create()
        sender = ZMUser.insertNewObject(in: uiMOC)
        sender.remoteIdentifier = senderID
        otherUser = ZMUser.insertNewObject(in: uiMOC)
        otherUser.remoteIdentifier = UUID.create()
        
        conversation = ZMConversation.insertGroupConversation(into: uiMOC, withParticipants: [sender, otherUser])
        conversation.remoteIdentifier = convID
        
        selfUser = ZMUser.selfUser(in: uiMOC)
        selfUser.remoteIdentifier = UUID.create()
        
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
        let event = callStateEvent(in: conversation, joinedUsers: [sender], videoSendingUsers: [], sequence: 1)
        
        // when
        let newState = sut.changeState(event!, managedObjectContext:uiMOC)
        
        // then
        XCTAssertEqual(newState, Session.State.incoming)
    }
    
    func testThatItSetsStateToOngoing(){
        // given
        let event1 = callStateEvent(in: conversation, joinedUsers: [sender], videoSendingUsers: [], sequence: 1)
        _ = sut.changeState(event1!, managedObjectContext:uiMOC)
        let event2 = callStateEvent(in: conversation, joinedUsers: [sender, otherUser], videoSendingUsers: [], sequence: 1)
        
        // when
        let newState = sut.changeState(event2!, managedObjectContext:uiMOC)
        
        // then
        XCTAssertEqual(newState, Session.State.ongoing)
    }
    
    func testThatItSetsStateToEnded(){
        // given
        let event1 = callStateEvent(in: conversation, joinedUsers: [sender], videoSendingUsers: [], sequence: 1)
        _ = sut.changeState(event1!, managedObjectContext:uiMOC)
        let event2 = callStateEvent(in: conversation, joinedUsers: [], videoSendingUsers: [], sequence: 1)

        // when
        let newState = sut.changeState(event2!, managedObjectContext:uiMOC)
        
        // then
        XCTAssertEqual(newState, Session.State.sessionEnded)
    }
    
    func testThatItSetsStateToSelfUserJoined(){
        // given
        let event1 = callStateEvent(in: conversation, joinedUsers: [sender], videoSendingUsers: [], sequence: 1)
        _ = sut.changeState(event1!, managedObjectContext:uiMOC)
        let event2 = callStateEvent(in: conversation, joinedUsers: [sender, selfUser], videoSendingUsers: [], sequence: 1)

        // when
        let newState = sut.changeState(event2!, managedObjectContext:uiMOC)
        
        // then
        XCTAssertEqual(newState, Session.State.selfUserJoined)
    }
    
    func testThatItSetsStateToSelfUserEnded(){
        // given
        let event1 = callStateEvent(in: conversation, joinedUsers: [sender], videoSendingUsers: [], sequence: 1)
        _ = sut.changeState(event1!, managedObjectContext:uiMOC)
        let event2 = callStateEvent(in: conversation, joinedUsers: [sender, selfUser], videoSendingUsers: [], sequence: 1)
        _ = sut.changeState(event2!, managedObjectContext:uiMOC)
        let event3 = callStateEvent(in: conversation, joinedUsers: [], videoSendingUsers: [], sequence: 1)
        
        // when
        let newState = sut.changeState(event3!, managedObjectContext:uiMOC)
        
        // then
        XCTAssertEqual(newState, Session.State.sessionEndedSelfJoined)
    }
    
    func testThatItDoesNotAddEventsWithOlderSequence(){
        // given
        let event1 = callStateEvent(in: conversation, joinedUsers: [sender], videoSendingUsers: [], sequence: 1)
        _ = sut.changeState(event1!, managedObjectContext:uiMOC)
        
        let event2 = callStateEvent(in: conversation, joinedUsers: [], videoSendingUsers: [], sequence: 3)
        _ = sut.changeState(event2!, managedObjectContext:uiMOC)
        
        let event3 = callStateEvent(in: conversation, joinedUsers: [selfUser], videoSendingUsers: [], sequence: 2)
        
        // when
        let newState = sut.changeState(event3!, managedObjectContext:uiMOC)
        
        // then
        XCTAssertEqual(newState, Session.State.sessionEnded)
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
        let event1 = callStateEvent(in: conversation, joinedUsers: [sender], videoSendingUsers: [], sequence: 1, session: "session1")
        let event2 = callStateEvent(in: conversation, joinedUsers: [sender, otherUser], videoSendingUsers: [], sequence: 2, session: "session1")
        let event3 = callStateEvent(in: conversation, joinedUsers: [sender, otherUser], videoSendingUsers: [], sequence: 3, session: "session2")
        
        // when
        sut.addEvent(event1!)
        XCTAssertEqual(sut.sessions.count, 1)

        sut.addEvent(event2!)
        XCTAssertEqual(sut.sessions.count, 1)
        
        sut.addEvent(event3!)
        XCTAssertEqual(sut.sessions.count, 2)
        
        // then
        let missedSessions = sut.missedSessionsFor(conversation.remoteIdentifier!)
        XCTAssertEqual(missedSessions.count, 1)
        XCTAssertEqual(missedSessions.first?.sessionID, "session1")
    }
    
    func testThatItReturnsACopyOfASession(){
        // given
        let event1 = callStateEvent(in: conversation, joinedUsers: [sender], videoSendingUsers: [], sequence: 1, session: "session1")
        let event2 = callStateEvent(in: conversation, joinedUsers: [], videoSendingUsers: [], sequence: 2, session: "session1")
        sut.addEvent(event1!)
        
        // when
        let session1 = sut.sessionForEvent(event1!)
        sut.addEvent(event2!)
        let session2 = sut.sessionForEvent(event1!)

        // then
        XCTAssertNotEqual(session1?.currentState, session2?.currentState)
        XCTAssertEqual(session1?.currentState, Session.State.incoming)
        XCTAssertEqual(session2?.currentState, Session.State.sessionEnded)
    }
    
    func testThatItRestoresOldSessions() {
        // given
        let event = callStateEvent(in: conversation, joinedUsers: [sender], videoSendingUsers: [], sequence: 1, session: "session1")
        sut.addEvent(event!)

        // when
        sut = SessionTracker(managedObjectContext: uiMOC)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(sut.sessions.count, 1)
        XCTAssertEqual(sut.sessions.first?.sessionID, "session1")
    }
    
    func testThatItUnarchivesSessionFromBeforeProjectRenameWithoutCrashing() {
        // given
        NSKeyedArchiver.setClassName("zmessaging.Session", for: Session.self) // Class name before the project rename
        let event = callStateEvent(in: conversation, joinedUsers: [sender], videoSendingUsers: [], sequence: 1, session: "session1")
        sut.addEvent(event!)

        // when
        NSKeyedArchiver.setClassName("WireSyncEngine.Session", for: Session.self) // Class name after project rename
        sut = SessionTracker(managedObjectContext: uiMOC)
        
        // then
        XCTAssertEqual(sut.sessions.count, 1)
        XCTAssertEqual(sut.sessions.first?.sessionID, "session1")
    }
    
}

