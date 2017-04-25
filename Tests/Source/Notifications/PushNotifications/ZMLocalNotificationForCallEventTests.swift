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

import Foundation


class ZMLocalNotificationForCallStateTests : MessagingTest {
    
    var sender : ZMUser!
    var conversation : ZMConversation!
    
    override func setUp() {
        super.setUp()
        
        syncMOC.performGroupedBlockAndWait {
            let sender = ZMUser.insertNewObject(in: self.syncMOC)
            sender.name = "Callie"
            sender.remoteIdentifier = UUID()
            
            self.sender = sender
            
            let conversation = ZMConversation.insertNewObject(in: self.syncMOC)
            conversation.conversationType = .oneOnOne
            conversation.remoteIdentifier = UUID()
            conversation.internalAddParticipants(Set<ZMUser>(arrayLiteral: sender), isAuthoritative: true)
            
            self.conversation = conversation
        }
    }
    
    
    func testIncomingAudioCall() {
        
        // given
        let note = ZMLocalNotificationForCallState(conversation: conversation, sender: sender)
        note.update(forCallState: .incoming(video: false, shouldRing: false))
        
        // when
        let uiNote = note.notifications.first!
        
        // then
        XCTAssertEqual(uiNote.alertBody, "Callie is calling")
        XCTAssertEqual(uiNote.category, ZMIncomingCallCategory)
        XCTAssertEqual(uiNote.soundName, ZMCustomSound.notificationRingingSoundName())
    }
    
    func testIncomingVideoCall() {
        
        // given
        let note = ZMLocalNotificationForCallState(conversation: conversation, sender: sender)
        note.update(forCallState: .incoming(video: true, shouldRing: false))
        
        // when
        let uiNote = note.notifications.first!
        
        // then
        XCTAssertEqual(uiNote.alertBody, "Callie is video calling")
        XCTAssertEqual(uiNote.category, ZMIncomingCallCategory)
        XCTAssertEqual(uiNote.soundName, ZMCustomSound.notificationRingingSoundName())
    }
    
    func testCanceledCall() {
        // given
        let note = ZMLocalNotificationForCallState(conversation: conversation, sender: sender)
        note.update(forCallState: .terminating(reason: .canceled))
        
        // when
        let uiNote = note.notifications.first!
        
        // then
        XCTAssertEqual(uiNote.alertBody, "Callie called")
        XCTAssertEqual(uiNote.category, ZMConversationCategory)
        XCTAssertEqual(uiNote.soundName, ZMCustomSound.notificationNewMessageSoundName())
    }
    
    func testCallClosedReasonsWhichShouldBeIgnored() {
        // given
        let note = ZMLocalNotificationForCallState(conversation: conversation, sender: sender)
        let ignoredCallClosedReasons : [CallClosedReason] = [.anweredElsewhere, .normal]
        
        // when
        for reason in ignoredCallClosedReasons {
            note.update(forCallState: .terminating(reason: reason))
        }
        
        // then
        XCTAssertEqual(note.notifications.count, 0)
    }
    
    
    func testMissedCall() {
        // given
        let note = ZMLocalNotificationForCallState(conversation: conversation, sender: sender)
        note.updateForMissedCall()
        
        // when
        let uiNote = note.notifications.first!
        
        // then
        XCTAssertEqual(uiNote.alertBody, "Callie called")
        XCTAssertEqual(uiNote.category, ZMMissedCallCategory)
        XCTAssertEqual(uiNote.soundName, ZMCustomSound.notificationNewMessageSoundName())
    }
    
    
}
