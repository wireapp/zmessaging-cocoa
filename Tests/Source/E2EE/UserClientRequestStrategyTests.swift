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
import ZMTesting
import ZMCMockTransport
import ZMCDataModel


class UserClientRequestStrategyTests: RequestStrategyTestBase {
    
    var sut: UserClientRequestStrategy!
    var clientRegistrationStatus: ZMMockClientRegistrationStatus!
    var authenticationStatus: MockAuthenticationStatus!
    var clientUpdateStatus: ZMMockClientUpdateStatus!
    
    var loginProvider: FakeCredentialProvider!
    var updateProvider: FakeCredentialProvider!
    var cookieStorage : ZMPersistentCookieStorage!
    
    var spyKeyStore: SpyUserClientKeyStore!
    
    var receivedAuthenticationNotifications : [ZMUserSessionAuthenticationNotification] = []
    
    override func setUp() {
        super.setUp()

        self.spyKeyStore = SpyUserClientKeyStore(in: UserClientKeysStore.otrDirectoryURL)
        cookieStorage = ZMPersistentCookieStorage(forServerName: "myServer")
        let cookie = ZMCookie(managedObjectContext: self.syncMOC, cookieStorage: cookieStorage)
        loginProvider = FakeCredentialProvider()
        updateProvider = FakeCredentialProvider()
        clientRegistrationStatus = ZMMockClientRegistrationStatus(managedObjectContext: self.syncMOC, loginCredentialProvider:loginProvider, update:updateProvider, cookie:cookie, registrationStatusDelegate: nil)
        authenticationStatus = MockAuthenticationStatus(cookie: cookie);
        clientUpdateStatus = ZMMockClientUpdateStatus(syncManagedObjectContext: self.syncMOC)
        sut = UserClientRequestStrategy(authenticationStatus:authenticationStatus, clientRegistrationStatus: clientRegistrationStatus, clientUpdateStatus:clientUpdateStatus, context: self.syncMOC, userKeysStore: self.spyKeyStore)
        NotificationCenter.default.addObserver(self, selector: #selector(UserClientRequestStrategyTests.didReceiveAuthenticationNotification(_:)), name: NSNotification.Name(rawValue: "ZMUserSessionAuthenticationNotificationName"), object: nil)
    }
    
    
    func didReceiveAuthenticationNotification(_ note: ZMUserSessionAuthenticationNotification) {
        receivedAuthenticationNotifications.append(note)
    }
    
    override func tearDown() {
        self.clientRegistrationStatus.tearDown()
        self.clientRegistrationStatus = nil
        self.clientUpdateStatus.tearDown()
        self.clientUpdateStatus = nil
        self.spyKeyStore = nil
        self.sut.tearDown()
        self.sut = nil
        receivedAuthenticationNotifications = []
        NotificationCenter.default.removeObserver(self)
        super.tearDown()
    }
}



// MARK: Inserting
extension UserClientRequestStrategyTests {

    func createSelfClient(_ context: NSManagedObjectContext) -> UserClient {
        let selfClient = UserClient.insertNewObject(in: context)
        selfClient.remoteIdentifier = nil
        selfClient.user = ZMUser.selfUser(in: context)
        return selfClient
    }
    
    func testThatItReturnsRequestForInsertedObject() {
        // given
        let client = createSelfClient(sut.managedObjectContext)
        sut.notifyChangeTrackers(client)
        clientRegistrationStatus.mockPhase = .unregistered
        
        // when
        clientRegistrationStatus.prepareForClientRegistration()
        
        let request = self.sut.nextRequest()
        
        // then
        let expectedRequest = try! sut.requestsFactory.registerClientRequest(client, credentials: self.updateProvider.emailCredentials(), authenticationStatus:authenticationStatus).transportRequest!
        
        AssertOptionalNotNil(request, "Should return request if there is inserted UserClient object") { request in
            XCTAssertNotNil(request.payload, "Request should contain payload")
            XCTAssertEqual(request.method, expectedRequest.method,"")
            XCTAssertEqual(request.path, expectedRequest.path, "")
        }
    }

