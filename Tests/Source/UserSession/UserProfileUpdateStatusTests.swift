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
import ZMUtilities

class UserProfileUpdateStatusTests : MessagingTest {
    
    var observerToken : AnyObject!
    
    var sut : UserProfileUpdateStatus! = nil
    
    fileprivate var observer : TestUserProfileUpdateObserver! = nil
    
    fileprivate var newRequestObserver : OperationLoopNewRequestObserver!
    
    /// Number of time the new request callback was invoked
    var newRequestCallbackCount : Int {
        return newRequestObserver.notifications.count
    }
    
    override func setUp() {
        super.setUp()
        self.newRequestObserver = OperationLoopNewRequestObserver()
        self.observer = TestUserProfileUpdateObserver()
        self.sut = UserProfileUpdateStatus(managedObjectContext: self.uiMOC)
        self.observerToken = self.sut.add(observer: self.observer)
    }
    
    override func tearDown() {
        self.newRequestObserver = nil
        self.sut.removeObserver(token: self.observerToken!)
        self.sut = nil
        self.observer = nil
        super.tearDown()
    }
}

// MARK: - Set email and password
extension UserProfileUpdateStatusTests {
    
    func testThatItIsNotUpdatingEmail() {
        XCTAssertFalse(sut.currentlySettingEmail)
        XCTAssertFalse(sut.currentlySettingPassword)
        XCTAssertNil(self.sut.emailCredentials())
    }
    
    func testThatItPreparesForEmailAndPasswordChangeIfTheSelfUserHasNoEmail() {
        
        // GIVEN
        let selfUser = ZMUser.selfUser(in: self.uiMOC)
        XCTAssertNil(selfUser.emailAddress)
        let credentials = ZMEmailCredentials(email: "foo@example.com", password: "%$#@11111")
        
        // WHEN
        do {
            try self.sut.requestSettingEmailAndPassword(credentials: credentials)
        } catch {
            XCTFail()
            return
        }
        
        // THEN
        XCTAssertFalse(self.sut.currentlySettingEmail)
        XCTAssertTrue(self.sut.currentlySettingPassword)
        XCTAssertNil(self.sut.emailCredentials())
        XCTAssertEqual(self.newRequestCallbackCount, 1)
    }
    
    func testThatItReturnsErrorWhenPreparingForEmailAndPasswordChangeAndUserUserHasEmail() {
        
        // GIVEN
        let selfUser = ZMUser.selfUser(in: self.uiMOC)
        selfUser.emailAddress = "my@fo.example.com"
        let credentials = ZMEmailCredentials(email: "foo@example.com", password: "%$#@11111")
        
        // WHEN
        do {
            try self.sut.requestSettingEmailAndPassword(credentials: credentials)
            XCTFail("Should have thrown")
        } catch {
            return
        }
    }
    
    func testThatItCanCancelSettingEmailAndPassword() {
        
        // GIVEN
        let credentials = ZMEmailCredentials(email: "foo@example.com", password: "%$#@11111")
        try? self.sut.requestSettingEmailAndPassword(credentials: credentials)
        
        // WHEN
        self.sut.cancelSettingEmailAndPassword()
        
        // THEN
        XCTAssertFalse(sut.currentlySettingEmail)
        XCTAssertFalse(sut.currentlySettingPassword)
        XCTAssertNil(self.sut.emailCredentials())
    }
    
    func testThatItNeedsToSetEmailAfterSuccessfullySettingPassword() {
        
        // GIVEN
        let credentials = ZMEmailCredentials(email: "foo@example.com", password: "%$#@11111")
        try? self.sut.requestSettingEmailAndPassword(credentials: credentials)
        
        // WHEN
        self.sut.didUpdatePasswordSuccessfully()
        
        // THEN
        XCTAssertTrue(sut.currentlySettingEmail)
        XCTAssertFalse(sut.currentlySettingPassword)
        XCTAssertNil(self.sut.emailCredentials())

    }
    
