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
    
    init(phase: ZMAuthenticationPhase = .Authenticated, cookieString: String = "label", cookie: ZMCookie? = nil) {
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

class ZMMockClientRegistrationStatus: ZMClientRegistrationStatus {
    var mockPhase : ZMClientRegistrationPhase?
    var mockCredentials : ZMEmailCredentials = ZMEmailCredentials(email: "bla@example.com", password: "secret")
    
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
}

class ZMMockClientUpdateStatus: ClientUpdateStatus {
    var fetchedClients : [UserClient!] = []
    var mockPhase : ClientUpdatePhase = .Done
    var deleteCallCount : Int = 0
    var fetchCallCount : Int = 0
    var mockCredentials: ZMEmailCredentials = ZMEmailCredentials(email: "bla@example.com", password: "secret")
    
    override var credentials : ZMEmailCredentials? {
        return mockCredentials
    }
    
    override func didFetchClients(clients: [UserClient]) {
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
public class FakeKeysStore: UserClientKeysStore {
    
    var failToGeneratePreKeys: Bool = false
    var failToGenerateLastPreKey: Bool = false
    
    var lastGeneratedKeys : (keys: [CBPreKey], minIndex: UInt, maxIndex: UInt) = ([],0,0)
    var lastGeneratedLastPrekey : CBPreKey?
    
    override public func generateMoreKeys(count: UInt, start: UInt) throws -> ([CBPreKey], UInt, UInt) {
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
    
    override public func lastPreKey() throws -> CBPreKey {
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

// MARK: - AddressBook
class AddressBookContactsFake {
    
    struct Contact {
        let firstName : String
        let emailAddresses : [String]
        let phoneNumbers : [String]
    }
    
    var contacts : [Contact] = []
    
    var peopleCount : Int {
        if self.createInfiniteContacts {
            return Int.max
        } else {
            return contacts.count
        }
    }
    
    var createInfiniteContacts: Bool = false
    
    var peopleGenerator : AnyGenerator<ABRecordRef> {
        
        guard !self.createInfiniteContacts else {
            return AnyGenerator {
                let record: ABRecordRef = ABPersonCreate().takeRetainedValue()
                ABRecordSetValue(record, kABPersonFirstNameProperty, "Johnny Infinite", nil)
                let values: ABMutableMultiValue = ABMultiValueCreateMutable(ABPropertyType(kABMultiStringPropertyType)).takeRetainedValue()
                ABMultiValueAddValueAndLabel(values, "neverending@example.com", kABHomeLabel, nil)
                ABRecordSetValue(record, kABPersonEmailProperty, values, nil)
                return record
            }
        }
        
        return AnyGenerator(self.contacts.map { contact in
            let record: ABRecordRef = ABPersonCreate().takeRetainedValue()
            ABRecordSetValue(record, kABPersonFirstNameProperty, contact.firstName, nil)
            if !contact.emailAddresses.isEmpty {
                let values: ABMutableMultiValue =
                    ABMultiValueCreateMutable(ABPropertyType(kABMultiStringPropertyType)).takeRetainedValue()
                contact.emailAddresses.forEach {
                    ABMultiValueAddValueAndLabel(values, $0, kABHomeLabel, nil)
                }
                ABRecordSetValue(record, kABPersonEmailProperty, values, nil)
            }
            if !contact.phoneNumbers.isEmpty {
                let values: ABMutableMultiValue =
                    ABMultiValueCreateMutable(ABPropertyType(kABMultiStringPropertyType)).takeRetainedValue()
                contact.phoneNumbers.forEach {
                    ABMultiValueAddValueAndLabel(values, $0, kABPersonPhoneMainLabel, nil)
                }
                ABRecordSetValue(record, kABPersonPhoneProperty, values, nil)
            }
            return record
        }.generate())
    }
    
    /// Return an address book that will return contacts extracted from self
    func addressBook() -> zmessaging.AddressBook {
        return zmessaging.AddressBook(allPeopleClosure: { _ in self.peopleGenerator },
                               addressBookAccessCheck: { return true },
                               numberOfPeopleClosure: { _ in self.peopleCount })!
    }
}