    func testThatItDoesNotReturnRequestIfThereIsNoInsertedObject() {
        // given
        let client = createSelfClient(sut.managedObjectContext)
        sut.notifyChangeTrackers(client)
        
        // when
        clientRegistrationStatus.prepareForClientRegistration()
        
        let _ = self.sut.nextRequest()
        let nextRequest = self.sut.nextRequest()
        
        // then
        XCTAssertNil(nextRequest, "Should return request only if UserClient object inserted")
    }
    
    
    func testThatItStoresTheRemoteIdentifierWhenUpdatingAnInsertedObject() {
        
        // given
        let client = createSelfClient(sut.managedObjectContext)
        self.sut.managedObjectContext.saveOrRollback()
        
        let remoteIdentifier = "superRandomIdentifer"
        let payload = ["id" : remoteIdentifier]
        let response = ZMTransportResponse(payload: payload as ZMTransportData, httpStatus: 200, transportSessionError: nil)
        let request = self.sut.request(forInserting: client, forKeys: Set())
        
        // when
        self.sut.updateInsertedObject(client, request: request!, response: response)
        
        // then
        XCTAssertNotNil(client.remoteIdentifier, "Should store remoteIdentifier provided by response")
        XCTAssertEqual(client.remoteIdentifier, remoteIdentifier)
        
        let storedRemoteIdentifier = self.syncMOC.persistentStoreMetadata(forKey: ZMPersistedClientIdKey) as? String
        AssertOptionalEqual(storedRemoteIdentifier, expression2: remoteIdentifier)
        self.syncMOC.setPersistentStoreMetadata(nil as String?, key: ZMPersistedClientIdKey)
    }
    
    func testThatItStoresTheLastGeneratedPreKeyIDWhenUpdatingAnInsertedObject() {
        
        // given
        clientRegistrationStatus.mockPhase = .unregistered

        let client = createSelfClient(sut.managedObjectContext)
        let maxID_before = UInt16(client.preKeysRangeMax)
        XCTAssertEqual(maxID_before, 0)
        
        sut.notifyChangeTrackers(client)
        guard let request = self.sut.nextRequest() else { return XCTFail() }
        let response = ZMTransportResponse(payload: ["id": "fakeRemoteID"] as ZMTransportData, httpStatus: 200, transportSessionError: nil)
        
        // when
        request.complete(with: response)
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        
        // then
        let maxID_after = UInt16(client.preKeysRangeMax)
        let expectedMaxID = self.spyKeyStore.lastGeneratedKeys.last?.id
        
        XCTAssertNotEqual(maxID_after, maxID_before)
        XCTAssertEqual(maxID_after, expectedMaxID)
    }
    
    func testThatItStoresTheSignalingKeysWhenUpdatingAnInsertedObject() {
        
        // given
        clientRegistrationStatus.mockPhase = .unregistered
        
        let client = createSelfClient(sut.managedObjectContext)
        XCTAssertNil(client.apsDecryptionKey)
        XCTAssertNil(client.apsVerificationKey)
        
        sut.notifyChangeTrackers(client)
        guard let request = self.sut.nextRequest() else { return XCTFail() }
        let response = ZMTransportResponse(payload: ["id": "fakeRemoteID"] as ZMTransportData, httpStatus: 200, transportSessionError: nil)
        
        // when
        request.complete(with: response)
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        
        // then
        XCTAssertNotNil(client.apsDecryptionKey)
        XCTAssertNotNil(client.apsVerificationKey)
    }
    
    func testThatItNotifiesObserversWhenUpdatingAnInsertedObject() {
        
        // given
        clientRegistrationStatus.mockPhase = .unregistered

        let client = createSelfClient(sut.managedObjectContext)
        sut.notifyChangeTrackers(client)
        
        guard let request = self.sut.nextRequest() else { return XCTFail() }
        let response = ZMTransportResponse(payload: ["id": "fakeRemoteID"] as ZMTransportData, httpStatus: 200, transportSessionError: nil)
        
        // when
        request.complete(with: response)
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.2))

