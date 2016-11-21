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

import XCTest
@testable import zmessaging

class UserProfileUpdateRequestStrategyTests : MessagingTest {
    
    var sut : UserProfileRequestStrategy!
    
    var userProfileUpdateStatus : TestUserProfileUpdateStatus!
    
    var mockAuthenticationStatus : MockAuthenticationStatus!
    
    override func setUp() {
        super.setUp()
        self.mockAuthenticationStatus = MockAuthenticationStatus()
        self.userProfileUpdateStatus = TestUserProfileUpdateStatus(managedObjectContext: self.uiMOC, newRequestCallback: { _ in return })
        self.sut = UserProfileRequestStrategy(managedObjectContext: self.uiMOC,
                                              userProfileUpdateStatus: self.userProfileUpdateStatus,
                                              authenticationStatus: self.mockAuthenticationStatus)
        self.mockAuthenticationStatus.mockPhase = .authenticated

    }
    
    override func tearDown() {
        self.sut = nil
        self.userProfileUpdateStatus = nil
        self.mockAuthenticationStatus = nil
        super.tearDown()
    }
    
}

// MARK: - Request generation
extension UserProfileUpdateRequestStrategyTests {
    
    func testThatItDoesNotCreateAnyRequestWhenNotAuthenticated() {
        
        // GIVEN
        self.userProfileUpdateStatus.requestPhoneVerificationCode(phoneNumber: "+15553453453")
        self.mockAuthenticationStatus.mockPhase = .unauthenticated
        
        // THEN
        XCTAssertNil(self.sut.nextRequest())

    }
    
    func testThatItDoesNotCreateAnyRequestWhenIdle() {
        
        // GIVEN
        // already authenticated in setup
        
        // THEN
        XCTAssertNil(self.sut.nextRequest())
    }
    
    func testThatItCreatesARequestToRequestAPhoneVerificationCode() {
        
        // GIVEN
        let phone = "+155523123123"
        self.userProfileUpdateStatus.requestPhoneVerificationCode(phoneNumber: phone)
        
        // WHEN
        let request = self.sut.nextRequest()
        
        // THEN
        let expected = ZMTransportRequest(path: "/self/phone", method: .methodPUT, payload: ["phone":phone] as NSDictionary)
        XCTAssertEqual(request, expected)
    }
    
    func testThatItCreatesARequestToChangePhone() {
        
        // GIVEN
        let credentials = ZMPhoneCredentials(phoneNumber: "+155523123123", verificationCode: "12345")
        self.userProfileUpdateStatus.requestPhoneNumberChange(credentials: credentials)
        
        // WHEN
        let request = self.sut.nextRequest()
        
        // THEN
        let expected = ZMTransportRequest(path: "/activate", method: .methodPOST, payload: [
            "phone":credentials.phoneNumber!,
            "code":credentials.phoneNumberVerificationCode!,
            "dryrun":false
            ] as NSDictionary)
        XCTAssertEqual(request, expected)
    }
    
    func testThatItCreatesARequestToUpdatePassword() {
        
        // GIVEN
        let credentials = ZMEmailCredentials(email: "mario@example.com", password: "princess")
        try! self.userProfileUpdateStatus.requestSettingEmailAndPassword(credentials: credentials)
        
        // WHEN
        let request = self.sut.nextRequest()
        
        // THEN
        let expected = ZMTransportRequest(path: "/self/password", method: .methodPUT, payload: [
            "new_password":credentials.password!
            ] as NSDictionary)
        XCTAssertEqual(request, expected)
    }
    
    func tetThatItCreatesARequestToUpdateEmailAfterUpdatingPassword() {
        
        // GIVEN
        let credentials = ZMEmailCredentials(email: "mario@example.com", password: "princess")
        try! self.userProfileUpdateStatus.requestSettingEmailAndPassword(credentials: credentials)
        self.userProfileUpdateStatus.didUpdatePasswordSuccessfully()
        
        // WHEN
        let request = self.sut.nextRequest()
        
        // THEN
        let expected = ZMTransportRequest(path: "/self/email", method: .methodPUT, payload: [
            "email":credentials.email!
            ] as NSDictionary)
        XCTAssertEqual(request, expected)
        
    }
}

