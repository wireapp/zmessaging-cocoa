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
import WireDataModel
import WireCryptobox
import avs
@testable import WireSyncEngine


@objcMembers
public class MockApplicationStatus : NSObject, ApplicationStatus, DeliveryConfirmationDelegate, ClientRegistrationDelegate, ZMRequestCancellation {


    public var notificationFetchStatus = BackgroundNotificationFetchStatus.done

    public var confirmationDelegate : DeliveryConfirmationDelegate { return self }
    public var taskCancellationDelegate : ZMRequestCancellation { return self }
    public var clientRegistrationDelegate : ClientRegistrationDelegate { return self }
    
    public var mockSynchronizationState = SynchronizationState.unauthenticated
    public var synchronizationState: SynchronizationState {
        return mockSynchronizationState
    }


    public var mockOperationState = OperationState.foreground
    public var operationState: OperationState {
        return mockOperationState
    }
    
    public var deliveryConfirmation: DeliveryConfirmationDelegate {
        return self
    }
    
    public var requestCancellation: ZMRequestCancellation {
        return self
    }
    
    //MARK ZMRequestCancellation
    public var cancelledIdentifiers = [ZMTaskIdentifier]()
    
    public func cancelTask(with identifier: ZMTaskIdentifier) {
        cancelledIdentifiers.append(identifier)
    }
    
    
    // MARK: ClientRegistrationDelegate
    public var deletionCalls : Int = 0
    
    /// Notify that the current client was deleted remotely
    public func didDetectCurrentClientDeletion() {
        deletionCalls = deletionCalls+1
    }
    
    /// Returns true if the client is registered
    public var clientIsReadyForRequests: Bool {
        return true
    }
    
    
    // MARK: DeliveryConfirmationDelegate
    public private (set) var messagesToConfirm = Set<UUID>()
    public private (set) var messagesConfirmed = Set<UUID>()
    
    public static var sendDeliveryReceipts: Bool {
        return true
    }
    
    public var needsToSyncMessages: Bool {
        return true
    }
    
    public func needsToConfirmMessage(_ messageNonce: UUID) {
        messagesToConfirm.insert(messageNonce)
    }
    
    public func didConfirmMessage(_ messageNonce: UUID) {
        messagesConfirmed.insert(messageNonce)
    }
    
    public var didRequestSlowSync = false
    public func requestSlowSync() {
        didRequestSlowSync = true
    }
    
}

class MockAuthenticationStatus: ZMAuthenticationStatus {
    
    var mockPhase: ZMAuthenticationPhase
    
    init(phase: ZMAuthenticationPhase = .authenticated, userInfoParser: UserInfoParser) {
        self.mockPhase = phase
        super.init(groupQueue: DispatchGroupQueue(queue: .main), userInfoParser: userInfoParser)
    }
    
    override var currentPhase: ZMAuthenticationPhase {
        return mockPhase
    }

}

@objcMembers
class ZMMockClientRegistrationStatus: ZMClientRegistrationStatus {
    var mockPhase : ZMClientRegistrationPhase?
    var mockReadiness :Bool = true
    
    convenience init(managedObjectContext: NSManagedObjectContext) {
        self.init(managedObjectContext: managedObjectContext, cookieStorage: nil, registrationStatusDelegate: nil)
    }
    
    override init!(managedObjectContext moc: NSManagedObjectContext!, cookieStorage: ZMPersistentCookieStorage!, registrationStatusDelegate: ZMClientRegistrationStatusDelegate!) {
        super.init(managedObjectContext: moc, cookieStorage: cookieStorage, registrationStatusDelegate: registrationStatusDelegate)
        self.emailCredentials = ZMEmailCredentials(email: "bla@example.com", password: "secret")
    }
    
    override var currentPhase: ZMClientRegistrationPhase {
        if let phase = mockPhase {
            return phase
        }
        return super.currentPhase
    }
    
    var isLoggedIn: Bool {
        return true
    }
    
    override func clientIsReadyForRequests() -> Bool {
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
class SpyUserClientKeyStore : UserClientKeysStore {
    
    var failToGeneratePreKeys: Bool = false
    var failToGenerateLastPreKey: Bool = false
    
    var lastGeneratedKeys : [(id: UInt16, prekey: String)] = []
    var lastGeneratedLastPrekey : String?
    
    override public func generateMoreKeys(_ count: UInt16, start: UInt16) throws -> [(id: UInt16, prekey: String)] {

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
    
    override public func lastPreKey() throws -> String {
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

public class MockSyncStatus : SyncStatus {
    
    var didCallFailCurrentSyncPhase = false
    var didCallFinishCurrentSyncPhase = false

    public var mockPhase : SyncPhase = .done {
        didSet {
            currentSyncPhase = mockPhase
        }
    }
    
    public override func failCurrentSyncPhase(phase: SyncPhase) {
        didCallFailCurrentSyncPhase = true
        
        super.failCurrentSyncPhase(phase: phase)
    }
    
    public override func finishCurrentSyncPhase(phase: SyncPhase) {
        didCallFinishCurrentSyncPhase = true
        
        super.finishCurrentSyncPhase(phase: phase)
    }
}

@objc public class MockSyncStateDelegate : NSObject, ZMSyncStateDelegate {

    var registeredUserClient : UserClient?
    @objc public var didCallStartSlowSync = false
    @objc public var didCallFinishSlowSync = false
    @objc public var didCallStartQuickSync = false
    @objc public var didCallFinishQuickSync = false
    
    public func didStartSlowSync() {
        didCallStartSlowSync = true
    }
    
    public func didFinishSlowSync() {
        didCallFinishSlowSync = true
    }

    public func didStartQuickSync() {
        didCallStartQuickSync = true
    }
    
    public func didFinishQuickSync() {
        didCallFinishQuickSync = true
    }
    
    public func didRegister(_ userClient: UserClient!) {
        registeredUserClient = userClient
    }
}

@objc public class MockPushMessageHandler: NSObject, PushMessageHandler {
    
    public func didFailToSend(_ message: ZMMessage) {
        failedToSend.append(message)
    }
    
    public func process(_ message: ZMMessage) {
        processedMessages.append(message)
    }
    
    public func process(_ event: ZMUpdateEvent) {
        if let genericMessage = GenericMessage(from: event) {
            processedGenericMessages.append(genericMessage)
        }
    }
    
    fileprivate(set) var failedToSend: [ZMMessage] = []
    fileprivate(set) var processedMessages: [ZMMessage] = []
    fileprivate(set) var processedGenericMessages: [GenericMessage] = []
}
