//
// Wire
// Copyright (C) 2017 Wire Swiss GmbH
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
import WireTesting
@testable import WireSyncEngine

// This enum only exist due to obj-c compatibility
@objc
public enum PreLoginAuthenticationEventObjc : Int {
    case loginCodeRequestDidSucceed
    case loginCodeRequestDidFail
    case authenticationDidSucceed
    case authenticationDidFail
    case readyToImportBackupExistingAccount
    case readyToImportBackupNewAccount
}

public typealias PreLoginAuthenticationObserverHandler = (_ event: PreLoginAuthenticationEventObjc, _ error : NSError?) -> Void

@objcMembers
public class PreLoginAuthenticationObserverToken : NSObject, PreLoginAuthenticationObserver {
    
    private var token : Any?
    private var handler : PreLoginAuthenticationObserverHandler

    public init(authenticationStatus: ZMAuthenticationStatus, handler : @escaping PreLoginAuthenticationObserverHandler) {
        self.handler = handler
        
        super.init()
        
        token = WireSyncEngine.PreLoginAuthenticationNotification.register(self, context: authenticationStatus)
    }
    
    public func loginCodeRequestDidSucceed() {
        handler(.loginCodeRequestDidSucceed, nil)
    }
    
    public func loginCodeRequestDidFail(_ error: NSError) {
        handler(.loginCodeRequestDidFail, error)
    }
    
    public func authenticationDidSucceed() {
        handler(.authenticationDidSucceed, nil)
    }
    
    public func authenticationDidFail(_ error: NSError) {
        handler(.authenticationDidFail, error)
    }

    public func authenticationReadyToImportBackup(existingAccount: Bool) {
        let value: PreLoginAuthenticationEventObjc = existingAccount ? .readyToImportBackupExistingAccount : .readyToImportBackupNewAccount
        handler(value, nil)
    }
}

@objcMembers
public class PreLoginAuthenticationNotificationEvent : NSObject {
    
    let event : PreLoginAuthenticationEventObjc
    var error : NSError?
    
    init(event : PreLoginAuthenticationEventObjc, error : NSError?) {
        self.event = event
        self.error = error
    }
    
}

@objcMembers
public class PreLoginAuthenticationNotificationRecorder : NSObject {
    
    private var token : Any?
    public var notifications : [PreLoginAuthenticationNotificationEvent] = []
    
    init(authenticationStatus: ZMAuthenticationStatus) {
        super.init()
        
        token = PreLoginAuthenticationObserverToken(authenticationStatus: authenticationStatus) { [weak self] (event, error) in
            self?.notifications.append(PreLoginAuthenticationNotificationEvent(event: event, error: error))
        }
    }
    
}

final class TestUnauthenticatedTransportSession: NSObject, UnauthenticatedTransportSessionProtocol {

    public var cookieStorage = ZMPersistentCookieStorage()
    var nextEnqueueResult: EnqueueResult = .nilRequest

    func enqueueRequest(withGenerator generator: () -> ZMTransportRequest?) -> EnqueueResult {
        return nextEnqueueResult
    }
    
    func tearDown() {}
    let environment: BackendEnvironmentProvider = MockEnvironment()

}


final class TestAuthenticationObserver: NSObject, PreLoginAuthenticationObserver {
    public var authenticationDidSucceedEvents: Int = 0
    public var authenticationDidFailEvents: [Error] = []
    
    private var preLoginAuthenticationToken : Any?
    
    init(unauthenticatedSession : UnauthenticatedSession) {
        super.init()
        
        preLoginAuthenticationToken = unauthenticatedSession.addAuthenticationObserver(self)
    }
    
    func authenticationDidSucceed() {
        authenticationDidSucceedEvents += 1
    }
    
    func authenticationDidFail(_ error: NSError) {
        authenticationDidFailEvents.append(error)
    }
}


final class MockUnauthenticatedSessionDelegate: NSObject, UnauthenticatedSessionDelegate {

    var existingAccounts = [Account]()
    var existingAccountsCalled = 0
    func session(session: UnauthenticatedSession, isExistingAccount account: Account) -> Bool {
        existingAccountsCalled += 1
        return existingAccounts.contains(account)
    }

    var createdAccounts = [Account]()
    var didUpdateCredentials : Bool = false
    var willAcceptUpdatedCredentials = false

    func session(session: UnauthenticatedSession, createdAccount account: Account) {
        createdAccounts.append(account)
    }