    func testThatItCompletesAfterSuccessfullySettingPasswordAndEmail() {
        
        // GIVEN
        let credentials = ZMEmailCredentials(email: "foo@example.com", password: "%$#@11111")
        try? self.sut.requestSettingEmailAndPassword(credentials: credentials)

        
        // WHEN
        self.sut.didUpdatePasswordSuccessfully()
        self.sut.didUpdateEmailSuccessfully()
        
        // THEN
        XCTAssertFalse(sut.currentlySettingEmail)
        XCTAssertFalse(sut.currentlySettingPassword)
        XCTAssertEqual(self.sut.emailCredentials(), credentials)
    }
    
    func testThatItNotifiesAfterSuccessfullySettingEmail() {
        
        // GIVEN
        let credentials = ZMEmailCredentials(email: "foo@example.com", password: "%$#@11111")
        try? self.sut.requestSettingEmailAndPassword(credentials: credentials)
        
        // WHEN
        self.sut.didUpdatePasswordSuccessfully()
        self.sut.didUpdateEmailSuccessfully()
        
        // THEN
        XCTAssertEqual(self.observer.invokedCallbacks.count, 1)
        guard let first = self.observer.invokedCallbacks.first else { return }
        switch first {
        case .emailDidSendVerification:
            break
        default:
            XCTFail()
        }
    }
    
    func testThatItIsNotSettingEmailAnymoreAsSoonAsTheSelfUserHasEmail() {
        
        // GIVEN
        let credentials = ZMEmailCredentials(email: "foo@example.com", password: "%$#@11111")
        try? self.sut.requestSettingEmailAndPassword(credentials: credentials)

        
        // WHEN
        let selfUser = ZMUser.selfUser(in: self.uiMOC)
        selfUser.emailAddress = "bar@example.com"
        
        // THEN
        XCTAssertFalse(self.sut.currentlySettingEmail)
        XCTAssertFalse(self.sut.currentlySettingPassword)
    }
    
    func testThatItIsNotSettingPasswordAnymoreAsSoonAsTheSelfUserHasEmail() {
        
        // GIVEN
        let credentials = ZMEmailCredentials(email: "foo@example.com", password: "%$#@11111")
        try? self.sut.requestSettingEmailAndPassword(credentials: credentials)
        self.sut.didUpdatePasswordSuccessfully()

        // WHEN
        let selfUser = ZMUser.selfUser(in: self.uiMOC)
        selfUser.emailAddress = "bar@example.com"
        
        // THEN
        XCTAssertFalse(self.sut.currentlySettingEmail)
        XCTAssertFalse(self.sut.currentlySettingPassword)
    }
    
    func testThatItIsNotSettingEmailAndPasswordAnymoreIfItFailsToUpdatePassword() {
        
        // GIVEN
        let credentials = ZMEmailCredentials(email: "foo@example.com", password: "%$#@11111")
        try? self.sut.requestSettingEmailAndPassword(credentials: credentials)
        
        // WHEN
        self.sut.didFailPasswordUpdate()
        
        // THEN
        XCTAssertFalse(self.sut.currentlySettingEmail)
        XCTAssertFalse(self.sut.currentlySettingPassword)
        XCTAssertNil(self.sut.emailCredentials())
    }
    
    func testThatItNotifiesIfItFailsToUpdatePassword() {
        
        // GIVEN
        let credentials = ZMEmailCredentials(email: "foo@example.com", password: "%$#@11111")
        try? self.sut.requestSettingEmailAndPassword(credentials: credentials)
        
        // WHEN
        self.sut.didFailPasswordUpdate()
        
        // THEN
        XCTAssertEqual(self.observer.invokedCallbacks.count, 1)
        guard let first = self.observer.invokedCallbacks.first else { return }
        switch first {
        case .passwordUpdateDidFail:
            break
        default:
            XCTFail()
        }
    }
    
    func testThatItIsNotSettingEmailAnymoreIfItFailsToUpdateEmail() {
        
        // GIVEN
        let credentials = ZMEmailCredentials(email: "foo@example.com", password: "%$#@11111")
        try? self.sut.requestSettingEmailAndPassword(credentials: credentials)
        let error = NSError(domain: "zmessaging", code: 100, userInfo: nil)
        
        // WHEN
        self.sut.didUpdatePasswordSuccessfully()
        self.sut.didFailEmailUpdate(error: error)
        
        // THEN
        XCTAssertFalse(self.sut.currentlySettingEmail)
        XCTAssertFalse(self.sut.currentlySettingPassword)
        XCTAssertNil(self.sut.emailCredentials())
    }
    
