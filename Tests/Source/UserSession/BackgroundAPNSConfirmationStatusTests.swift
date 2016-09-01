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

@testable import zmessaging
import ZMTesting
import ZMCMockTransport

class FakeApplication : NSObject, ApplicationStateOwner {
    var mockApplicationState : UIApplicationState = .Background
    var applicationState: UIApplicationState {
        return mockApplicationState
    }
}

class FakeBackgroundActivityFactory : BackgroundActivityFactory {
    var nameToHandler : [String : (Void -> Void)] = [:]
    
    override func backgroundActivity(withName name: String, expirationHandler handler: (Void -> Void)) -> ZMBackgroundActivity? {
        nameToHandler[name] = handler
        return ZMBackgroundActivity()
    }
    
    // simulates the expirationHandler being called
    func callHandler(messageNonce: NSUUID){
        guard let handler = nameToHandler.removeValueForKey(messageNonce.transportString()) else { return }
        mainGroupQueue?.performGroupedBlock({ 
            handler()
        })
    }
    
    func tearDown(){
        nameToHandler = [:]
    }
}

class BackgroundAPNSConfirmationStatusTests : MessagingTest {

    var sut : BackgroundAPNSConfirmationStatus!
    var fakeApplication : FakeApplication!
    var fakeBGActivityFactory : FakeBackgroundActivityFactory!

    override func setUp() {
        super.setUp()
        fakeApplication = FakeApplication()
        fakeBGActivityFactory = FakeBackgroundActivityFactory()
        fakeBGActivityFactory.mainGroupQueue = uiMOC // this mimics the real BackgroundActivityFactory
        sut = BackgroundAPNSConfirmationStatus(application: fakeApplication, managedObjectContext: syncMOC, backgroundActivityFactory: fakeBGActivityFactory)
    }
    
    override func tearDown() {
        fakeBGActivityFactory.tearDown()
        sut.tearDown()
        sut = nil
        fakeApplication = nil
        fakeBGActivityFactory = nil
        FakeBackgroundActivityFactory.tearDownInstance()
        super.tearDown()
    }
    
    func testThat_CanSendMessage_IsSetToTrue_NewMessage() {
        // given
        let uuid = NSUUID.createUUID()
        
        // when
        sut.needsToConfirmMessage(uuid)
        XCTAssert(waitForAllGroupsToBeEmptyWithTimeout(0.5))
        
        // then
        XCTAssertTrue(sut.needsToSyncMessages)
    }
    
    func testThat_CanSendMessage_IsSetToFalse_MessageConfirmed() {
        // given
        let uuid = NSUUID.createUUID()
        sut.needsToConfirmMessage(uuid)
        XCTAssert(waitForAllGroupsToBeEmptyWithTimeout(0.5))

        // when
        sut.didConfirmMessage(uuid)
        XCTAssert(waitForAllGroupsToBeEmptyWithTimeout(0.5))

        // then
        XCTAssertFalse(sut.needsToSyncMessages)
    }
    
    func testThat_CanSendMessage_IsSetToTrue_OneMessageConfirmed_OneMessageNew() {
        // given
        let uuid1 = NSUUID.createUUID()
        let uuid2 = NSUUID.createUUID()

        sut.needsToConfirmMessage(uuid1)
        sut.needsToConfirmMessage(uuid2)
        XCTAssert(waitForAllGroupsToBeEmptyWithTimeout(0.5))

        // when
        sut.didConfirmMessage(uuid1)
        XCTAssert(waitForAllGroupsToBeEmptyWithTimeout(0.5))

        // then
        XCTAssertTrue(sut.needsToSyncMessages)
    }
    
    func testThat_CanSendMessage_IsSetToFalse_MessageTimedOut() {
        // given
        let uuid1 = NSUUID.createUUID()
        
        sut.needsToConfirmMessage(uuid1)
        XCTAssert(waitForAllGroupsToBeEmptyWithTimeout(0.5))

        // when
        fakeBGActivityFactory.callHandler(uuid1)
        XCTAssert(waitForAllGroupsToBeEmptyWithTimeout(0.5))
        
        // then
        XCTAssertFalse(sut.needsToSyncMessages)
    }
    
    func testThat_CanSendMessage_IsSetToTrue_OneMessageTimedOut_OneMessageNew() {
        // given
        let uuid1 = NSUUID.createUUID()
        let uuid2 = NSUUID.createUUID()
        
        sut.needsToConfirmMessage(uuid1)
        sut.needsToConfirmMessage(uuid2)
        XCTAssert(waitForAllGroupsToBeEmptyWithTimeout(0.5))

        // when
        fakeBGActivityFactory.callHandler(uuid1)
        XCTAssert(waitForAllGroupsToBeEmptyWithTimeout(0.5))
        
        // then
        XCTAssertTrue(sut.needsToSyncMessages)
    }
}