// MARK: - Parsing response
extension UserProfileUpdateRequestStrategyTests {
    
    func testThatItCallsDidRequestPhoneVerificationCodeSuccessfully() {
        
        // GIVEN
        let phone = "+155523123123"
        self.userProfileUpdateStatus.requestPhoneVerificationCode(phoneNumber: phone)
        
        // WHEN
        let request = self.sut.nextRequest()
        request?.complete(with: self.successResponse())

        // THEN
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        XCTAssertEqual(self.userProfileUpdateStatus.recordedDidRequestPhoneVerificationCodeSuccessfully, 1)
    }
    
    func testThatItCallsDidFailPhoneVerificationCodeRequest() {
        
        // GIVEN
        let phone = "+155523123123"
        self.userProfileUpdateStatus.requestPhoneVerificationCode(phoneNumber: phone)
        
        // WHEN
        let request = self.sut.nextRequest()
        request?.complete(with: self.invalidPhoneNumberResponse())
        
        // THEN
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        XCTAssertEqual(self.userProfileUpdateStatus.recordedDidFailPhoneVerificationCodeRequest.count, 1)
        guard let error = self.userProfileUpdateStatus.recordedDidFailPhoneVerificationCodeRequest.first as? NSError else { return }
        XCTAssertEqual(error.code, Int(ZMUserSessionErrorCode.invalidPhoneNumber.rawValue))
    }
    
    func testThatItGetsInvalidPhoneNumberErrorOnBadRequestResponse() {
        
        // GIVEN
        let phone = "+155523123123"
        self.userProfileUpdateStatus.requestPhoneVerificationCode(phoneNumber: phone)
        
        // WHEN
        let request = self.sut.nextRequest()
        request?.complete(with: self.badRequestResponse())
        
        // THEN
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        XCTAssertEqual(self.userProfileUpdateStatus.recordedDidFailPhoneVerificationCodeRequest.count, 1)
        guard let error = self.userProfileUpdateStatus.recordedDidFailPhoneVerificationCodeRequest.first as? NSError else { return }
        XCTAssertEqual(error.code, Int(ZMUserSessionErrorCode.invalidPhoneNumber.rawValue))
    }
    
    func testThatItGetsDuplicatePhoneNumberErrorOnDuplicatePhoneNumber() {
        
        // GIVEN
        let phone = "+155523123123"
        self.userProfileUpdateStatus.requestPhoneVerificationCode(phoneNumber: phone)
        
        // WHEN
        let request = self.sut.nextRequest()
        request?.complete(with: self.keyExistsResponse())
        
        // THEN
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        XCTAssertEqual(self.userProfileUpdateStatus.recordedDidFailPhoneVerificationCodeRequest.count, 1)
        guard let error = self.userProfileUpdateStatus.recordedDidFailPhoneVerificationCodeRequest.first as? NSError else { return }
        XCTAssertEqual(error.code, Int(ZMUserSessionErrorCode.phoneNumberIsAlreadyRegistered.rawValue))
    }
    
    func testThatItCallsDidChangePhoneSuccessfully() {
        
        // GIVEN
        let credentials = ZMPhoneCredentials(phoneNumber: "+155523123123", verificationCode: "12345")
        self.userProfileUpdateStatus.requestPhoneNumberChange(credentials: credentials)
        
        // WHEN
        let request = self.sut.nextRequest()
        request?.complete(with: self.successResponse())
        
        // THEN
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        XCTAssertEqual(self.userProfileUpdateStatus.recordedDidChangePhoneSuccesfully, 1)
    }
    
    func testThatItCallsDidFailChangePhone() {
        
        // GIVEN
        let credentials = ZMPhoneCredentials(phoneNumber: "+155523123123", verificationCode: "12345")
        self.userProfileUpdateStatus.requestPhoneNumberChange(credentials: credentials)
        
        // WHEN
        let request = self.sut.nextRequest()
        request?.complete(with: self.errorResponse())
        
        // THEN
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        XCTAssertEqual(self.userProfileUpdateStatus.recordedDidFailChangingPhone.count, 1)
        guard let error = self.userProfileUpdateStatus.recordedDidFailPhoneVerificationCodeRequest.first as? NSError else { return }
        XCTAssertEqual(error.code, Int(ZMUserSessionErrorCode.unkownError.rawValue))
    }
    