    func testThatItNotifiesIfItFailsToUpdateEmail() {
        
        // GIVEN
        let error = NSError(domain: "zmessaging", code: 100, userInfo: nil)
        let credentials = ZMEmailCredentials(email: "foo@example.com", password: "%$#@11111")
        try? self.sut.requestSettingEmailAndPassword(credentials: credentials)
        
        // WHEN
        self.sut.didUpdatePasswordSuccessfully()
        self.sut.didFailEmailUpdate(error: error)
        
        // THEN
        XCTAssertEqual(self.observer.invokedCallbacks.count, 1)
        guard let first = self.observer.invokedCallbacks.first else { return }
        switch first {
        case .emailUpdateDidFail(let _error):
            XCTAssertEqual(error, _error as NSError)
        default:
            XCTFail()
        }
    }
}

// MARK: - Credentials provider
extension UserProfileUpdateStatusTests {
    
    func testThatItDoesNotReturnCredentialsIfOnlyPasswordIsVerified() {
        
        // GIVEN
        let credentials = ZMEmailCredentials(email: "foo@example.com", password: "%$#@11111")
        
        // WHEN
        try? self.sut.requestSettingEmailAndPassword(credentials: credentials)
        self.sut.didUpdatePasswordSuccessfully()
        
        // THEN
        XCTAssertNil(self.sut.emailCredentials())
    }
    
    func testThatItDoesNotReturnCredentialsIfOnlyEmailIsVerified() {
        
        // GIVEN
        let credentials = ZMEmailCredentials(email: "foo@example.com", password: "%$#@11111")
        
        // WHEN
        try? self.sut.requestSettingEmailAndPassword(credentials: credentials)
        self.sut.didUpdateEmailSuccessfully()
        
        // THEN
        XCTAssertNil(self.sut.emailCredentials())
    }
    
    func testThatItReturnsCredentialsIfEmailAndPasswordAreVerified() {
        
        // GIVEN
        let credentials = ZMEmailCredentials(email: "foo@example.com", password: "%$#@11111")
        
        // WHEN
        try? self.sut.requestSettingEmailAndPassword(credentials: credentials)
        self.sut.didUpdatePasswordSuccessfully()
        self.sut.didUpdateEmailSuccessfully()
        
        // THEN
        XCTAssertEqual(self.sut.emailCredentials(), credentials)
    }
    
    func testThatItDeletesCredentials() {
        
        // GIVEN
        let credentials = ZMEmailCredentials(email: "foo@example.com", password: "%$#@11111")
        try? self.sut.requestSettingEmailAndPassword(credentials: credentials)
        self.sut.didUpdatePasswordSuccessfully()
        self.sut.didUpdateEmailSuccessfully()
        
        // WHEN
        self.sut.credentialsMayBeCleared()
        
        // THEN
        XCTAssertNil(self.sut.emailCredentials())
    }
}

// MARK: - Phone number code request
extension UserProfileUpdateStatusTests {

    func testThatItIsNotRequestingPhoneVerificationAtStart() {
        XCTAssertFalse(self.sut.currentlyRequestingPhoneVerificationCode)
    }
    
    func testThatItPreparesForRequestingPhoneVerificationCodeForRegistration() {
        
        // GIVEN
        let phoneNumber = "+1555234342"

        // WHEN
        self.sut.requestPhoneVerificationCode(phoneNumber: phoneNumber)
        
        // THEN
        XCTAssertTrue(self.sut.currentlyRequestingPhoneVerificationCode)
        XCTAssertEqual(self.sut.phoneNumberForWhichCodeIsRequested, phoneNumber)
        XCTAssertEqual(self.newRequestCallbackCount, 1)

    }
    
    func testThatItCompletesRequestingPhoneVerificationCode() {
        
        // GIVEN
        let phoneNumber = "+1555234342"
        
        // WHEN
        self.sut.requestPhoneVerificationCode(phoneNumber: phoneNumber)
        self.sut.didRequestPhoneVerificationCodeSuccessfully()
        
        // THEN
        XCTAssertFalse(self.sut.currentlyRequestingPhoneVerificationCode)
        XCTAssertNil(self.sut.phoneNumberForWhichCodeIsRequested)
        
    }
    