        // then
        XCTAssertEqual(receivedAuthenticationNotifications.count, 1, "should only receive one notification")
        let note = receivedAuthenticationNotifications.first
        AssertOptionalNotNil(note, "Authentication should succeed. Observers should be notified") { note in
            XCTAssertNil(note.error)
            XCTAssertEqual(note.type, ZMUserSessionAuthenticationNotificationType.authenticationNotificationAuthenticationDidSuceeded)
        }
    }
    
    
    func testThatItProcessFailedInsertResponseWithAuthenticationError_NoEmail() {
        // given
        clientRegistrationStatus.mockPhase = .unregistered

        let client = createSelfClient(sut.managedObjectContext)
        sut.notifyChangeTrackers(client)
        
        guard let request = self.sut.nextRequest() else { return XCTFail() }
        let responsePayload = ["code": 403, "message": "Re-authentication via password required", "label": "missing-auth"] as [String : Any]
        let response = ZMTransportResponse(payload: responsePayload as ZMTransportData, httpStatus: 403, transportSessionError: nil)
        let expectedError = NSError(domain: ZMUserSessionErrorDomain, code: Int(ZMUserSessionErrorCode.needsToRegisterEmailToRegisterClient.rawValue), userInfo: nil)
        
        // when
        request.complete(with: response)
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        
        // then
        XCTAssertEqual(receivedAuthenticationNotifications.count, 1, "should only receive one notification")
        let note = receivedAuthenticationNotifications.first
        AssertOptionalNotNil(note, "Authentication should fail. Observers should be notified") { note in
            XCTAssertEqual(note.error as NSError, expectedError)
            XCTAssertEqual(note.type, ZMUserSessionAuthenticationNotificationType.authenticationNotificationAuthenticationDidFail)
        }
    }
    
    
    func testThatItProcessFailedInsertResponseWithAuthenticationError_HasEmail()
    {
        // given
        clientRegistrationStatus.mockPhase = .unregistered

        let selfUser = ZMUser.selfUser(in: self.sut.managedObjectContext)
        selfUser.emailAddress = "hello@example.com";
        
        let client = createSelfClient(sut.managedObjectContext)
        sut.notifyChangeTrackers(client)
        
        guard let request = self.sut.nextRequest() else { return XCTFail() }
        let responsePayload = ["code": 403, "message": "Re-authentication via password required", "label": "missing-auth"] as [String : Any]
        let response = ZMTransportResponse(payload: responsePayload as ZMTransportData, httpStatus: 403, transportSessionError: nil)

        let expectedError = NSError(domain: ZMUserSessionErrorDomain, code: Int(ZMUserSessionErrorCode.needsPasswordToRegisterClient.rawValue), userInfo: nil)
        
        // when
        request.complete(with: response)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        
        // then
        XCTAssertEqual(receivedAuthenticationNotifications.count, 1, "should only receive one notification")
        let note = receivedAuthenticationNotifications.first
        AssertOptionalNotNil(note, "Authentication should fail. Observers should be notified") { note in
            XCTAssertEqual(note.error as NSError, expectedError)
            XCTAssertEqual(note.type, ZMUserSessionAuthenticationNotificationType.authenticationNotificationAuthenticationDidFail)
        }
    }
    
    
    func testThatItProcessFailedInsertResponseWithTooManyClientsError()
    {
        // given
        cookieStorage.authenticationCookieData = Data()
        clientRegistrationStatus.mockPhase = .unregistered

        let client = createSelfClient(sut.managedObjectContext)
        sut.notifyChangeTrackers(client)
        let selfUser = ZMUser.selfUser(in: self.sut.managedObjectContext)
        selfUser.remoteIdentifier = UUID.create()
        

        guard let request = self.sut.nextRequest() else {
            XCTFail()
            return
        }
        let responsePayload = ["code": 403, "message": "Too many clients", "label": "too-many-clients"] as [String : Any]
        let response = ZMTransportResponse(payload: responsePayload as ZMTransportData?, httpStatus: 403, transportSessionError: nil)
        

        _ = NSError(domain: ZMUserSessionErrorDomain, code: Int(ZMUserSessionErrorCode.canNotRegisterMoreClients.rawValue), userInfo: nil)
        
        // when
        clientRegistrationStatus.mockPhase = nil
        request.complete(with: response)
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        
        // then
        XCTAssertEqual(clientRegistrationStatus.currentPhase,ZMClientRegistrationPhase.fetchingClients)
    }
    
}



// MARK: Updating
extension UserClientRequestStrategyTests {
    