    func testThatCallsDidUpdatePasswordSuccessfully() {
        
        // GIVEN
        let credentials = ZMEmailCredentials(email: "mario@example.com", password: "princess")
        try! self.userProfileUpdateStatus.requestSettingEmailAndPassword(credentials: credentials)
        
        // WHEN
        let request = self.sut.nextRequest()
        request?.complete(with: self.successResponse())
        
        // THEN
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        XCTAssertEqual(self.userProfileUpdateStatus.recordedDidUpdatePasswordSuccessfully, 1)
    }
    
    func testThatCallsDidUpdatePasswordSuccessfullyOn403() {
        
        // GIVEN
        let credentials = ZMEmailCredentials(email: "mario@example.com", password: "princess")
        try! self.userProfileUpdateStatus.requestSettingEmailAndPassword(credentials: credentials)
        
        // WHEN
        let request = self.sut.nextRequest()
        request?.complete(with: self.invalidCredentialsResponse())
        
        // THEN
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        XCTAssertEqual(self.userProfileUpdateStatus.recordedDidUpdatePasswordSuccessfully , 1)
    }
    
    func testThatCallsDidFailPasswordUpdateOn400() {
        
        // GIVEN
        let credentials = ZMEmailCredentials(email: "mario@example.com", password: "princess")
        try! self.userProfileUpdateStatus.requestSettingEmailAndPassword(credentials: credentials)
        
        // WHEN
        let request = self.sut.nextRequest()
        request?.complete(with: self.errorResponse())
        
        // THEN
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        XCTAssertEqual(self.userProfileUpdateStatus.recordedDidFailPasswordUpdate , 1)
    }
    
    func testThatItCallsDidUpdateEmailSuccessfully() {
        
        // GIVEN
        let credentials = ZMEmailCredentials(email: "mario@example.com", password: "princess")
        try! self.userProfileUpdateStatus.requestSettingEmailAndPassword(credentials: credentials)
        self.userProfileUpdateStatus.didUpdatePasswordSuccessfully()
        
        // WHEN
        let request = self.sut.nextRequest()
        request?.complete(with: self.successResponse())

        
        // THEN
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        XCTAssertEqual(self.userProfileUpdateStatus.recordedDidUpdateEmailSuccessfully , 1)
    }
    
    func testThatItCallsDidFailEmailUpdateWithInvalidEmail() {
        
        // GIVEN
        let credentials = ZMEmailCredentials(email: "mario@example.com", password: "princess")
        try! self.userProfileUpdateStatus.requestSettingEmailAndPassword(credentials: credentials)
        self.userProfileUpdateStatus.didUpdatePasswordSuccessfully()
        
        // WHEN
        let request = self.sut.nextRequest()
        request?.complete(with: self.invalidEmailResponse())
        
        // THEN
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        XCTAssertEqual(self.userProfileUpdateStatus.recordedDidFailEmailUpdate.count, 1)
        guard let error = self.userProfileUpdateStatus.recordedDidFailEmailUpdate.first as? NSError else { return }
        XCTAssertEqual(error.code, Int(ZMUserSessionErrorCode.invalidEmail.rawValue))
    }
    
    func testThatItCallsDidFailEmailUpdateWithDuplicatedEmail() {
        
        // GIVEN
        let credentials = ZMEmailCredentials(email: "mario@example.com", password: "princess")
        try! self.userProfileUpdateStatus.requestSettingEmailAndPassword(credentials: credentials)
        self.userProfileUpdateStatus.didUpdatePasswordSuccessfully()
        
        // WHEN
        let request = self.sut.nextRequest()
        request?.complete(with: self.keyExistsResponse())
        
        // THEN
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        XCTAssertEqual(self.userProfileUpdateStatus.recordedDidFailEmailUpdate.count, 1)
        guard let error = self.userProfileUpdateStatus.recordedDidFailEmailUpdate.first as? NSError else { return }
        XCTAssertEqual(error.code, Int(ZMUserSessionErrorCode.emailIsAlreadyRegistered.rawValue))
    }
    