    func testThatItFailsRequestingPhoneVerificationCode() {
        
        // GIVEN
        let error = NSError(domain: "zmessaging", code: 100, userInfo: nil)
        let phoneNumber = "+1555234342"
        
        // WHEN
        self.sut.requestPhoneVerificationCode(phoneNumber: phoneNumber)
        self.sut.didFailPhoneVerificationCodeRequest(error: error)
        
        // THEN
        XCTAssertFalse(self.sut.currentlyRequestingPhoneVerificationCode)
        XCTAssertNil(self.sut.phoneNumberForWhichCodeIsRequested)
        
    }
    
    func testThatItNotifiesAfterCompletingRequestingPhoneVerificationCode() {
        
        // GIVEN
        let phoneNumber = "+1555234342"
        
        // WHEN
        self.sut.requestPhoneVerificationCode(phoneNumber: phoneNumber)
        self.sut.didRequestPhoneVerificationCodeSuccessfully()
        
        // THEN
        XCTAssertEqual(self.observer.invokedCallbacks.count, 1)
        guard let first = self.observer.invokedCallbacks.first else { return }
        switch first {
        case .phoneNumberVerificationCodeRequestDidSucceed:
            break
        default:
            XCTFail()
        }
    }
    
    func testThatItNotifiesAfterFailureInRequestingPhoneVerificationCode() {
        
        // GIVEN
        let error = NSError(domain: "zmessaging", code: 100, userInfo: nil)
        let phoneNumber = "+1555234342"
        
        // WHEN
        self.sut.requestPhoneVerificationCode(phoneNumber: phoneNumber)
        self.sut.didFailPhoneVerificationCodeRequest(error: error)
        
        // THEN
        XCTAssertEqual(self.observer.invokedCallbacks.count, 1)
        guard let first = self.observer.invokedCallbacks.first else { return }
        switch first {
        case .phoneNumberVerificationCodeRequestDidFail(let _error):
            XCTAssertEqual(error, _error as NSError)
        default:
            XCTFail()
        }
    }
}

// MARK: - Phone number verification
extension UserProfileUpdateStatusTests {
    
    func testThatItIsNotUpdatingPhoneNumberAtStart() {
        XCTAssertFalse(self.sut.currentlySettingPhone)
    }
    
    func testThatItPreparesForPhoneChangeWithCredentials() {
        
        // GIVEN
        let credentials = ZMPhoneCredentials(phoneNumber: "+1555234342", verificationCode: "234555")
        
        // WHEN
        self.sut.requestPhoneNumberChange(credentials: credentials)
        
        // THEN
        XCTAssertTrue(self.sut.currentlySettingPhone)
        XCTAssertEqual(self.sut.phoneNumberToSet, credentials)
        XCTAssertEqual(self.newRequestCallbackCount, 1)

    }
    
    func testThatItCompletesUpdatingPhoneNumber() {
        
        // GIVEN
        let credentials = ZMPhoneCredentials(phoneNumber: "+1555234342", verificationCode: "234555")
        
        // WHEN
        self.sut.requestPhoneNumberChange(credentials: credentials)
        self.sut.didChangePhoneSuccesfully()
        
        // THEN
        XCTAssertFalse(self.sut.currentlySettingPhone)
        XCTAssertNil(self.sut.phoneNumberToSet)
        
    }
    
    func testThatItFailsUpdatingPhoneNumber() {
        
        // GIVEN
        let error = NSError(domain: "zmessaging", code: 100, userInfo: nil)
        let credentials = ZMPhoneCredentials(phoneNumber: "+1555234342", verificationCode: "234555")
        
        // WHEN
        self.sut.requestPhoneNumberChange(credentials: credentials)
        self.sut.didFailChangingPhone(error: error)
        
        // THEN
        XCTAssertFalse(self.sut.currentlySettingPhone)
        XCTAssertNil(self.sut.phoneNumberToSet)
        
    }
    