    func testThatItReturnsRequestIfNumberOfRemainingKeysIsLessThanMinimum() {
        // given
        clientRegistrationStatus.mockPhase = .registered

        let client = UserClient.insertNewObject(in: self.sut.managedObjectContext)
        client.remoteIdentifier = UUID.create().transportString()
        self.sut.managedObjectContext.saveOrRollback()
        
        client.numberOfKeysRemaining = Int32(self.sut.minNumberOfRemainingKeys - 1)
        client.setLocallyModifiedKeys(Set(arrayLiteral: ZMUserClientNumberOfKeysRemainingKey))
        sut.notifyChangeTrackers(client)
        
        // when
        guard let request = self.sut.nextRequest() else {
            XCTFail()
            return
        }
        
        // then
        let expectedRequest = try! sut.requestsFactory.updateClientPreKeysRequest(client).transportRequest
        
        AssertOptionalNotNil(request, "Should return request if there is inserted UserClient object") { request in
            XCTAssertNotNil(request.payload, "Request should contain payload")
            XCTAssertEqual(request.method, expectedRequest?.method)
            XCTAssertEqual(request.path, expectedRequest?.path)
        }
    }
    
    func testThatItDoesNotReturnsRequestIfNumberOfRemainingKeysIsLessThanMinimum_NoRemoteIdentifier() {
        // given
        clientRegistrationStatus.mockPhase = .registered
        
        let client = UserClient.insertNewObject(in: self.sut.managedObjectContext)

        // when
        client.remoteIdentifier = nil
        self.sut.managedObjectContext.saveOrRollback()
        
        client.numberOfKeysRemaining = Int32(self.sut.minNumberOfRemainingKeys - 1)
        client.setLocallyModifiedKeys(Set(arrayLiteral: ZMUserClientNumberOfKeysRemainingKey))
        sut.notifyChangeTrackers(client)
        
        // then
        XCTAssertNil(self.sut.nextRequest())
    }
    
    func testThatItDoesNotReturnRequestIfNumberOfRemainingKeysIsAboveMinimum() {
        // given
        let client = UserClient.insertNewObject(in: self.sut.managedObjectContext)
        client.remoteIdentifier = UUID.create().transportString()
        self.sut.managedObjectContext.saveOrRollback()
        
        client.numberOfKeysRemaining = Int32(self.sut.minNumberOfRemainingKeys)
        
        client.setLocallyModifiedKeys(Set(arrayLiteral: ZMUserClientNumberOfKeysRemainingKey))
        sut.notifyChangeTrackers(client)
        
        // when
        let request = self.sut.nextRequest()
        
        // then
        XCTAssertNil(request, "Should not return request if there are enouth keys left")
    }
    
    func testThatItResetsNumberOfRemainingKeysAfterNewKeysUploaded() {
        // given
        let client = UserClient.insertNewObject(in: self.sut.managedObjectContext)
        client.remoteIdentifier = UUID.create().transportString()
        self.sut.managedObjectContext.saveOrRollback()
        
        client.numberOfKeysRemaining = Int32(self.sut.minNumberOfRemainingKeys - 1)
        let expectedNumberOfKeys = client.numberOfKeysRemaining + Int32(sut.requestsFactory.keyCount)
        
        // when
        let response = ZMTransportResponse(payload: nil, httpStatus: 200, transportSessionError: nil)
        let _ = self.sut.updateUpdatedObject(client, requestUserInfo: nil, response: response, keysToParse: Set(arrayLiteral: ZMUserClientNumberOfKeysRemainingKey))

        // then
        XCTAssertEqual(client.numberOfKeysRemaining, expectedNumberOfKeys)
    }
}


// MARK: Fetching Clients
extension UserClientRequestStrategyTests {
    
    
    func  payloadForClients() -> ZMTransportData {
        let payload =  [
            [
                "id" : UUID.create().transportString(),
                "type" : "permanent",
                "label" : "client",
                "time": Date().transportString()
            ],
            [
                "id" : UUID.create().transportString(),
                "type" : "permanent",
                "label" : "client",
                "time": Date().transportString()
            ]
        ]
        
        return payload as ZMTransportData
    }
    
