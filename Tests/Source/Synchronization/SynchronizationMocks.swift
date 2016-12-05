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
import AddressBook
@testable import zmessaging

class MockAuthenticationStatus: ZMAuthenticationStatus {
    
    var mockPhase: ZMAuthenticationPhase
    
    init(phase: ZMAuthenticationPhase = .authenticated, cookieString: String = "label", cookie: ZMCookie? = nil) {
        self.mockPhase = phase
        self.cookieString = cookieString
        super.init(managedObjectContext: nil, cookie: cookie)
    }
    
    override var currentPhase: ZMAuthenticationPhase {
        return mockPhase
    }
    
    var cookieString: String
    
    override var cookieLabel: String {
        return self.cookieString
    }
}

class ZMMockClientRegistrationStatus: ZMClientRegistrationStatus, ClientRegistrationDelegate {
    var mockPhase : ZMClientRegistrationPhase?
    var mockCredentials : ZMEmailCredentials = ZMEmailCredentials(email: "bla@example.com", password: "secret")
    var mockReadiness :Bool = true
    
    override var currentPhase: ZMClientRegistrationPhase {
        if let phase = mockPhase {
            return phase
        }
        return super.currentPhase
    }
    
    override var emailCredentials : ZMEmailCredentials {
        return mockCredentials
    }
    
    var isLoggedIn: Bool {
        return true
    }
    
    override var clientIsReadyForRequests: Bool {
        return mockReadiness
    }
}

class ZMMockClientUpdateStatus: ClientUpdateStatus {
    var fetchedClients : [UserClient?] = []
    var mockPhase : ClientUpdatePhase = .done
    var deleteCallCount : Int = 0
    var fetchCallCount : Int = 0
    var mockCredentials: ZMEmailCredentials = ZMEmailCredentials(email: "bla@example.com", password: "secret")
    
    override var credentials : ZMEmailCredentials? {
        return mockCredentials
    }
    
    override func didFetchClients(_ clients: [UserClient]) {
        fetchedClients = clients
        fetchCallCount += 1
    }
    
    override func didDeleteClient() {
        deleteCallCount += 1
    }
    
    override var currentPhase: ClientUpdatePhase {
        return mockPhase
    }
}

class FakeCredentialProvider: NSObject, ZMCredentialProvider
{
    var clearCallCount = 0
    var email = "hello@example.com"
    var password = "verySafePassword"
    
    func emailCredentials() -> ZMEmailCredentials! {
        return ZMEmailCredentials(email: email, password: password)
    }
    
    func credentialsMayBeCleared() {
        clearCallCount += 1
    }
}

class FakeCookieStorage: ZMPersistentCookieStorage {
}


// used by tests to fake errors on genrating pre keys
open class FakeKeysStore: UserClientKeysStore {
    
    var failToGeneratePreKeys: Bool = false
    var failToGenerateLastPreKey: Bool = false
    
    var lastGeneratedKeys : [(id: UInt16, prekey: String)] = []
    var lastGeneratedLastPrekey : String?

    static var testDirectory : URL {
        let directoryURL = try! FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return directoryURL.appendingPathComponent("otr")
    }
    
    override open func generateMoreKeys(_ count: UInt16, start: UInt16) throws -> [(id: UInt16, prekey: String)] {

        if self.failToGeneratePreKeys {
            let error = NSError(domain: "cryptobox.error", code: 0, userInfo: ["reason" : "using fake store with simulated fail"])
            throw error
        }
        else {
            let keys = try! super.generateMoreKeys(count, start: start)
            lastGeneratedKeys = keys
            return keys
        }
    }
    
    override open func lastPreKey() throws -> String {
        if self.failToGenerateLastPreKey {
            let error = NSError(domain: "cryptobox.error", code: 0, userInfo: ["reason" : "using fake store with simulated fail"])
            throw error
        }
        else {
            lastGeneratedLastPrekey = try! super.lastPreKey()
            return lastGeneratedLastPrekey!
        }
    }
    
}