    func testThatItNotifiesAfterFailureInUpdatingPhoneNumber() {
        
        // GIVEN
        let credentials = ZMPhoneCredentials(phoneNumber: "+1555234342", verificationCode: "234555")
        let error = NSError(domain: "zmessaging", code: 100, userInfo: nil)
        
        // WHEN
        self.sut.requestPhoneNumberChange(credentials: credentials)
        self.sut.didFailChangingPhone(error: error)
        
        // THEN
        XCTAssertEqual(self.observer.invokedCallbacks.count, 1)
        guard let first = self.observer.invokedCallbacks.first else { return }
        switch first {
        case .phoneNumberChangeDidFail(let _error):
            XCTAssertEqual(error, _error as NSError)
        default:
            XCTFail()
        }
    }
}

// MARK: - Check handle availability
extension UserProfileUpdateStatusTests {
    
    func testThatItIsNotCheckingAvailabilityAtCreation() {
        XCTAssertFalse(self.sut.currentlyCheckingHandleAvailability)
    }
    
    func testThatItPreparesForCheckingHandleAvailability() {
        
        // GIVEN
        let handle = "foobar"
        
        // WHEN
        self.sut.requestCheckHandleAvailability(handle: handle)
        
        // THEN
        XCTAssertEqual(self.sut.handleToCheck, handle)
        XCTAssertTrue(self.sut.currentlyCheckingHandleAvailability)
        XCTAssertEqual(newRequestObserver.notifications.count, 1)
    }
    
    func testThatItCompletesCheckingHandleAvailability_Available() {
        
        // GIVEN
        let handle = "foobar"
        
        // WHEN
        self.sut.requestCheckHandleAvailability(handle: handle)
        self.sut.didNotFindHandle(handle: handle)
        
        // THEN
        XCTAssertNil(self.sut.handleToCheck)
        XCTAssertFalse(self.sut.currentlyCheckingHandleAvailability)
    }
    
    func testThatItCompletesCheckingHandleAvailability_NotAvailable() {
        
        // GIVEN
        let handle = "foobar"
        
        // WHEN
        self.sut.requestCheckHandleAvailability(handle: handle)
        self.sut.didFetchHandle(handle: handle)
        
        // THEN
        XCTAssertNil(self.sut.handleToCheck)
        XCTAssertFalse(self.sut.currentlyCheckingHandleAvailability)
    }
    
    func testThatItFailsCheckingHandleAvailability() {
        
        // GIVEN
        let handle = "foobar"
        
        // WHEN
        self.sut.requestCheckHandleAvailability(handle: handle)
        self.sut.didFailRequestToFetchHandle(handle: handle)
        
        // THEN
        XCTAssertNil(self.sut.handleToCheck)
        XCTAssertFalse(self.sut.currentlyCheckingHandleAvailability)
    }
    
    func testThatItDoesCompletesCheckingHandleAvailabilityIfDifferentHandle_Available() {
        
        // GIVEN
        let handle = "foobar"
        
        // WHEN
        self.sut.requestCheckHandleAvailability(handle: handle)
        self.sut.didNotFindHandle(handle: "other")
        
        // THEN
        XCTAssertEqual(self.sut.handleToCheck, handle)
        XCTAssertTrue(self.sut.currentlyCheckingHandleAvailability)
    }
    
    func testThatItDoesCompletesCheckingHandleAvailabilityIfDifferentHandle_NotAvailable() {
        
        // GIVEN
        let handle = "foobar"
        
        // WHEN
        self.sut.requestCheckHandleAvailability(handle: handle)
        self.sut.didFetchHandle(handle: "other")
        
        // THEN
        XCTAssertEqual(self.sut.handleToCheck, handle)
        XCTAssertTrue(self.sut.currentlyCheckingHandleAvailability)
    }
    
    func testThatItDoesCompletesCheckingHandleAvailabilityIfDifferentHandle_Failed() {
        
        // GIVEN
        let handle = "foobar"
        
        // WHEN
        self.sut.requestCheckHandleAvailability(handle: handle)
        self.sut.didFailRequestToFetchHandle(handle: "other")
        
        // THEN
        XCTAssertEqual(self.sut.handleToCheck, handle)
        XCTAssertTrue(self.sut.currentlyCheckingHandleAvailability)
    }
    
