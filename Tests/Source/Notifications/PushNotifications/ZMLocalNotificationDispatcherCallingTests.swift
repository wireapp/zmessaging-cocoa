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

class ZMLocalNotificationDispatcherCallingTests : MessagingTest {
    
    var sut : ZMLocalNotificationDispatcher!
    var sender : ZMUser!
    var conversation : ZMConversation!
    
    override func setUp() {
        super.setUp()
        
        sut = ZMLocalNotificationDispatcher(managedObjectContext: syncMOC, sharedApplication: application)
        
        syncMOC.performGroupedBlockAndWait {
            let sender = ZMUser.insertNewObject(in: self.syncMOC)
            sender.name = "Callie"
            sender.remoteIdentifier = UUID()
            
            self.sender = sender
            
            let conversation = ZMConversation.insertNewObject(in: self.syncMOC)
            conversation.conversationType = .oneOnOne
            conversation.remoteIdentifier = UUID()
            conversation.internalAddParticipant(sender, isAuthoritative: true)
            
            self.conversation = conversation
        }
    }
    
    func testThatMissedCallCreatesCallingNotification() {
        // when
        sut.processMissedCall(in: conversation, sender: sender)
        
        // then
        XCTAssertEqual(sut.callingNotifications.notifications.count, 1)
        XCTAssertEqual(application.scheduledLocalNotifications.count, 1)
    }
    
    func testThatIncomingCallCreatesCallingNotification() {
        // when
        sut.process(callState: .incoming(video: false), in: conversation, sender: sender)
        
        // then
        XCTAssertEqual(sut.callingNotifications.notifications.count, 1)
        XCTAssertEqual(application.scheduledLocalNotifications.count, 1)
    }
    
    func testThatIgnoredCallStatesDoesNotCreateCallingNotifications() {
        
        let ignoredCallStates : [CallState] = [.established, .answered, .outgoing, .none, .unknown]
        
        for ignoredCallState in ignoredCallStates {
            // when
            sut.process(callState: ignoredCallState, in: conversation, sender: sender)
            
            // then
            XCTAssertEqual(sut.callingNotifications.notifications.count, 0)
            XCTAssertEqual(application.scheduledLocalNotifications.count, 0)
        }
    }
    
    func testThatIncomingCallIsReplacedByCanceledCallNotification() {
        // given 
        sut.process(callState: .incoming(video: false), in: conversation, sender: sender)
        XCTAssertEqual(sut.callingNotifications.notifications.count, 1)
        XCTAssertEqual(application.scheduledLocalNotifications.count, 1)
        let incomingCallNotification = application.scheduledLocalNotifications.first!
        
        // when
        sut.process(callState: .terminating(reason: .canceled), in: conversation, sender: sender)
        
        // then
        XCTAssertEqual(sut.callingNotifications.notifications.count, 1)
        XCTAssertEqual(application.scheduledLocalNotifications.count, 2)
        XCTAssertEqual(application.cancelledLocalNotifications, [incomingCallNotification])
    }
    
    func testThatIncomingCallIsClearedWhenCallIsAnsweredElsewhere() {
        // given
        sut.process(callState: .incoming(video: false), in: conversation, sender: sender)
        XCTAssertEqual(sut.callingNotifications.notifications.count, 1)
        XCTAssertEqual(application.scheduledLocalNotifications.count, 1)
        let incomingCallNotification = application.scheduledLocalNotifications.first!
        
        // when
        sut.process(callState: .terminating(reason: .anweredElsewhere), in: conversation, sender: sender)
        
        // then
        XCTAssertEqual(sut.callingNotifications.notifications.count, 0)
        XCTAssertEqual(application.scheduledLocalNotifications.count, 1)
        XCTAssertEqual(application.cancelledLocalNotifications, [incomingCallNotification])
    }
    
}