    func testThatItNotifiesWhenFinishingFetchingTheClient() {
        // given
        let nextResponse = ZMTransportResponse(payload: payloadForClients() as ZMTransportData?, httpStatus: 200, transportSessionError: nil)
        
        // when
        _ = sut.nextRequest()
        sut.didReceive(nextResponse, forSingleRequest: nil)
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        
        // then
        AssertOptionalNotNil(self.clientUpdateStatus.fetchedClients, "userinfo should contain clientIDs") { clients in
            XCTAssertEqual(self.clientUpdateStatus.fetchedClients.count, 2)
            for client in self.clientUpdateStatus.fetchedClients {
                XCTAssertEqual(client?.label!, "client")
            }
        }
    }
}


// MARK: Deleting
extension UserClientRequestStrategyTests {
    
    func testThatItCreatesARequestToDeleteAClient_UpdateStatus() {
        
        // given
        clientRegistrationStatus.mockPhase = .unregistered
        clientUpdateStatus.mockPhase = .deletingClients
        var clients = [
            UserClient.insertNewObject(in: self.syncMOC),
            UserClient.insertNewObject(in: self.syncMOC)
        ]
        clients.forEach{
            $0.remoteIdentifier = "\($0.objectID)"
            $0.user = ZMUser.selfUser(in: self.syncMOC)
        }
        self.syncMOC.saveOrRollback()
        
        // when
        clients[0].markForDeletion()
        sut.notifyChangeTrackers(clients[0])
        
        let nextRequest = self.sut.nextRequest()
        
        // then
        AssertOptionalNotNil(nextRequest) {
            XCTAssertEqual($0.path, "/clients/\(clients[0].remoteIdentifier!)")
            XCTAssertEqual($0.payload as! [String:String], [
                "email" : self.clientUpdateStatus.mockCredentials.email!,
                "password" : self.clientUpdateStatus.mockCredentials.password!
                ])
            XCTAssertEqual($0.method, ZMTransportRequestMethod.methodDELETE)
        }
    }
    
    func testThatItDeletesAClientOnSuccess() {
        
        // given
        var client : UserClient!
        
        self.syncMOC.performGroupedBlockAndWait{
            client =  UserClient.insertNewObject(in: self.syncMOC)
            client.remoteIdentifier = "\(client.objectID)"
            client.user = ZMUser.selfUser(in: self.syncMOC)
            self.syncMOC.saveOrRollback()
            
            let response = ZMTransportResponse(payload: [:] as ZMTransportData, httpStatus: 200, transportSessionError: nil)
            
            // when
            let _ = self.sut.updateUpdatedObject(client, requestUserInfo:nil, response: response, keysToParse:Set(arrayLiteral: ZMUserClientMarkedToDeleteKey))
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        XCTAssertTrue(client.isZombieObject)

    }
}



// MARK: - Updating from push events
extension UserClientRequestStrategyTests {
    
    static func payloadForAddingClient(_ clientId : String,
        label : String = "device label",
        time : Date = Date(timeIntervalSince1970: 0)
        ) -> ZMTransportData {
        
            return [
                "client" : [
                    "id" : clientId,
                    "label" : label,
                    "time" : time.transportString(),
                    "type" : "permanent",
                ],
                "type" : "user.client-add"
            ] as ZMTransportData
    }
    
    static func payloadForDeletingClient(_ clientId : String) -> ZMTransportData {
            
            return [
                "client" : [
                    "id" : clientId,
                ],
                "type" : "user.client-remove"
            ] as ZMTransportData
    }
    
    func testThatItAddsAnIgnoredSelfUserClientWhenReceivingAPush() {
        
        // given
        let selfUser = ZMUser.selfUser(in: self.syncMOC)
        let (selfClient, _) = createClients()
        let clientId = "94766bd92f56923d"
        let clientLabel = "iPhone 23sd Plus Air Pro C"
        let clientTime = Date(timeIntervalSince1970: 1234555)
        
        XCTAssertEqual(selfUser.clients.count, 1)
        let payload: [String : Any] = [
            "id" : "27330a52-bab6-11e5-8183-22000b080265",
            "payload" : [
                UserClientRequestStrategyTests.payloadForAddingClient(clientId, label: clientLabel, time: clientTime)
            ],
            "transient" : false
        ]
        
        let events = ZMUpdateEvent.eventsArray(fromPushChannelData: payload as ZMTransportData)
        guard let event = events!.first else {
            XCTFail()
            return
        }
        
        // when
        self.sut.processEvents([event], liveEvents:true, prefetchResult: .none)
        
        // then
        XCTAssertEqual(selfUser.clients.count, 2)
        guard let newClient = selfUser.clients.filter({ $0 != selfClient}).first else {
            XCTFail()
            return
        }
        XCTAssertEqual(newClient.remoteIdentifier, clientId)
        XCTAssertEqual(newClient.label, clientLabel)
        XCTAssertEqual(newClient.activationDate, clientTime)
        XCTAssertTrue(selfClient.ignoredClients.contains(newClient))
    }
    
