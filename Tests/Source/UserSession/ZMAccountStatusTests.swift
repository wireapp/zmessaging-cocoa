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


class MockCookieStorage : NSObject, ZMCookieProvider {
    
    var shouldReturnCookie : Bool = false
    
    var authenticationCookieData : Data! {
        if shouldReturnCookie {
            return Data()
        }
        return nil
    }
}


class ZMAccountStatusTests : MessagingTest {

    var sut : ZMAccountStatus!
    
    override func tearDown() {
        sut = nil
        super.tearDown()
        
    }
    
    func testThatIfItLaunchesWithoutCookieButWithHistoryItSetsAccountStateToDeactivatedAccount(){
        // given
        ZMConversation.insertNewObject(in: self.uiMOC)
        ZMConversation.insertNewObject(in: self.uiMOC)

        let cookieStorage = MockCookieStorage()
        cookieStorage.shouldReturnCookie = false
        
        // when
        self.sut = ZMAccountStatus(managedObjectContext: self.uiMOC, cookieStorage: cookieStorage)
        
        // then
        XCTAssertEqual(self.sut.currentAccountState, AccountState.oldDeviceDeactivatedAccount)
        
    }
    
    func testThatIfItLaunchesWithoutCookieNorHistorytItSetsAccountStateToNewAccount(){
        // given
        let cookieStorage = MockCookieStorage()
        cookieStorage.shouldReturnCookie = false
        
        // when
        self.sut = ZMAccountStatus(managedObjectContext: self.uiMOC, cookieStorage: cookieStorage)
        
        // then
        XCTAssertEqual(self.sut.currentAccountState, AccountState.newDeviceNewAccount)
    }
    
    func testThatIfItLaunchesWithCookieAndHistoryItSetsAccountStateToExistingAccount(){
        // given
        ZMConversation.insertNewObject(in: self.uiMOC)
        ZMConversation.insertNewObject(in: self.uiMOC)
        
        let cookieStorage = MockCookieStorage()
        cookieStorage.shouldReturnCookie = true
        
        // when
        self.sut = ZMAccountStatus(managedObjectContext: self.uiMOC, cookieStorage: cookieStorage)
        
        // then
        XCTAssertEqual(self.sut.currentAccountState, AccountState.oldDeviceActiveAccount)
    }

    
    func testThatWhenInitialSyncCompletesItSetsAccountStateToExistingAcccount(){
        // given
        ZMConversation.insertNewObject(in: self.uiMOC)
        ZMConversation.insertNewObject(in: self.uiMOC)
        
        let cookieStorage = MockCookieStorage()
        cookieStorage.shouldReturnCookie = true
        
        // when
        self.sut = ZMAccountStatus(managedObjectContext: self.uiMOC, cookieStorage: cookieStorage)
        
        // then
        XCTAssertEqual(self.sut.currentAccountState, AccountState.oldDeviceActiveAccount)
    }
    
    func testThatWhenLoginSucceedsWithoutRegistrationItSwitchesToNewDeviceExistingAccount() {
        // given
        let cookieStorage = MockCookieStorage()
        cookieStorage.shouldReturnCookie = false
        self.sut = ZMAccountStatus(managedObjectContext: self.uiMOC, cookieStorage: cookieStorage)
        XCTAssertEqual(self.sut.currentAccountState, AccountState.newDeviceNewAccount)
        
        // when
        ZMUserSessionAuthenticationNotification.notifyAuthenticationDidSucceed()
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(self.sut.currentAccountState, AccountState.newDeviceExistingAccount)
    }
    
    func testThatWhenAuthenticationSucceedsOnOldAccountItDoesNotSwitchToNewDeviceExistingAccount() {
        // given
        ZMConversation.insertNewObject(in: self.uiMOC)
        ZMConversation.insertNewObject(in: self.uiMOC)
        
        let cookieStorage = MockCookieStorage()
        cookieStorage.shouldReturnCookie = true
        
        self.sut = ZMAccountStatus(managedObjectContext: self.uiMOC, cookieStorage: cookieStorage)
        XCTAssertEqual(self.sut.currentAccountState, AccountState.oldDeviceActiveAccount)
        
        // when
        ZMUserSessionAuthenticationNotification.notifyAuthenticationDidSucceed()
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(self.sut.currentAccountState, AccountState.oldDeviceActiveAccount)
    }
    