    func session(session: UnauthenticatedSession, updatedProfileImage imageData: Data) {
        // no-op
    }

    func session(session: UnauthenticatedSession, updatedCredentials credentials: ZMCredentials) -> Bool {
        didUpdateCredentials = true
        return willAcceptUpdatedCredentials
    }

}


public final class UnauthenticatedSessionTests: ZMTBaseTest {
    var transportSession: TestUnauthenticatedTransportSession!
    var sut: UnauthenticatedSession!
    var mockDelegate: MockUnauthenticatedSessionDelegate!
    var reachability: TestReachability!
    
    public override func setUp() {
        super.setUp()
        transportSession = TestUnauthenticatedTransportSession()
        mockDelegate = MockUnauthenticatedSessionDelegate()
        reachability = TestReachability()
        sut = UnauthenticatedSession(transportSession: transportSession, reachability: reachability, delegate: mockDelegate)
        sut.groupQueue.add(dispatchGroup)
    }
    
    public override func tearDown() {
        sut.tearDown()
        sut = nil
        transportSession = nil
        mockDelegate = nil
        reachability = nil
        super.tearDown()
    }
    
    func testThatTriesToUpdateCredentials() {
        // given
        let emailCredentials = ZMEmailCredentials(email: "hello@email.com", password: "123456")
        mockDelegate.willAcceptUpdatedCredentials = true
        
        // when
        sut.login(with: emailCredentials)
        
        // then
        XCTAssertTrue(mockDelegate.didUpdateCredentials)
    }
    
    func testThatDuringLoginItThrowsErrorWhenNoCredentials() {
        let observer = TestAuthenticationObserver(unauthenticatedSession: sut)
        // given
        reachability.mayBeReachable = false
        // when
        sut.login(with: ZMCredentials())
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(observer.authenticationDidSucceedEvents, 0)
        XCTAssertEqual(observer.authenticationDidFailEvents.count, 1)
        XCTAssertEqual(observer.authenticationDidFailEvents[0].localizedDescription, NSError(code: .needsCredentials, userInfo:nil).localizedDescription)
    }
    
    func testThatDuringLoginWithEmailItThrowsErrorWhenOffline() {
        let observer = TestAuthenticationObserver(unauthenticatedSession: sut)
        // given
        reachability.mayBeReachable = false
        // when
        sut.login(with: ZMEmailCredentials(email: "my@mail.com", password: "my-password"))
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        // then
        XCTAssertEqual(observer.authenticationDidSucceedEvents, 0)
        XCTAssertEqual(observer.authenticationDidFailEvents.count, 1)
        XCTAssertEqual(observer.authenticationDidFailEvents[0].localizedDescription, NSError(code: .networkError, userInfo:nil).localizedDescription)
    }

    func testThatDuringLoginWithPhoneNumberItThrowsErrorWhenOffline() {
        let observer = TestAuthenticationObserver(unauthenticatedSession: sut)
        // given
        reachability.mayBeReachable = false
        // when
        sut.login(with: ZMPhoneCredentials(phoneNumber: "+49111111111111", verificationCode: "1234"))
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        // then
        XCTAssertEqual(observer.authenticationDidSucceedEvents, 0)
        XCTAssertEqual(observer.authenticationDidFailEvents.count, 1)
        XCTAssertEqual(observer.authenticationDidFailEvents[0].localizedDescription, NSError(code: .networkError, userInfo:nil).localizedDescription)
    }

    func testThatItAsksDelegateIfAccountAlreadyExists() throws {
        // given
        let userId = UUID.create()
        let cookie = "zuid=wjCWn1Y1pBgYrFCwuU7WK2eHpAVY8Ocu-rUAWIpSzOcvDVmYVc9Xd6Ovyy-PktFkamLushbfKgBlIWJh6ZtbAA==.1721442805.u.7eaaa023.08326f5e-3c0f-4247-a235-2b4d93f921a4; Expires=Sun, 21-Jul-2024 09:06:45 GMT; Domain=wire.com; HttpOnly; Secure"
        let response = try createResponse(cookie: cookie, userId: userId, userIdKey: "id")
        mockDelegate.existingAccounts = [Account(userName: "", userIdentifier: userId)]

        
        guard let userInfo = response.extractUserInfo() else { return XCTFail("no userinfo") }
        // when
        let exists = sut.accountExistsLocally(from: userInfo)

        // then
        XCTAssertTrue(exists)
        XCTAssertEqual(mockDelegate.existingAccountsCalled, 1)
    }
    