    func testThatItAddsASelfUserClientWhenDownloadingAClientEvent() {
        
        // given
        let selfUser = ZMUser.selfUser(in: self.syncMOC)
        let clientId = "94766bd92f56923d"
        
        XCTAssertEqual(selfUser.clients.count, 0)
        let payload = UserClientRequestStrategyTests.payloadForAddingClient(clientId)
        let event = ZMUpdateEvent(fromEventStreamPayload: payload, uuid: nil)!
        
        // when
        self.sut.processEvents([event], liveEvents:false, prefetchResult: .none)
        
        // then
        XCTAssertEqual(selfUser.clients.count, 1)
        guard let newClient = selfUser.clients.first else {
            XCTFail()
            return
        }
        XCTAssertEqual(newClient.remoteIdentifier, clientId)
    }
    
    func testThatItDoesNotAddASelfUserClientWhenReceivingAPushIfTheClientExistsAlready() {
        
        // given
        let selfUser = ZMUser.selfUser(in: self.syncMOC)
        let existingClient = self.createSelfClient()
        
        XCTAssertEqual(selfUser.clients.count, 1)
        let payload: [String : Any] = [
            "id" : "27330a52-bab6-11e5-8183-22000b080265",
            "payload" : [
                UserClientRequestStrategyTests.payloadForAddingClient(existingClient.remoteIdentifier!)
            ],
            "transient" : false
        ]
        
        let events = ZMUpdateEvent.eventsArray(fromPushChannelData: payload as ZMTransportData)
        guard let event = events!.first else {
            XCTFail()
            return
        }
        
        // when
        self.sut.processEvents([event], liveEvents:true, prefetchResult: .none)
        
        // then
        XCTAssertEqual(selfUser.clients.count, 1)
        guard let newClient = selfUser.clients.first else {
            XCTFail()
            return
        }
        XCTAssertEqual(newClient, existingClient)
    }
    
    func testThatItDeletesASelfClientWhenReceivingAPush() {
        
        // given
        let selfUser = ZMUser.selfUser(in: self.syncMOC)
        let existingClient1 = self.createSelfClient()
        let existingClient2 = UserClient.insertNewObject(in: self.syncMOC)
        existingClient2.user = selfUser
        existingClient2.remoteIdentifier = "aabbcc112233"
        self.syncMOC.saveOrRollback()
        
        XCTAssertEqual(selfUser.clients.count, 2)
        let payload: [String: Any] = [
            "id" : "27330a52-bab6-11e5-8183-22000b080265",
            "payload" : [
                UserClientRequestStrategyTests.payloadForDeletingClient(existingClient2.remoteIdentifier!)
            ],
            "transient" : false
        ]
        
        let events = ZMUpdateEvent.eventsArray(fromPushChannelData: payload as ZMTransportData)
        guard let event = events!.first else {
            XCTFail()
            return
        }
        
        // when
        self.sut.processEvents([event], liveEvents:true, prefetchResult: .none)
        
        // then
        XCTAssertEqual(selfUser.clients.count, 1)
        guard let newClient = selfUser.clients.first else {
            XCTFail()
            return
        }
        XCTAssertEqual(newClient, existingClient1)
    }
    