    func testThatItCallsDidFailEmailUpdateWithUnknownError() {
        
        // GIVEN
        let credentials = ZMEmailCredentials(email: "mario@example.com", password: "princess")
        try! self.userProfileUpdateStatus.requestSettingEmailAndPassword(credentials: credentials)
        self.userProfileUpdateStatus.didUpdatePasswordSuccessfully()
        
        // WHEN
        let request = self.sut.nextRequest()
        request?.complete(with: self.errorResponse())
        
        // THEN
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        XCTAssertEqual(self.userProfileUpdateStatus.recordedDidFailEmailUpdate.count, 1)
        guard let error = self.userProfileUpdateStatus.recordedDidFailEmailUpdate.first as? NSError else { return }
        XCTAssertEqual(error.code, Int(ZMUserSessionErrorCode.unkownError.rawValue))
        
    }
}

// MARK: - Helpers
extension UserProfileUpdateRequestStrategyTests {
    
    func errorResponse() -> ZMTransportResponse {
        return ZMTransportResponse(payload: nil, httpStatus: 400, transportSessionError: nil)
    }
    
    func badRequestResponse() -> ZMTransportResponse {
        return ZMTransportResponse(payload: ["label":"bad-request"] as NSDictionary, httpStatus: 400, transportSessionError: nil)
    }
    
    func keyExistsResponse() -> ZMTransportResponse {
        return ZMTransportResponse(payload: ["label":"key-exists"] as NSDictionary, httpStatus: 409, transportSessionError: nil)
    }
    
    func invalidPhoneNumberResponse() -> ZMTransportResponse {
        return ZMTransportResponse(payload: ["label":"invalid-phone"] as NSDictionary, httpStatus: 400, transportSessionError: nil)
    }
    
    func invalidEmailResponse() -> ZMTransportResponse {
        return ZMTransportResponse(payload: ["label":"invalid-email"] as NSDictionary, httpStatus: 400, transportSessionError: nil)
    }
    
    func invalidCredentialsResponse() -> ZMTransportResponse {
        return ZMTransportResponse(payload: ["label":"invalid-credentials"] as NSDictionary, httpStatus: 403, transportSessionError: nil)
    }
    
    func successResponse() -> ZMTransportResponse {
        return ZMTransportResponse(payload: nil, httpStatus: 200, transportSessionError: nil)
    }
}

class TestUserProfileUpdateStatus : UserProfileUpdateStatus {
    
    var recordedDidFailEmailUpdate : [Error] = []
    var recordedDidUpdateEmailSuccessfully = 0
    var recordedDidChangePhoneSuccesfully = 0
    var recordedDidFailPasswordUpdate = 0
    var recordedDidUpdatePasswordSuccessfully = 0
    var recordedDidFailChangingPhone : [Error] = []
    var recordedDidRequestPhoneVerificationCodeSuccessfully = 0
    var recordedDidFailPhoneVerificationCodeRequest : [Error] = []
    
    override func didFailEmailUpdate(error: Error) {
        recordedDidFailEmailUpdate.append(error)
        super.didFailEmailUpdate(error: error)
    }
    
    override func didUpdateEmailSuccessfully() {
        recordedDidUpdateEmailSuccessfully += 1
        super.didUpdateEmailSuccessfully()
    }
    
    override func didChangePhoneSuccesfully() {
        recordedDidChangePhoneSuccesfully += 1
        super.didChangePhoneSuccesfully()
    }
    
    override func didFailPasswordUpdate() {
        recordedDidFailPasswordUpdate += 1
        super.didFailPasswordUpdate()
    }
    
    override func didUpdatePasswordSuccessfully() {
        recordedDidUpdatePasswordSuccessfully += 1
        super.didUpdatePasswordSuccessfully()
    }

    override func didFailChangingPhone(error: Error) {
        recordedDidFailChangingPhone.append(error)
        super.didFailChangingPhone(error: error)
    }
    
    override func didRequestPhoneVerificationCodeSuccessfully() {
        recordedDidRequestPhoneVerificationCodeSuccessfully += 1
        super.didRequestPhoneVerificationCodeSuccessfully()
    }
    
    override func didFailPhoneVerificationCodeRequest(error: Error) {
        recordedDidFailPhoneVerificationCodeRequest.append(error)
        super.didFailPhoneVerificationCodeRequest(error: error)
    }
}