    func testThatItNotifiesAfterCheckingHandleAvailability_Available() {
        
        // GIVEN
        let handle = "foobar"
        
        // WHEN
        self.sut.requestCheckHandleAvailability(handle: "other")
        self.sut.didNotFindHandle(handle: handle)
        
        // THEN
        XCTAssertEqual(self.observer.invokedCallbacks.count, 1)
        guard let first = self.observer.invokedCallbacks.first else { return }
        switch first {
        case .didCheckAvailabilityOfHandle(handle: handle, available: true):
            break
        default:
            XCTFail()
        }
    }
    
    func testThatItNotifiesAfterCheckingHandleAvailability_NotAvailable() {
        
        // GIVEN
        let handle = "foobar"
        
        // WHEN
        self.sut.requestCheckHandleAvailability(handle: "other")
        self.sut.didFetchHandle(handle: handle)
        
        // THEN
        XCTAssertEqual(self.observer.invokedCallbacks.count, 1)
        guard let first = self.observer.invokedCallbacks.first else { return }
        switch first {
        case .didCheckAvailabilityOfHandle(handle: handle, available: false):
            break
        default:
            XCTFail()
        }
    }
    
    func testThatItNotifiesAfterFailingCheckingHandleAvailability() {
        
        // GIVEN
        let handle = "foobar"
        
        // WHEN
        self.sut.requestCheckHandleAvailability(handle: "other")
        self.sut.didFailRequestToFetchHandle(handle: handle)
        
        // THEN
        XCTAssertEqual(self.observer.invokedCallbacks.count, 1)
        guard let first = self.observer.invokedCallbacks.first else { return }
        switch first {
        case .didFailToCheckAvailabilityOfHandle(handle: handle):
            break
        default:
            XCTFail()
        }
    }
}

// MARK: - Set handle
extension UserProfileUpdateStatusTests {
    
    func testThatItIsNotSettingHandleyAtCreation() {
        XCTAssertFalse(self.sut.currentlySettingHandle)
    }
    
    func testThatItPreparesForSettingHandle() {
        
        // GIVEN
        let handle = "foobar"
        
        // WHEN
        self.sut.requestSettingHandle(handle: handle)
        
        // THEN
        XCTAssertEqual(self.sut.handleToSet, handle)
        XCTAssertTrue(self.sut.currentlySettingHandle)
        XCTAssertEqual(newRequestObserver.notifications.count, 1)
    }
    
    func testThatItSetsHandleSuccessfully() {
        
        // GIVEN
        let handle = "foobar"
        let selfUser = ZMUser.selfUser(in: self.sut.managedObjectContext)
        XCTAssertNotNil(selfUser)
        
        // WHEN
        self.sut.requestSettingHandle(handle: handle)
        self.sut.didSetHandle()
        
        // THEN
        XCTAssertNil(self.sut.handleToSet)
        XCTAssertFalse(self.sut.currentlySettingHandle)
        XCTAssertEqual(selfUser.handle, handle)
    }
    
    func testThatItCancelsSetHandle() {
        
        // GIVEN
        let handle = "foobar"
        let selfUser = ZMUser.selfUser(in: self.sut.managedObjectContext)
        
        // WHEN
        self.sut.requestSettingHandle(handle: handle)
        self.sut.cancelSettingHandle()
        
        // THEN
        XCTAssertNil(self.sut.handleToSet)
        XCTAssertFalse(self.sut.currentlySettingHandle)
        XCTAssertNil(selfUser.handle)
    }
    
    func testThatItFailsToSetHandle() {
        
        // GIVEN
        let handle = "foobar"
        let selfUser = ZMUser.selfUser(in: self.sut.managedObjectContext)
        
        // WHEN
        self.sut.requestSettingHandle(handle: handle)
        self.sut.didFailToSetHandle()
        
        // THEN
        XCTAssertNil(self.sut.handleToSet)
        XCTAssertFalse(self.sut.currentlySettingHandle)
        XCTAssertNil(selfUser.handle)
    }
    
    func testThatItFailsToSetHandleBecauseExisting() {
        
        // GIVEN
        let handle = "foobar"
        let selfUser = ZMUser.selfUser(in: self.sut.managedObjectContext)
        
        // WHEN
        self.sut.requestSettingHandle(handle: handle)
        self.sut.didFailToSetAlreadyExistingHandle()
        
        // THEN
        XCTAssertNil(self.sut.handleToSet)
        XCTAssertFalse(self.sut.currentlySettingHandle)
        XCTAssertNil(selfUser.handle)
    }
    