    func testThatItParsesCookieDataAndDoesCallTheDelegateIfTheCookieIsValidAndThereIsAUserIdKeyUser() throws {
        // given
        let userId = UUID.create()
        let cookie = "zuid=wjCWn1Y1pBgYrFCwuU7WK2eHpAVY8Ocu-rUAWIpSzOcvDVmYVc9Xd6Ovyy-PktFkamLushbfKgBlIWJh6ZtbAA==.1721442805.u.7eaaa023.08326f5e-3c0f-4247-a235-2b4d93f921a4; Expires=Sun, 21-Jul-2024 09:06:45 GMT; Domain=wire.com; HttpOnly; Secure"

        // when
        let account = try parseAccount(cookie: cookie, userId: userId, userIdKey: "id")

        // then
        XCTAssertEqual(account.userIdentifier, userId)
        XCTAssertNotNil(transportSession.environment.cookieStorage(for: account).authenticationCookieData)
    }

    func testThatItParsesCookieDataAndDoesCallTheDelegateIfTheCookieIsValidAndThereIsAUserIdKeyId() throws {
        // given
        let userId = UUID.create()
        let cookie = "zuid=wjCWn1Y1pBgYrFCwuU7WK2eHpAVY8Ocu-rUAWIpSzOcvDVmYVc9Xd6Ovyy-PktFkamLushbfKgBlIWJh6ZtbAA==.1721442805.u.7eaaa023.08326f5e-3c0f-4247-a235-2b4d93f921a4; Expires=Sun, 21-Jul-2024 09:06:45 GMT; Domain=wire.com; HttpOnly; Secure"

        // when
        let account = try parseAccount(cookie: cookie, userId: userId, userIdKey: "user")

        // then
        XCTAssertEqual(account.userIdentifier, userId)
        XCTAssertNotNil(transportSession.environment.cookieStorage(for: account).authenticationCookieData)
    }

    func testThatItDoesNotParseAnAccountWithWrongUserIdKey() {
        // given
        let cookie = "zuid=wjCWn1Y1pBgYrFCwuU7WK2eHpAVY8Ocu-rUAWIpSzOcvDVmYVc9Xd6Ovyy-PktFkamLushbfKgBlIWJh6ZtbAA==.1721442805.u.7eaaa023.08326f5e-3c0f-4247-a235-2b4d93f921a4; Expires=Sun, 21-Jul-2024 09:06:45 GMT; Domain=wire.com; HttpOnly; Secure"

        // then
        performIgnoringZMLogError() {
            XCTAssertNil(try? self.parseAccount(cookie: cookie, userIdKey: "identifier"))
        }
    }

    func testThatItDoesNotParseAnAccountWithInvalidCookie() throws {
        // given
        let cookie = "Expires=Sun, 21-Jul-2024 09:06:45 GMT; Domain=wire.com; HttpOnly; Secure"

        // then
        performIgnoringZMLogError() {
            XCTAssertNil(try? self.parseAccount(cookie: cookie, userIdKey: "user"))
        }
    }

    private func createResponse(cookie: String, userId: UUID = .create(), userIdKey: String, line: UInt = #line) throws -> ZMTransportResponse {
        // given
        let headers = [
            "Date": "Thu, 24 Jul 2014 09:06:45 GMT",
            "Content-Encoding": "gzip",
            "Server": "nginx",
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "file://",
            "Connection": "keep-alive",
            "Content-Length": "214",
            "Set-Cookie": cookie
        ]

        return try ZMTransportResponse(headers: headers, payload: [userIdKey: userId.transportString()])
    }

    private func parseAccount(cookie: String, userId: UUID = .create(), userIdKey: String, line: UInt = #line) throws -> Account {
        // given
        let response = try createResponse(cookie: cookie, userId: userId, userIdKey: userIdKey, line: line)

        // when
        response.extractUserInfo().apply(sut.upgradeToAuthenticatedSession)

        // then
        XCTAssertLessThanOrEqual(mockDelegate.createdAccounts.count, 1, line: line)
        if mockDelegate.createdAccounts.isEmpty { throw NSError(domain: "No account", code: 1) }
        return mockDelegate.createdAccounts.first!
    }

}


fileprivate extension ZMTransportResponse {

    convenience init(headers: [String: String], payload: [String: String]) throws {
        let httpResponse = HTTPURLResponse(url: URL(string: "/")!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        self.init(httpurlResponse: httpResponse, data: data, error: nil)
    }

}
