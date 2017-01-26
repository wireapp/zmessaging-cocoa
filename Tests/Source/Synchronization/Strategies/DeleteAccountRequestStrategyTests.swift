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
import zmessaging
import ZMTransport

class DeleteAccountRequestStrategyTests: MessagingTest {
    
    fileprivate var sut : DeleteAccountRequestStrategy!
    fileprivate var authStatus : ZMAuthenticationStatus!
    
    override func setUp() {
        super.setUp()
        let cookie = ZMCookie(managedObjectContext: self.uiMOC, cookieStorage: self.mockTransportSession.cookieStorage)
        self.authStatus = ZMAuthenticationStatus(managedObjectContext: self.uiMOC, cookie: cookie)
        self.sut = DeleteAccountRequestStrategy(authStatus:authStatus, managedObjectContext: self.uiMOC)
    }
    
    override func tearDown() {
        self.sut = nil
        super.tearDown()
    }
    
    func testThatItGeneratesNoRequestsIfTheStatusIsEmpty() {
        XCTAssertNil(self.sut.nextRequest())
    }
    
    func testThatItGeneratesARequest() {
        
        // given
        self.uiMOC.setPersistentStoreMetadata(NSNumber(value: true), key: DeleteAccountRequestStrategy.userDeletionInitiatedKey)
        
        // when
        let request : ZMTransportRequest? = self.sut.nextRequest()
        
        // then
        if let request = request {
            XCTAssertEqual(request.method, ZMTransportRequestMethod.methodDELETE)
            XCTAssertEqual(request.path, "/self")
            XCTAssertTrue(request.needsAuthentication)
        } else {
            XCTFail("Empty request")
        }
    }
    
    func testThatItGeneratesARequestOnlyOnce() {
        
        // given
        self.uiMOC.setPersistentStoreMetadata(NSNumber(value: true), key: DeleteAccountRequestStrategy.userDeletionInitiatedKey)
        
        // when
        let request1 : ZMTransportRequest? = self.sut.nextRequest()
        let request2 : ZMTransportRequest? = self.sut.nextRequest()
        
        // then
        XCTAssertNotNil(request1)
        XCTAssertNil(request2)
        
    }
    
    func testThatItSignsUserOutWhenSuccessful() {
        // given
        self.uiMOC.setPersistentStoreMetadata(NSNumber(value: true), key: DeleteAccountRequestStrategy.userDeletionInitiatedKey)
        let notificationExpectation = self.expectation(description: "Notification fired")
        
        let _ = NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: "ZMUserSessionAuthenticationNotificationName"), object: nil, queue: .main) { _ in
            notificationExpectation.fulfill()
        }
        
        // when
        let request1 : ZMTransportRequest! = self.sut.nextRequest()
        request1.complete(with: ZMTransportResponse(payload: [] as ZMTransportData, httpStatus: 201, transportSessionError: nil))
        
        // then
        XCTAssertTrue(self.waitForCustomExpectations(withTimeout: 0.5))
    }
}
