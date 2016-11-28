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
        self.userProfileUpdateStatus = TestUserProfileUpdateStatus(managedObjectContext: self.uiMOC)
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
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        
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
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        
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
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        
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
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        self.userProfileUpdateStatus.didUpdatePasswordSuccessfully()
        
        // WHEN
        let request = self.sut.nextRequest()
        
        // THEN
        let expected = ZMTransportRequest(path: "/self/email", method: .methodPUT, payload: [
            "email":credentials.email!
            ] as NSDictionary)
        XCTAssertEqual(request, expected)
        
    }
    
    func testThatItCreatesARequestToCheckHandleAvailability() {
        
        // GIVEN
        let handle = "martha"
        self.userProfileUpdateStatus.requestCheckHandleAvailability(handle: handle)
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        
        // WHEN
        let request = self.sut.nextRequest()
        
        // THEN
        let expected = ZMTransportRequest(path: "/users/handles/\(handle)", method: .methodHEAD, payload: nil)
        XCTAssertEqual(request, expected)
    }
    
    func testThatItCreatesARequestToSetHandle() {
        
        // GIVEN
        let handle = "martha"
        self.userProfileUpdateStatus.requestSettingHandle(handle: handle)
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        
        // WHEN
        let request = self.sut.nextRequest()
        
        // THEN
        let payload : NSDictionary = ["handle" : handle]
        let expected = ZMTransportRequest(path: "/self/handle", method: .methodPUT, payload: payload)
        XCTAssertEqual(request, expected)
    }
    
    func testThatItCreatesARequestToFindHandleSuggestion() {
        
        // GIVEN
        self.userProfileUpdateStatus.suggestHandles()
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        guard let handles = self.userProfileUpdateStatus.suggestedHandlesToCheck?.joined(separator: ",") else {
            XCTFail()
            return
        }
        
        // WHEN
        let possibleRequest = self.sut.nextRequest()
        
        // THEN
        guard let request = possibleRequest else {
            XCTFail()
            return
        }
        
        XCTAssertEqual(request.method, .methodGET)
        XCTAssertTrue(request.path.hasPrefix("/users?handles=\(handles)"))
    }
}

// MARK: - Parsing response
extension UserProfileUpdateRequestStrategyTests {
    