    func testThatItDoesNotSetTheHandleOnSelfUserIfCompletedAfterCancelling() {
        
        // GIVEN
        let handle = "foobar"
        let selfUser = ZMUser.selfUser(in: self.sut.managedObjectContext)
        
        // WHEN
        self.sut.requestSettingHandle(handle: handle)
        self.sut.cancelSettingHandle()
        self.sut.didSetHandle()
        
        // THEN
        XCTAssertNil(selfUser.handle)
    }
    
    func testThatItNotifyWhenSetingHandleSuccessfully() {
        
        // GIVEN
        let handle = "foobar"
        
        // WHEN
        self.sut.requestSettingHandle(handle: handle)
        self.sut.didSetHandle()
        
        // THEN
        XCTAssertEqual(self.observer.invokedCallbacks.count, 1)
        guard let first = self.observer.invokedCallbacks.first else { return }
        switch first {
        case .didSetHandle:
            break
        default:
            XCTFail()
        }
    }
    
    func testThatItNotifyWhenItFailsToSetHandle() {
        
        // GIVEN
        let handle = "foobar"
        
        // WHEN
        self.sut.requestSettingHandle(handle: handle)
        self.sut.didFailToSetHandle()
        
        // THEN
        XCTAssertEqual(self.observer.invokedCallbacks.count, 1)
        guard let first = self.observer.invokedCallbacks.first else { return }
        switch first {
        case .didFailToSetHandle:
            break
        default:
            XCTFail()
        }
    }
    
    func testThatItNotifiesWhenItFailsToSetHandleBecauseExisting() {
        
        // GIVEN
        let handle = "foobar"
        
        // WHEN
        self.sut.requestSettingHandle(handle: handle)
        self.sut.didFailToSetAlreadyExistingHandle()
        
        // THEN
        XCTAssertEqual(self.observer.invokedCallbacks.count, 1)
        guard let first = self.observer.invokedCallbacks.first else { return }
        switch first {
        case .didFailToSetHandleBecauseExisting:
            break
        default:
            XCTFail()
        }
    }
}


// MARK: - Helpers
class TestUserProfileUpdateObserver : NSObject, UserProfileUpdateObserver {
    
    var invokedCallbacks : [zmessaging.UserProfileUpdateNotificationType] = []
    
    func passwordUpdateRequestDidFail() {
        invokedCallbacks.append(.passwordUpdateDidFail)
    }

    func emailUpdateDidFail(_ error: Error!) {
        invokedCallbacks.append(.emailUpdateDidFail(error: error))
    }
    
    func didSentVerificationEmail() {
        invokedCallbacks.append(.emailDidSendVerification)
    }
    
    func phoneNumberVerificationCodeRequestDidFail(_ error: Error!) {
        invokedCallbacks.append(.phoneNumberVerificationCodeRequestDidFail(error: error))
    }
    
    func phoneNumberVerificationCodeRequestDidSucceed() {
        invokedCallbacks.append(.phoneNumberVerificationCodeRequestDidSucceed)
    }
    
    func phoneNumberChangeDidFail(_ error: Error!) {
        invokedCallbacks.append(.phoneNumberChangeDidFail(error: error))
    }
    
    func didCheckAvailiabilityOfHandle(handle: String, available: Bool) {
        invokedCallbacks.append(.didCheckAvailabilityOfHandle(handle: handle, available: available))
    }
    
    func didFailToCheckAvailabilityOfHandle(handle: String) {
        invokedCallbacks.append(.didFailToCheckAvailabilityOfHandle(handle: handle))
    }
    
    func didFailToSetHandleBecauseExisting() {
        invokedCallbacks.append(.didFailToSetHandleBecauseExisting)
    }
    
    func didFailToSetHandle() {
        invokedCallbacks.append(.didFailToSetHandle)
    }
    
    func didSetHandle() {
        invokedCallbacks.append(.didSetHandle)
    }
    
    func clearReceivedCallbacks() {
        self.invokedCallbacks = []
    }
    
}