    func testThatItInvalidatesTheCurrentSelfClientAndWipeCryptoBoxWhenReceivingAPush() {
        
        // given
        let selfUser = ZMUser.selfUser(in: syncMOC)
        let existingClient = createSelfClient()

        var fingerprint : Data?
        syncMOC.zm_cryptKeyStore.encryptionContext.perform { (sessionsDirectory) in
            fingerprint = sessionsDirectory.localFingerprint
        }
        let previousLastPrekey = try? syncMOC.zm_cryptKeyStore.lastPreKey()
        
        XCTAssertEqual(selfUser.clients.count, 1)
        let payload: [String: Any] = [
            "id" : "27330a52-bab6-11e5-8183-22000b080265",
            "payload" : [
                UserClientRequestStrategyTests.payloadForDeletingClient(existingClient.remoteIdentifier!)
            ],
            "transient" : false
        ] as [String : Any]
        
        let events = ZMUpdateEvent.eventsArray(fromPushChannelData: payload as ZMTransportData)
        guard let event = events!.first else { return XCTFail() }
        
        // when
        self.sut.processEvents([event], liveEvents:true, prefetchResult: .none)
        
        // then
        var newFingerprint : Data?
        syncMOC.zm_cryptKeyStore.encryptionContext.perform { (sessionsDirectory) in
            newFingerprint = sessionsDirectory.localFingerprint
        }
        let newLastPrekey = try? syncMOC.zm_cryptKeyStore.lastPreKey()
        
        XCTAssertNotNil(fingerprint)
        XCTAssertNotNil(newFingerprint)
        XCTAssertNotEqual(fingerprint, newFingerprint)
        XCTAssertNil(selfUser.clients.first?.remoteIdentifier)
        XCTAssertNil(syncMOC.persistentStoreMetadata(forKey: ZMPersistedClientIdKey))
        XCTAssertNotNil(fingerprint)
        XCTAssertNotNil(newFingerprint)
        XCTAssertNotEqual(previousLastPrekey, newLastPrekey)
    }
    
    func testThatItCreatesARequestForClientsThatNeedToUploadSignalingKeys() {
        
        // given
        clientRegistrationStatus.mockPhase = .registered

        let existingClient = createSelfClient()
        XCTAssertNil(existingClient.apsVerificationKey)
        XCTAssertNil(existingClient.apsDecryptionKey)
        
        // when
        existingClient.needsToUploadSignalingKeys = true
        existingClient.setLocallyModifiedKeys(Set(arrayLiteral: ZMUserClientNeedsToUpdateSignalingKeysKey))
        self.sut.contextChangeTrackers.forEach{$0.objectsDidChange(Set(arrayLiteral: existingClient))}
        let request = self.sut.nextRequest()
        
        // then
        XCTAssertNotNil(request)
        
        // and when
        let response = ZMTransportResponse(payload: nil, httpStatus: 200, transportSessionError: nil)
        request?.complete(with: response)
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        
        // then
        XCTAssertNotNil(existingClient.apsVerificationKey)
        XCTAssertNotNil(existingClient.apsDecryptionKey)
        XCTAssertFalse(existingClient.needsToUploadSignalingKeys)
        XCTAssertFalse(existingClient.hasLocalModifications(forKey: ZMUserClientNeedsToUpdateSignalingKeysKey))

    }
    
    func testThatItRetriesOnceWhenUploadSignalingKeysFails() {
        
        // given
        clientRegistrationStatus.mockPhase = .registered
        
        let existingClient = createSelfClient()
        XCTAssertNil(existingClient.apsVerificationKey)
        XCTAssertNil(existingClient.apsDecryptionKey)
        
        existingClient.needsToUploadSignalingKeys = true
        existingClient.setLocallyModifiedKeys(Set(arrayLiteral: ZMUserClientNeedsToUpdateSignalingKeysKey))
        self.sut.contextChangeTrackers.forEach{$0.objectsDidChange(Set(arrayLiteral: existingClient))}
        
        // when
        let request = self.sut.nextRequest()
        XCTAssertNotNil(request)
        let badResponse = ZMTransportResponse(payload: ["label": "bad-request"] as ZMTransportData, httpStatus: 400, transportSessionError: nil)

        request?.complete(with: badResponse)
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        
        // and when
        let secondRequest = self.sut.nextRequest()
        XCTAssertNotNil(secondRequest)
        let success = ZMTransportResponse(payload: nil, httpStatus: 200, transportSessionError: nil)

        request?.complete(with: success)
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        
        // and when
        let thirdRequest = self.sut.nextRequest()
        XCTAssertNil(thirdRequest)
        
    }

}