    func testThatItCallsDidRequestPhoneVerificationCodeSuccessfully() {
        
        // GIVEN
        let phone = "+155523123123"
        self.userProfileUpdateStatus.requestPhoneVerificationCode(phoneNumber: phone)
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        
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
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        
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
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        
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
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        
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
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        
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
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        
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
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        
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
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        
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
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        
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
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.2))
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
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.2))
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
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.2))
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
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.2))
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
    
    func testThatItCallsDidFetchHandle() {
        
        // GIVEN
        let handle = "martha"
        self.userProfileUpdateStatus.requestCheckHandleAvailability(handle: handle)
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        
        // WHEN
        let request = self.sut.nextRequest()
        request?.complete(with: self.successResponse(path: request?.path))
        
        // THEN
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        XCTAssertEqual(self.userProfileUpdateStatus.recordedDidFetchHandle, [handle])
    }
    
    func testThatItCallsDidNotFindHandle() {
        
        // GIVEN
        let handle = "martha"
        self.userProfileUpdateStatus.requestCheckHandleAvailability(handle: handle)
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        
        // WHEN
        let request = self.sut.nextRequest()
        request?.complete(with: self.notFoundResponse(path: request!.path))
        
        // THEN
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        XCTAssertEqual(self.userProfileUpdateStatus.recordedDidNotFindHandle, [handle])
    }
    
    func testThatItCallsFailedToCheckHandleAvailability() {
        
        // GIVEN
        let handle = "martha"
        self.userProfileUpdateStatus.requestCheckHandleAvailability(handle: handle)
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        
        // WHEN
        let request = self.sut.nextRequest()
        request?.complete(with: self.errorResponse(path: request?.path))
        
        // THEN
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        XCTAssertEqual(self.userProfileUpdateStatus.recordedDidFailRequestToFetchHandle, [handle])
    }
    
    func testThatItCallsSuccessSetHandle() {
        
        // GIVEN
        let handle = "martha"
        self.userProfileUpdateStatus.requestSettingHandle(handle: handle)
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        
        // WHEN
        let request = self.sut.nextRequest()
        request?.complete(with: self.successResponse())
        
        // THEN
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        XCTAssertEqual(self.userProfileUpdateStatus.recordedDidSetHandle, 1)
    }
    
    func testThatItCallsFailedToSetHandle() {
        
        // GIVEN
        let handle = "martha"
        self.userProfileUpdateStatus.requestSettingHandle(handle: handle)
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        
        // WHEN
        let request = self.sut.nextRequest()
        request?.complete(with: self.errorResponse())
        
        // THEN
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        XCTAssertEqual(self.userProfileUpdateStatus.recordedDidFailToSetHandle, 1)
    }
    
    func testThatItCallsFailedToSetHandleBecauseExisting() {
        
        // GIVEN
        let handle = "martha"
        self.userProfileUpdateStatus.requestSettingHandle(handle: handle)
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        
        // WHEN
        let request = self.sut.nextRequest()
        request?.complete(with: self.keyExistsResponse())
        
        // THEN
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        XCTAssertEqual(self.userProfileUpdateStatus.recordedDidFailToSetAlreadyExistingHandle , 1)
    }
    
    func testThatItCallsDidFinddHandleSuggestion() {
        
        // GIVEN
        self.userProfileUpdateStatus.suggestHandles()
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        guard let handles = self.userProfileUpdateStatus.suggestedHandlesToCheck, handles.count > 10 else {
            XCTFail()
            return
        }
        let expectedHandle = handles[8]
        
        // WHEN
        let request = self.sut.nextRequest()
        let handlesInResponse = handles.filter { $0 != expectedHandle }
        request?.complete(with: self.userProfileResponse(handles: handlesInResponse))
        
        // THEN
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        XCTAssertEqual(self.userProfileUpdateStatus.recordedDidFindHandleSuggestion, [expectedHandle])
    }
    
    
    func testThatItCallsFailedToFindHandleSuggestionIfAllHandlesArePresent() {
        
        // GIVEN
        self.userProfileUpdateStatus.suggestHandles()
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        guard let handles = self.userProfileUpdateStatus.suggestedHandlesToCheck else {
            XCTFail()
            return
        }
        
        // WHEN
        let request = self.sut.nextRequest()
        request?.complete(with: self.userProfileResponse(handles: handles))
        
        // THEN
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        XCTAssertEqual(self.userProfileUpdateStatus.recordedDidFailToFindHandleSuggestion , 1)
    }
    
    func testThatItCallsFailedToFindHandleSuggestionInCaseOfError() {
        
        // GIVEN
        self.userProfileUpdateStatus.suggestHandles()
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        
        // WHEN
        guard let request = self.sut.nextRequest() else {
            XCTFail()
            return
        }
        request.complete(with: self.errorResponse())
        
        // THEN
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        XCTAssertEqual(self.userProfileUpdateStatus.recordedDidFailToFindHandleSuggestion , 1)
    }
}

// MARK: - Helpers
extension UserProfileUpdateRequestStrategyTests {
    
    func userProfileResponse(handles: [String]) -> ZMTransportResponse {
        
        let users = handles.map {
            return ["handle" : $0,
                    "id" : UUID.create().transportString()
            ]
        }
        return ZMTransportResponse(
            payload: users as NSArray,
            httpStatus: 200,
            transportSessionError: nil,
            headers: nil
        )
        
    }
    
    func errorResponse(path: String? = nil) -> ZMTransportResponse {
        if let url = path.flatMap(URL.init) {
            return ZMTransportResponse(originalUrl: url, httpStatus: 400, error: nil)
        }

        return ZMTransportResponse(payload: nil,
                                   httpStatus: 400,
                                   transportSessionError: nil,
                                   headers: nil
        )
    }
    
