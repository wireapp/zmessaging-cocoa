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
import ZMCLinkPreview
@testable import zmessaging

class SelfContactCardUploadStrategyTests : MessagingTest {
    
    var sut : zmessaging.SelfContactCardUploadStrategy!
    var authenticationStatus : MockAuthenticationStatus!
    var clientRegistrationStatus : ZMMockClientRegistrationStatus!
    
    override func setUp() {
        super.setUp()
        self.authenticationStatus = MockAuthenticationStatus(phase: .authenticated)
        self.clientRegistrationStatus = ZMMockClientRegistrationStatus()
        self.clientRegistrationStatus.mockPhase = .registered
        
        self.sut = zmessaging.SelfContactCardUploadStrategy(authenticationStatus: self.authenticationStatus,
                                                               clientRegistrationStatus: self.clientRegistrationStatus,
                                                               managedObjectContext: self.syncMOC)
    }
    
    override func tearDown() {
        self.authenticationStatus = nil
        self.clientRegistrationStatus.tearDown()
        self.clientRegistrationStatus = nil
        self.sut = nil
        super.tearDown()
    }
}

// MARK: - Upload requests
extension SelfContactCardUploadStrategyTests {
    
    func testThatItReturnsNoRequestWhenTheCardIsNotMarkedForUpload() {
        
        // given
        
        // when
        let request = sut.nextRequest() // this will return nil and start async processing
        
        // then
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        XCTAssertNil(request)
    }
    
    func testThatItReturnsARequestWhenTheCardIsMarkedForUpload() {
        
        // given
        zmessaging.AddressBook.markSelfContactCardToBeUploaded(self.syncMOC)
        
        // when
        let request = sut.nextRequest() // this will return nil and start async processing
        
        // then
        XCTAssertNotNil(request)
        if let request = request {
            XCTAssertEqual(request.path, "/onboarding/v3")
            XCTAssertEqual(request.method, ZMTransportRequestMethod.methodPOST)
            if let payload = request.payload as? [String:[Any]] {
                XCTAssertNotNil(payload["cards"])
                XCTAssertNotNil(payload["self"])
            } else {
                XCTFail()
            }
            XCTAssertTrue(request.shouldCompress)
        }
    }
    
    func testThatItIncludesSelfCardWithPhoneNumber() {
        
        // given
        zmessaging.AddressBook.markSelfContactCardToBeUploaded(self.syncMOC)
        let selfUser = ZMUser.selfUser(in: self.syncMOC)
        selfUser.phoneNumber = "+155534534566"
        
        // when
        let request = sut.nextRequest() // this will return nil and start async processing
        
        // then
        XCTAssertNotNil(request)
        if let request = request {
            let selfArray = (request.payload as? [String : AnyObject])?["self"] as? [String] ?? []
            XCTAssertEqual(selfArray, [selfUser.phoneNumber.base64EncodedSHADigest])
        } else {
            XCTFail()
        }
    }
    
    func testThatItIncludesSelfCardWithEmail() {
        
        // given
        zmessaging.AddressBook.markSelfContactCardToBeUploaded(self.syncMOC)
        let selfUser = ZMUser.selfUser(in: self.syncMOC)
        selfUser.emailAddress = "me@example.com"
        
        // when
        let request = sut.nextRequest() // this will return nil and start async processing
        
        // then
        XCTAssertNotNil(request)
        if let request = request {
            let selfArray = (request.payload as? [String : AnyObject])?["self"] as? [String] ?? []
            XCTAssertEqual(selfArray, [selfUser.normalizedEmailAddress.base64EncodedSHADigest])
        } else {
            XCTFail()
        }
    }
    
    func testThatItUploadsOnlyOnceWhenNotAskedAgain() {
        
        // given
        zmessaging.AddressBook.markSelfContactCardToBeUploaded(self.syncMOC)
        let selfUser = ZMUser.selfUser(in: self.syncMOC)
        selfUser.emailAddress = "me@example.com"
        
        // when
        let firstRequest = sut.nextRequest()
        XCTAssertNotNil(firstRequest)
        firstRequest?.complete(with: ZMTransportResponse(payload: nil, httpStatus: 200, transportSessionError: nil))
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertNil(sut.nextRequest())
        
    }
    
    func testThatItUploadsMultipleTimesWhenAskedAgain() {
        
        // given
        zmessaging.AddressBook.markSelfContactCardToBeUploaded(self.syncMOC)
        let selfUser = ZMUser.selfUser(in: self.syncMOC)
        selfUser.emailAddress = "me@example.com"
        
        // when
        let firstRequest = sut.nextRequest()
        XCTAssertNotNil(firstRequest)
        
        // then
        XCTAssertNil(sut.nextRequest())
        
        // and when
        firstRequest?.complete(with: ZMTransportResponse(payload: nil, httpStatus: 200, transportSessionError: nil))
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        zmessaging.AddressBook.markSelfContactCardToBeUploaded(self.syncMOC)

        // then
        XCTAssertNotNil(sut.nextRequest())
    }
    
}