    func testThatWhenLoginSucceedsWithRegistrationItDoesNotSwitchToNewDeviceExistingAccount() {
        // given
        let cookieStorage = MockCookieStorage()
        cookieStorage.shouldReturnCookie = false
        self.sut = ZMAccountStatus(managedObjectContext: self.uiMOC, cookieStorage: cookieStorage)
        XCTAssertEqual(self.sut.currentAccountState, AccountState.newDeviceNewAccount)
        
        // when
        ZMUserSessionRegistrationNotification.notifyEmailVerificationDidSucceed()
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        ZMUserSessionAuthenticationNotification.notifyAuthenticationDidSucceed()
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(self.sut.currentAccountState, AccountState.newDeviceNewAccount)
    }
    
    
    func testThatItAppendsANewDeviceMessageWhenSyncCompletes_NewDevice() {
        // given
        setupSelfClient(inMoc: self.uiMOC)
        
        let cookieStorage = MockCookieStorage()
        cookieStorage.shouldReturnCookie = false
        self.sut = ZMAccountStatus(managedObjectContext: self.uiMOC, cookieStorage: cookieStorage)
        XCTAssertEqual(self.sut.currentAccountState, AccountState.newDeviceNewAccount)

        ZMUserSessionAuthenticationNotification.notifyAuthenticationDidSucceed()
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        let oneOnOne = ZMConversation.insertNewObject(in: self.uiMOC)
        oneOnOne.conversationType = .oneOnOne
        let group = ZMConversation.insertNewObject(in: self.uiMOC)
        group.conversationType = .group
        let connection = ZMConversation.insertNewObject(in: self.uiMOC)
        connection.conversationType = .connection
        let selfConv = ZMConversation.insertNewObject(in: self.uiMOC)
        selfConv.conversationType = .self
        
        XCTAssertEqual(self.sut.currentAccountState, AccountState.newDeviceExistingAccount)

        // when
        NotificationCenter.default.post(name: NSNotification.Name(rawValue: "ZMInitialSyncCompletedNotification"), object: nil)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // then
        XCTAssertEqual(oneOnOne.messages.count, 1)
        XCTAssertEqual(group.messages.count, 1)
        XCTAssertEqual(connection.messages.count, 0)
        if let oneOnOneMsg = oneOnOne.messages.lastObject as? ZMSystemMessage, let groupMsg = oneOnOne.messages.lastObject as? ZMSystemMessage {
            XCTAssertEqual(oneOnOneMsg.systemMessageType, ZMSystemMessageType.usingNewDevice)
            XCTAssertEqual(groupMsg.systemMessageType, ZMSystemMessageType.usingNewDevice)
        } else {
            XCTFail()
        }
        
        XCTAssertEqual(self.sut.currentAccountState, AccountState.oldDeviceActiveAccount)
    }
    
    func testThatItAppendsAReactivedDeviceMessageWhenSyncCompletes_ReactivatedDevice() {
        // given
        setupSelfClient(inMoc: self.uiMOC)
        
        let cookieStorage = MockCookieStorage()
        cookieStorage.shouldReturnCookie = false
        
        let oneOnOne = ZMConversation.insertNewObject(in: self.uiMOC)
        oneOnOne.conversationType = .oneOnOne
        let group = ZMConversation.insertNewObject(in: self.uiMOC)
        group.conversationType = .group
        let connection = ZMConversation.insertNewObject(in: self.uiMOC)
        connection.conversationType = .connection
        let selfConv = ZMConversation.insertNewObject(in: self.uiMOC)
        selfConv.conversationType = .self
        
        self.sut = ZMAccountStatus(managedObjectContext: self.uiMOC, cookieStorage: cookieStorage)
        XCTAssertEqual(self.sut.currentAccountState, AccountState.oldDeviceDeactivatedAccount)
        
        // when
        NotificationCenter.default.post(name: NSNotification.Name(rawValue: "ZMInitialSyncCompletedNotification"), object: nil)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(oneOnOne.messages.count, 1)
        XCTAssertEqual(group.messages.count, 1)
        XCTAssertEqual(connection.messages.count, 0)
        if let oneOnOneMsg = oneOnOne.messages.lastObject as? ZMSystemMessage, let groupMsg = oneOnOne.messages.lastObject as? ZMSystemMessage {
            XCTAssertEqual(oneOnOneMsg.systemMessageType, ZMSystemMessageType.reactivatedDevice)
            XCTAssertEqual(groupMsg.systemMessageType, ZMSystemMessageType.reactivatedDevice)
        } else {
            XCTFail()
        }
        
        XCTAssertEqual(self.sut.currentAccountState, AccountState.oldDeviceActiveAccount)
    }
    
    func testThatWhenSyncCompletesItSwitchesToOldDeviceActiveAccount_NewAccountNewDevice(){
        // given
        let cookieStorage = MockCookieStorage()
        cookieStorage.shouldReturnCookie = false
        self.sut = ZMAccountStatus(managedObjectContext: self.uiMOC, cookieStorage: cookieStorage)
        XCTAssertEqual(self.sut.currentAccountState, AccountState.newDeviceNewAccount)
        
        // when
        NotificationCenter.default.post(name: NSNotification.Name(rawValue: "ZMInitialSyncCompletedNotification"), object: nil)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(self.sut.currentAccountState, AccountState.oldDeviceActiveAccount)
    }
    
    func testThatItSwitchesToOldDeviceDeactivatedAccountWhneAuthenticationFails() {
    
        // given
        ZMConversation.insertNewObject(in: self.uiMOC)
        ZMConversation.insertNewObject(in: self.uiMOC)
        
        let cookieStorage = MockCookieStorage()
        cookieStorage.shouldReturnCookie = true
        
        self.sut = ZMAccountStatus(managedObjectContext: self.uiMOC, cookieStorage: cookieStorage)
        XCTAssertEqual(self.sut.currentAccountState, AccountState.oldDeviceActiveAccount)
        
        // when
        ZMUserSessionAuthenticationNotification.notifyAuthenticationDidFail(NSError(domain:"UserSession", code:0, userInfo: nil))
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(self.sut.currentAccountState, AccountState.oldDeviceActiveAccount)
    
    }
    
}