    func badRequestResponse() -> ZMTransportResponse {
        return ZMTransportResponse(payload: ["label":"bad-request"] as NSDictionary,
                                   httpStatus: 400,
                                   transportSessionError: nil)
    }
    
    func keyExistsResponse() -> ZMTransportResponse {
        return ZMTransportResponse(payload: ["label":"key-exists"] as NSDictionary,
                                   httpStatus: 409,
                                   transportSessionError: nil)
    }
    
    func invalidPhoneNumberResponse() -> ZMTransportResponse {
        return ZMTransportResponse(payload: ["label":"invalid-phone"] as NSDictionary,
                                   httpStatus: 400,
                                   transportSessionError: nil)
    }
    
    func invalidEmailResponse() -> ZMTransportResponse {
        return ZMTransportResponse(payload: ["label":"invalid-email"] as NSDictionary,
                                   httpStatus: 400,
                                   transportSessionError: nil)
    }
    
    func invalidCredentialsResponse() -> ZMTransportResponse {
        return ZMTransportResponse(payload: ["label":"invalid-credentials"] as NSDictionary,
                                   httpStatus: 403,
                                   transportSessionError: nil)
    }
    
    func successResponse(path: String? = nil) -> ZMTransportResponse {
        if let url = path.flatMap(URL.init) {
            return ZMTransportResponse(originalUrl: url, httpStatus: 200, error: nil)
        }
        return ZMTransportResponse(
            payload: nil,
            httpStatus: 200,
            transportSessionError: nil,
            headers: nil
        )
    }

    func notFoundResponse(path: String) -> ZMTransportResponse {
        return ZMTransportResponse(originalUrl: URL(string: path)!, httpStatus: 404, error: nil)
    }
}

extension ZMTransportResponse {

    convenience init(originalUrl: URL, httpStatus: Int, error: Error?) {
        let headers = ["Content-Type": "application/json"]
        let httpResponse = HTTPURLResponse(url: originalUrl, statusCode: httpStatus, httpVersion: nil, headerFields: headers)
        self.init(httpurlResponse: httpResponse!, data: nil, error: error)
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
    var recordedDidFetchHandle : [String] = []
    var recordedDidFailRequestToFetchHandle : [String] = []
    var recordedDidNotFindHandle : [String] = []
    var recordedDidSetHandle = 0
    var recordedDidFailToSetHandle = 0
    var recordedDidFailToSetAlreadyExistingHandle = 0
    var recordedDidFailToFindHandleSuggestion = 0
    var recordedDidFindHandleSuggestion : [String] = []
    
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
    
    override func didFetchHandle(handle: String) {
        recordedDidFetchHandle.append(handle)
        super.didFetchHandle(handle: handle)
    }
    
    override func didFailRequestToFetchHandle(handle: String) {
        recordedDidFailRequestToFetchHandle.append(handle)
        super.didFailRequestToFetchHandle(handle: handle)
    }
    
    override func didNotFindHandle(handle: String) {
        recordedDidNotFindHandle.append(handle)
        super.didNotFindHandle(handle: handle)
    }
    
    override func didSetHandle() {
        recordedDidSetHandle += 1
        super.didSetHandle()
    }
    
    override func didFailToSetHandle() {
        recordedDidFailToSetHandle += 1
        super.didFailToSetHandle()
    }
    
    override func didFailToSetAlreadyExistingHandle() {
        recordedDidFailToSetAlreadyExistingHandle += 1
        super.didFailToSetAlreadyExistingHandle()
    }
    
    override func didFailToFindHandleSuggestion() {
        recordedDidFailToFindHandleSuggestion += 1
        super.didFailToFindHandleSuggestion()
    }
    
    override func didFindHandleSuggestion(handle: String) {
        recordedDidFindHandleSuggestion.append(handle)
        super.didFindHandleSuggestion(handle: handle)
    }
}
