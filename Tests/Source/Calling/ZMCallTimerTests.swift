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
import CoreData


class ZMCallTimerTests : MessagingTest {

    
    @objc class TestClient: NSObject, ZMCallTimerClient {
        var didTimeOut : Bool = false
        @objc func callTimerDidFire(_ timer: ZMCallTimer) {
            didTimeOut = true
        }
    }
    
    override func setUp() {
        super.setUp()
        ZMCallTimer.setTestCallTimeout(0.2)
    }
    
    override func tearDown() {
        ZMCallTimer.resetTestCallTimeout()
        super.tearDown()
    }
    
    func testThatItAddsACallTimer() {
        self.syncMOC.performAndWait { () -> Void in
            // given
            let conversation = ZMConversation.insertNewObject(in: self.syncMOC)
            self.syncMOC.saveOrRollback()
            let sut = ZMCallTimer(managedObjectContext: self.syncMOC)
            
            // when
            sut.addAndStartTimer(conversation)
            
            // then
            XCTAssertNotNil(sut.conversationIDToTimerMap[conversation.objectID])
            sut.tearDown()
        }
    }
    
    func testThatItAddsOnlyOneCallTimerPerConversation() {
        self.syncMOC.performAndWait { () -> Void in
            // given
            let conversation = ZMConversation.insertNewObject(in: self.syncMOC)
            self.syncMOC.saveOrRollback()
            let sut = ZMCallTimer(managedObjectContext: self.syncMOC)
            
            // when
            sut.addAndStartTimer(conversation)
            sut.addAndStartTimer(conversation)
            // then
            XCTAssertEqual(Array(sut.conversationIDToTimerMap.keys).count, 1)
            sut.tearDown()
        }
    }
    
    func testThatItCanAddMoreThanOneCallTimer() {
        self.syncMOC.performAndWait { () -> Void in
            // given
            let conversation1 = ZMConversation.insertNewObject(in: self.syncMOC)
            let conversation2 = ZMConversation.insertNewObject(in: self.syncMOC)
            self.syncMOC.saveOrRollback()
            let sut = ZMCallTimer(managedObjectContext: self.syncMOC)
            
            // when
            sut.addAndStartTimer(conversation1)
            sut.addAndStartTimer(conversation2)
            // then
            XCTAssertEqual(Array(sut.conversationIDToTimerMap.keys).count, 2)
            sut.tearDown()
        }
    }
    
    
    func testThatItTearsDownACallTimer() {
        self.syncMOC.performAndWait { () -> Void in
            // given
            let conversation = ZMConversation.insertNewObject(in: self.syncMOC)
            self.syncMOC.saveOrRollback()
            let testClient = TestClient()
            
            let sut = ZMCallTimer(managedObjectContext: self.syncMOC)
            sut.testDelegate = testClient
            sut.addAndStartTimer(conversation)
            XCTAssertFalse(testClient.didTimeOut)

            // when
            sut.tearDown()
            self.spinMainQueue(withTimeout: 0.5);
            
            // then
            XCTAssertFalse(testClient.didTimeOut)
            XCTAssertNil(sut.conversationIDToTimerMap[conversation.objectID])

        }
    }
    
    
    func testThatItRemovesTheCallTimerAfterItFired() {
        self.syncMOC.performAndWait { () -> Void in
            // given
            let conversation = ZMConversation.insertNewObject(in: self.syncMOC)
            self.syncMOC.saveOrRollback()
            let sut = ZMCallTimer(managedObjectContext: self.syncMOC)
            
            // when
            sut.addAndStartTimer(conversation)
            self.spinMainQueue(withTimeout: 0.5)
            
            // then
            XCTAssertNil(sut.conversationIDToTimerMap[conversation.objectID])
            sut.tearDown()
        }
    }

    func testThatCallsTimerDidFireOnVoiceChannel() {
        self.syncMOC.performAndWait { () -> Void in
            // given
            let conversation = ZMConversation.insertNewObject(in: self.syncMOC)
            self.syncMOC.saveOrRollback()

            let testClient = TestClient()
            XCTAssertFalse(testClient.didTimeOut)

            let sut = ZMCallTimer(managedObjectContext: self.syncMOC)
            sut.testDelegate = testClient
            
            // when
            sut.addAndStartTimer(conversation)
            self.spinMainQueue(withTimeout: 0.5)
            
            // then
            XCTAssertNil(sut.conversationIDToTimerMap[conversation.objectID])
            XCTAssertTrue(testClient.didTimeOut)
            sut.tearDown()
        }
    }

    
    func testThatItCancelsAndRemovesTheTimer() {
        self.syncMOC.performAndWait { () -> Void in
            // given
            let conversation = ZMConversation.insertNewObject(in: self.syncMOC)
            self.syncMOC.saveOrRollback()

            let testClient = TestClient()
            XCTAssertFalse(testClient.didTimeOut)
            
            let sut = ZMCallTimer(managedObjectContext: self.syncMOC)
            sut.testDelegate = testClient

            // when
            sut.addAndStartTimer(conversation)
            sut.resetTimer(conversation)

            // then
            XCTAssertNil(sut.conversationIDToTimerMap[conversation.objectID])
            
            // when
            self.spinMainQueue(withTimeout: 0.5)
            
            // then
            XCTAssertFalse(testClient.didTimeOut)
            sut.tearDown()
        }
    }
    
    func testThatItDoesNotRemovesAndCancelsATimerWhenDeletingAConversation() {
        self.syncMOC.performAndWait { () -> Void in
            // given
            let conversation = ZMConversation.insertNewObject(in: self.syncMOC)
            self.syncMOC.saveOrRollback()
            let objectID = conversation.objectID
            
            let testClient = TestClient()
            let sut = ZMCallTimer(managedObjectContext: self.syncMOC)
            self.syncMOC.userInfo["ZMCallTimer"] = sut
            sut.testDelegate = testClient
            
            XCTAssertFalse(testClient.didTimeOut)

            // when
            sut.addAndStartTimer(conversation)
            self.syncMOC.delete(conversation);
            self.syncMOC.saveOrRollback()
            
            XCTAssertTrue(conversation.isZombieObject)
            
            // then
            XCTAssertNil(sut.conversationIDToTimerMap[objectID])
            
            // when
            self.spinMainQueue(withTimeout: 0.5)
            
            // then
            XCTAssertFalse(testClient.didTimeOut)
            sut.tearDown()
        }
    }
    
    func testThatItDoesNotCancelAndRemovesTheTimerWhenRefreshingAConversation() {
        self.syncMOC.performAndWait { () -> Void in
            // given
            let conversation = ZMConversation.insertNewObject(in: self.syncMOC)
            self.syncMOC.saveOrRollback()
            let objectID = conversation.objectID
            
            let testClient = TestClient()
            let sut = ZMCallTimer(managedObjectContext: self.syncMOC)
            sut.testDelegate = testClient
            
            XCTAssertFalse(testClient.didTimeOut)
            
            // when
            sut.addAndStartTimer(conversation)
            self.syncMOC.refresh(conversation, mergeChanges: false);
            self.syncMOC.saveOrRollback()
            
            // then
            XCTAssertNotNil(sut.conversationIDToTimerMap[objectID])
            
            // when
            self.spinMainQueue(withTimeout: 0.5)
            
            // then
            XCTAssertTrue(testClient.didTimeOut)
            sut.tearDown()
        }
    }
}

