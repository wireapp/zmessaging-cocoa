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

class UserClientRequestStrategyTests: MessagingTest {
    
    var sut: UserClientRequestStrategy!
    var clientRegistrationStatus: ZMMockClientRegistrationStatus!
    var authenticationStatus: MockAuthenticationStatus!
    var clientUpdateStatus: ZMMockClientUpdateStatus!
    
    var loginProvider: FakeCredentialProvider!
    var updateProvider: FakeCredentialProvider!
    var cookieStorage : ZMPersistentCookieStorage!
    
    var receivedAuthenticationNotifications : [ZMUserSessionAuthenticationNotification] = []
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
        let newKeyStore = FakeKeysStore()
        self.syncMOC.userInfo.setObject(newKeyStore, forKey: "ZMUserClientKeysStore")
        cookieStorage = ZMPersistentCookieStorage(forServerName: "myServer")
        let cookie = ZMCookie(managedObjectContext: self.syncMOC, cookieStorage: cookieStorage)
        loginProvider = FakeCredentialProvider()
        updateProvider = FakeCredentialProvider()
        clientRegistrationStatus = ZMMockClientRegistrationStatus(managedObjectContext: self.syncMOC, loginCredentialProvider:loginProvider, updateCredentialProvider:updateProvider, cookie:cookie, registrationStatusDelegate: nil)
        authenticationStatus = MockAuthenticationStatus(cookie: cookie);
        clientUpdateStatus = ZMMockClientUpdateStatus(syncManagedObjectContext: self.syncMOC)
        sut = UserClientRequestStrategy(authenticationStatus:authenticationStatus, clientRegistrationStatus: clientRegistrationStatus, clientUpdateStatus:clientUpdateStatus, context: self.syncMOC)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(UserClientRequestStrategyTests.didReceiveAuthenticationNotification(_:)), name: "ZMUserSessionAuthenticationNotificationName", object: nil)
    }
    
    
    func didReceiveAuthenticationNotification(note: ZMUserSessionAuthenticationNotification) {
        receivedAuthenticationNotifications.append(note)
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        clientRegistrationStatus.tearDown()
        clientRegistrationStatus = nil
        clientUpdateStatus.tearDown()
        clientUpdateStatus = nil
        sut.tearDown()
        sut = nil
        receivedAuthenticationNotifications = []
        NSNotificationCenter.defaultCenter().removeObserver(self)
        super.tearDown()
    }

    func notifyChangeTrackers(client : UserClient) {
        for changeTracker in self.sut.contextChangeTrackers {
            changeTracker.objectsDidChange(Set(arrayLiteral:client))
        }
    }
    
}



// MARK: Inserting
extension UserClientRequestStrategyTests {

    func createSelfClient(context: NSManagedObjectContext) -> UserClient {
        let selfClient = UserClient.insertNewObjectInManagedObjectContext(context)
        selfClient.remoteIdentifier = nil
        selfClient.user = ZMUser.selfUserInContext(context)
        return selfClient
    
    }

    func testThatItReturnsRequestForInsertedObject() {
        // given
        let client = createSelfClient(sut.managedObjectContext)
        notifyChangeTrackers(client)
        clientRegistrationStatus.mockPhase = .Unregistered
        
        // when
        clientRegistrationStatus.prepareForClientRegistration()
        
        let request = self.sut.nextRequest()
        
        // then
        let expectedRequest = try! sut.requestsFactory.registerClientRequest(client, credentials: self.updateProvider.emailCredentials(), authenticationStatus:authenticationStatus).transportRequest
        
        AssertOptionalNotNil(request, "Should return request if there is inserted UserClient object") { request in
            XCTAssertNotNil(request.payload, "Request should contain payload")
            XCTAssertEqual(request.method, expectedRequest.method,"")
            XCTAssertEqual(request.path, expectedRequest.path, "")
        }
    }

    func testThatItDoesNotReturnRequestIfThereIsNoInsertedObject() {
        // given
        let client = createSelfClient(sut.managedObjectContext)
        notifyChangeTrackers(client)
        
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
        let response = ZMTransportResponse(payload: payload, HTTPstatus: 200, transportSessionError: nil)
        let request = self.sut.requestForInsertingObject(client, forKeys: Set())
        
        // when
        self.sut.updateInsertedObject(client, request: request!, response: response)
        
        // then
        XCTAssertNotNil(client.remoteIdentifier, "Should store remoteIdentifier provided by response")
        XCTAssertEqual(client.remoteIdentifier, remoteIdentifier)
        
        let storedRemoteIdentifier = self.syncMOC.persistentStoreMetadataForKey(ZMPersistedClientIdKey) as? String
        AssertOptionalEqual(storedRemoteIdentifier, expression2: remoteIdentifier)
        self.syncMOC.setPersistentStoreMetadata(nil, forKey: ZMPersistedClientIdKey)
    }
    
    func testThatItStoresTheLastGeneratedPreKeyIDWhenUpdatingAnInsertedObject() {
        
        // given
        clientRegistrationStatus.mockPhase = .Unregistered

        let client = createSelfClient(sut.managedObjectContext)
        let maxID_before = UInt(client.preKeysRangeMax)
        XCTAssertEqual(maxID_before, 0)
        
        notifyChangeTrackers(client)
        guard let request = self.sut.nextRequest() else { return XCTFail() }
        let response = ZMTransportResponse(payload: ["id": "fakeRemoteID"], HTTPstatus: 200, transportSessionError: nil)
        
        // when
        request.completeWithResponse(response)
        XCTAssertTrue(waitForAllGroupsToBeEmptyWithTimeout(0.2))
        
        // then
        let maxID_after = UInt(client.preKeysRangeMax)
        let (_, _, expectedMaxID) = (client.keysStore as! FakeKeysStore).lastGeneratedKeys
        
        XCTAssertNotEqual(maxID_after, maxID_before)
        XCTAssertEqual(maxID_after, expectedMaxID)
    }
    
    func testThatItStoresTheSignalingKeysWhenUpdatingAnInsertedObject() {
        
        // given
        clientRegistrationStatus.mockPhase = .Unregistered
        
        let client = createSelfClient(sut.managedObjectContext)
        XCTAssertNil(client.apsDecryptionKey)
        XCTAssertNil(client.apsVerificationKey)
        
        notifyChangeTrackers(client)
        guard let request = self.sut.nextRequest() else { return XCTFail() }
        let response = ZMTransportResponse(payload: ["id": "fakeRemoteID"], HTTPstatus: 200, transportSessionError: nil)
        
        // when
        request.completeWithResponse(response)
        XCTAssertTrue(waitForAllGroupsToBeEmptyWithTimeout(0.2))
        
        // then
        XCTAssertNotNil(client.apsDecryptionKey)
        XCTAssertNotNil(client.apsVerificationKey)
    }
    
    func testThatItNotifiesObserversWhenUpdatingAnInsertedObject() {
        
        // given
        clientRegistrationStatus.mockPhase = .Unregistered

        let client = createSelfClient(sut.managedObjectContext)
        notifyChangeTrackers(client)
        
        guard let request = self.sut.nextRequest() else { return XCTFail() }
        let response = ZMTransportResponse(payload: ["id": "fakeRemoteID"], HTTPstatus: 200, transportSessionError: nil)
        
        // when
        request.completeWithResponse(response)
        XCTAssertTrue(waitForAllGroupsToBeEmptyWithTimeout(0.2))

        // then
        XCTAssertEqual(receivedAuthenticationNotifications.count, 1, "should only receive one notification")
        let note = receivedAuthenticationNotifications.first
        AssertOptionalNotNil(note, "Authentication should succeed. Observers should be notified") { note in
            XCTAssertNil(note.error)
            XCTAssertEqual(note.type, ZMUserSessionAuthenticationNotificationType.AuthenticationNotificationAuthenticationDidSuceeded)
        }
    }
    
    
    func testThatItProcessFailedInsertResponseWithAuthenticationError_NoEmail() {
        // given
        clientRegistrationStatus.mockPhase = .Unregistered

        let client = createSelfClient(sut.managedObjectContext)
        notifyChangeTrackers(client)
        
        guard let request = self.sut.nextRequest() else { return XCTFail() }
        let responsePayload = ["code": 403, "message": "Re-authentication via password required", "label": "missing-auth"]
        let response = ZMTransportResponse(payload: responsePayload, HTTPstatus: 403, transportSessionError: nil)
        let expectedError = NSError(domain: ZMUserSessionErrorDomain, code: Int(ZMUserSessionErrorCode.NeedsToRegisterEmailToRegisterClient.rawValue), userInfo: nil)
        
        // when
        request.completeWithResponse(response)
        XCTAssertTrue(waitForAllGroupsToBeEmptyWithTimeout(0.2))
        
        // then
        XCTAssertEqual(receivedAuthenticationNotifications.count, 1, "should only receive one notification")
        let note = receivedAuthenticationNotifications.first
        AssertOptionalNotNil(note, "Authentication should fail. Observers should be notified") { note in
            XCTAssertEqual(note.error, expectedError)
            XCTAssertEqual(note.type, ZMUserSessionAuthenticationNotificationType.AuthenticationNotificationAuthenticationDidFail)
        }
    }
    
    
    func testThatItProcessFailedInsertResponseWithAuthenticationError_HasEmail()
    {
        // given
        clientRegistrationStatus.mockPhase = .Unregistered

        let selfUser = ZMUser.selfUserInContext(self.sut.managedObjectContext)
        selfUser.emailAddress = "hello@example.com";
        
        let client = createSelfClient(sut.managedObjectContext)
        notifyChangeTrackers(client)
        
        guard let request = self.sut.nextRequest() else { return XCTFail() }
        let responsePayload = ["code": 403, "message": "Re-authentication via password required", "label": "missing-auth"]
        let response = ZMTransportResponse(payload: responsePayload, HTTPstatus: 403, transportSessionError: nil)
        let expectedError = NSError(domain: ZMUserSessionErrorDomain, code: Int(ZMUserSessionErrorCode.NeedsPasswordToRegisterClient.rawValue), userInfo: nil)
        
        // when
        request.completeWithResponse(response)
        XCTAssert(waitForAllGroupsToBeEmptyWithTimeout(0.2))
        
        // then
        XCTAssertEqual(receivedAuthenticationNotifications.count, 1, "should only receive one notification")
        let note = receivedAuthenticationNotifications.first
        AssertOptionalNotNil(note, "Authentication should fail. Observers should be notified") { note in
            XCTAssertEqual(note.error, expectedError)
            XCTAssertEqual(note.type, ZMUserSessionAuthenticationNotificationType.AuthenticationNotificationAuthenticationDidFail)
        }
    }
    
    
    func testThatItProcessFailedInsertResponseWithTooManyClientsError()
    {
        // given
        cookieStorage.authenticationCookieData = NSData()
        clientRegistrationStatus.mockPhase = .Unregistered

        let client = createSelfClient(sut.managedObjectContext)
        notifyChangeTrackers(client)
        let selfUser = ZMUser.selfUserInContext(self.sut.managedObjectContext)
        selfUser.remoteIdentifier = NSUUID.createUUID()
        

        guard let request = self.sut.nextRequest() else {
            XCTFail()
            return
        }
        let responsePayload = ["code": 403, "message": "Too many clients", "label": "too-many-clients"]
        let response = ZMTransportResponse(payload: responsePayload, HTTPstatus: 403, transportSessionError: nil)
        

        _ = NSError(domain: ZMUserSessionErrorDomain, code: Int(ZMUserSessionErrorCode.CanNotRegisterMoreClients.rawValue), userInfo: nil)
        
        // when
        clientRegistrationStatus.mockPhase = nil
        request.completeWithResponse(response)
        XCTAssertTrue(waitForAllGroupsToBeEmptyWithTimeout(0.2))
        
        // then
        XCTAssertEqual(clientRegistrationStatus.currentPhase,ZMClientRegistrationPhase.FetchingClients)
    }
    
}



// MARK: Updating
extension UserClientRequestStrategyTests {
    
    func testThatItReturnsRequestIfNumberOfRemainingKeysIsLessThanMinimum() {
        // given
        clientRegistrationStatus.mockPhase = .Registered

        let client = UserClient.insertNewObjectInManagedObjectContext(self.sut.managedObjectContext)
        client.remoteIdentifier = NSUUID.createUUID().transportString()
        self.sut.managedObjectContext.saveOrRollback()
        
        client.numberOfKeysRemaining = Int32(self.sut.minNumberOfRemainingKeys - 1)
        client.setLocallyModifiedKeys(Set(arrayLiteral: ZMUserClientNumberOfKeysRemainingKey))
        notifyChangeTrackers(client)
        
        // when
        guard let request = self.sut.nextRequest() else {
            XCTFail()
            return
        }
        
        // then
        let expectedRequest = try! sut.requestsFactory.updateClientPreKeysRequest(client).transportRequest
        
        AssertOptionalNotNil(request, "Should return request if there is inserted UserClient object") { request in
            XCTAssertNotNil(request.payload, "Request should contain payload")
            XCTAssertEqual(request.method, expectedRequest.method)
            XCTAssertEqual(request.path, expectedRequest.path)
        }
    }
    
    func testThatItDoesNotReturnsRequestIfNumberOfRemainingKeysIsLessThanMinimum_NoRemoteIdentifier() {
        // given
        clientRegistrationStatus.mockPhase = .Registered
        
        let client = UserClient.insertNewObjectInManagedObjectContext(self.sut.managedObjectContext)

        // when
        client.remoteIdentifier = nil
        self.sut.managedObjectContext.saveOrRollback()
        
        client.numberOfKeysRemaining = Int32(self.sut.minNumberOfRemainingKeys - 1)
        client.setLocallyModifiedKeys(Set(arrayLiteral: ZMUserClientNumberOfKeysRemainingKey))
        notifyChangeTrackers(client)
        
        // then
        XCTAssertNil(self.sut.nextRequest())
    }
    
    func testThatItDoesNotReturnRequestIfNumberOfRemainingKeysIsAboveMinimum() {
        // given
        let client = UserClient.insertNewObjectInManagedObjectContext(self.sut.managedObjectContext)
        client.remoteIdentifier = NSUUID.createUUID().transportString()
        self.sut.managedObjectContext.saveOrRollback()
        
        client.numberOfKeysRemaining = Int32(self.sut.minNumberOfRemainingKeys)
        
        client.setLocallyModifiedKeys(Set(arrayLiteral: ZMUserClientNumberOfKeysRemainingKey))
        notifyChangeTrackers(client)
        
        // when
        let request = self.sut.nextRequest()
        
        // then
        XCTAssertNil(request, "Should not return request if there are enouth keys left")
    }
    
    func testThatItResetsNumberOfRemainingKeysAfterNewKeysUploaded() {
        // given
        let client = UserClient.insertNewObjectInManagedObjectContext(self.sut.managedObjectContext)
        client.remoteIdentifier = NSUUID.createUUID().transportString()
        self.sut.managedObjectContext.saveOrRollback()
        
        client.numberOfKeysRemaining = Int32(self.sut.minNumberOfRemainingKeys - 1)
        let expectedNumberOfKeys = client.numberOfKeysRemaining + Int32(sut.requestsFactory.keyCount)
        
        // when
        let response = ZMTransportResponse(payload: nil, HTTPstatus: 200, transportSessionError: nil)
        self.sut.updateUpdatedObject(client, requestUserInfo: nil, response: response, keysToParse: Set(arrayLiteral: ZMUserClientNumberOfKeysRemainingKey))

        // then
        XCTAssertEqual(client.numberOfKeysRemaining, expectedNumberOfKeys)
    }
}


// MARK: Fetching Clients
extension UserClientRequestStrategyTests {
    
    
    func  payloadForClients() -> [[String:String!]] {
        let payload =  [
            [
                "id" : NSUUID.createUUID().transportString(),
                "type" : "permanent",
                "label" : "client",
                "time": NSDate().transportString()
            ],
            [
                "id" : NSUUID.createUUID().transportString(),
                "type" : "permanent",
                "label" : "client",
                "time": NSDate().transportString()
            ]
        ]
        
        return payload
    }
    
    func testThatItNotifiesWhenFinishingFetchingTheClient() {
        // given
        let nextResponse = ZMTransportResponse(payload: payloadForClients(), HTTPstatus: 200, transportSessionError: nil)
        
        // when
        _ = sut.nextRequest()
        sut.didReceiveResponse(nextResponse, forSingleRequest: nil)
        XCTAssertTrue(waitForAllGroupsToBeEmptyWithTimeout(0.2))
        
        // then
        AssertOptionalNotNil(self.clientUpdateStatus.fetchedClients, "userinfo should contain clientIDs") { clients in
            XCTAssertEqual(self.clientUpdateStatus.fetchedClients.count, 2)
            for client in self.clientUpdateStatus.fetchedClients {
                XCTAssertEqual(client.label!, "client")
            }
        }
    }
}

// MARK: Fetching Other Users Clients
extension UserClientRequestStrategyTests {
    
    func payloadForOtherClients(identifiers: String...) -> [[String : String]] {
        return identifiers.reduce([]) { $0 + [["id": $1, "class" : "phone"]] }
    }
    
    func testThatItCreatesOtherUsersClientsCorrectly() {
        // given
        createClients()
        let (firstIdentifier, secondIdentifier) = (NSUUID.createUUID().transportString(), NSUUID.createUUID().transportString())
        let payloadForOtherClients = [
            [
                "id" : firstIdentifier,
                "class" : "phone"
            ],
            [
                "id" : secondIdentifier,
                "class": "tablet"
            ]
        ]
        
        let response = ZMTransportResponse(payload: payloadForOtherClients, HTTPstatus: 200, transportSessionError: nil)
        
        let identifier = NSUUID.createUUID()
        let user = ZMUser.insertNewObjectInManagedObjectContext(syncMOC)
        user.remoteIdentifier = identifier
        
        // when
        clientRegistrationStatus.mockPhase = .Registered
        _ = sut.nextRequest()
        sut.didReceiveResponse(response, remoteIdentifierObjectSync: nil, forRemoteIdentifiers: Set(arrayLiteral: identifier))
        XCTAssertTrue(waitForAllGroupsToBeEmptyWithTimeout(0.2))
        
        // then
        let expectedDeviceClasses = Set(arrayLiteral: "phone", "tablet")
        let actualDeviceClasses = Set(user.clients.flatMap { $0.deviceClass })
        let expectedIdentifiers = Set(arrayLiteral: firstIdentifier, secondIdentifier)
        let actualIdentifiers = Set(user.clients.map { $0.remoteIdentifier })
        XCTAssertEqual(user.clients.count, 2)
        XCTAssertEqual(expectedDeviceClasses, actualDeviceClasses)
        XCTAssertEqual(expectedIdentifiers, actualIdentifiers)
    }
    
    func testThatItAddsOtherUsersNewFetchedClientsToSelfUsersMissingClients() {
        // given
        let (selfClient, _) = createClients()
        XCTAssertEqual(selfClient.missingClients?.count, 0)
        let (firstIdentifier, secondIdentifier) = (NSUUID.createUUID().transportString(), NSUUID.createUUID().transportString())
        let payload = payloadForOtherClients(firstIdentifier, secondIdentifier)
        let response = ZMTransportResponse(payload: payload, HTTPstatus: 200, transportSessionError: nil)
        let identifier = NSUUID.createUUID()
        let user = ZMUser.insertNewObjectInManagedObjectContext(syncMOC)
        user.remoteIdentifier = identifier
        
        // when
        clientRegistrationStatus.mockPhase = .Registered
        _ = sut.nextRequest()
        sut.didReceiveResponse(response, remoteIdentifierObjectSync: nil, forRemoteIdentifiers: Set(arrayLiteral: identifier))
        XCTAssertTrue(waitForAllGroupsToBeEmptyWithTimeout(0.2))
        
        // then
        XCTAssertEqual(user.clients.count, 2)
        XCTAssertEqual(user.clients, selfClient.missingClients)
    }
    
    func testThatItDeletesLocalClientsNotIncludedInResponseToFetchOtherUsersClients() {
        // given
        let (selfClient, localOnlyClient) = createClients()
        XCTAssertEqual(selfClient.missingClients?.count, 0)
        
        let firstIdentifier = NSUUID.createUUID().transportString()
        let payload = payloadForOtherClients(firstIdentifier)
        let response = ZMTransportResponse(payload: payload, HTTPstatus: 200, transportSessionError: nil)
        let identifier = NSUUID.createUUID()
        let user = ZMUser.insertNewObjectInManagedObjectContext(syncMOC)
        user.mutableSetValueForKey("clients").addObject(localOnlyClient)
        user.remoteIdentifier = identifier
        XCTAssertEqual(user.clients.count, 1)
        
        // when
        clientRegistrationStatus.mockPhase = .Registered
        _ = sut.nextRequest()
        sut.didReceiveResponse(response, remoteIdentifierObjectSync: nil, forRemoteIdentifiers: Set(arrayLiteral: identifier))
        XCTAssertTrue(waitForAllGroupsToBeEmptyWithTimeout(0.2))
        
        // then
        XCTAssertEqual(user.clients.count, 1)
        XCTAssertEqual(user.clients.first?.remoteIdentifier, firstIdentifier)
    }
}


// MARK: Deleting
extension UserClientRequestStrategyTests {
    
    func testThatItCreatesARequestToDeleteAClient_UpdateStatus() {
        
        // given
        clientRegistrationStatus.mockPhase = .Unregistered
        clientUpdateStatus.mockPhase = .DeletingClients
        var clients = [
            UserClient.insertNewObjectInManagedObjectContext(self.syncMOC),
            UserClient.insertNewObjectInManagedObjectContext(self.syncMOC)
        ]
        clients.forEach{
            $0.remoteIdentifier = "\($0.objectID)"
            $0.user = ZMUser.selfUserInContext(self.syncMOC)
        }
        self.syncMOC.saveOrRollback()
        
        // when
        clients[0].markForDeletion()
        notifyChangeTrackers(clients[0])
        
        let nextRequest = self.sut.nextRequest()
        
        // then
        AssertOptionalNotNil(nextRequest) {
            XCTAssertEqual($0.path, "/clients/\(clients[0].remoteIdentifier)")
            XCTAssertEqual($0.payload as! [String:String], [
                "email" : self.clientUpdateStatus.mockCredentials.email!,
                "password" : self.clientUpdateStatus.mockCredentials.password!
                ])
            XCTAssertEqual($0.method, ZMTransportRequestMethod.MethodDELETE)
        }
    }
    
    func testThatItDeletesAClientOnSuccess() {
        
        // given
        var client : UserClient!
        
        self.syncMOC.performGroupedBlockAndWait{
            client =  UserClient.insertNewObjectInManagedObjectContext(self.syncMOC)
            client.remoteIdentifier = "\(client.objectID)"
            client.user = ZMUser.selfUserInContext(self.syncMOC)
            self.syncMOC.saveOrRollback()
            
            let response = ZMTransportResponse(payload: [:], HTTPstatus: 200, transportSessionError: nil)
            
            // when
            self.sut.updateUpdatedObject(client, requestUserInfo:nil, response: response, keysToParse:Set(arrayLiteral: ZMUserClientMarkedToDeleteKey))
        }
        XCTAssertTrue(waitForAllGroupsToBeEmptyWithTimeout(0.5))
        
        XCTAssertTrue(client.isZombieObject)

    }
}

import ZMCMockTransport

// MARK: Fetching missed prekeys
extension UserClientRequestStrategyTests {

    func testThatItCreatesARequestToFetchMissedKeysIfClientHasMissingClientsAndMissingKeyIsModified() {
        // given
        clientRegistrationStatus.mockPhase = .Registered

        let client = createSelfClient()
        
        let missingClient = UserClient.insertNewObjectInManagedObjectContext(self.sut.managedObjectContext)
        missingClient.remoteIdentifier = NSString.createAlphanumericalString()
        let missingUser = ZMUser.insertNewObjectInManagedObjectContext(self.sut.managedObjectContext)
        missingUser.remoteIdentifier = NSUUID.createUUID()
        missingClient.user = missingUser
    
        client.missesClient(missingClient)
        notifyChangeTrackers(client)
        
        // when
        let request = self.sut.nextRequest()
        
        // then
        assertRequestEqualsExpectedRequest(request)
    }
    
    func testThatItDoesNotCreateARequestToFetchMissedKeysIfClientHasMissingClientsAndMissingKeyIsNotModified() {
        // given
        let client = createSelfClient()
        let missingClient = createRemoteClient(nil, lastKey: nil)
        
        client.mutableSetValueForKey(ZMUserClientMissingKey).addObject(missingClient)
        notifyChangeTrackers(client)
        
        // when
        let request = self.sut.nextRequest()
        
        // then
        XCTAssertNil(request, "Should not fetch missing clients keys if missing key is not modified")
    }

    func testThatItDoesNotCreateARequestToFetchMissedKeysIfClientDoesNotHaveMissingClientsAndMissingKeyIsNotModified() {
        // given
        let client = createSelfClient()
        createRemoteClient(nil, lastKey: nil)
        
        client.missingClients = nil
        notifyChangeTrackers(client)
        
        // when
        let request = self.sut.nextRequest()
        
        // then
        XCTAssertNil(request, "Should not fetch missing clients keys if missing key is not modified")
    }
    
    func testThatItDoesNotCreateARequestToFetchMissedKeysIfClientDoesNotHaveMissingClientsAndMissingKeyIsModified() {
        // given
        let client = createSelfClient()
        createRemoteClient(nil, lastKey: nil)
        
        client.numberOfKeysRemaining = Int32(self.sut.requestsFactory.keyCount)
        client.missingClients = nil
        client.setLocallyModifiedKeys(Set(arrayLiteral: ZMUserClientMissingKey))
        notifyChangeTrackers(client)
        
        // when
        let request = self.sut.nextRequest()
        
        // then
        XCTAssertNil(request, "Should not fetch missing clients keys if missing key is not modified")
    }
    
    func testThatItPaginatesMissedClientsRequest() {
        
        clientRegistrationStatus.mockPhase = .Registered
        self.sut.requestsFactory = UserClientRequestFactory(missingClientsUserPageSize: 1)
        
        // given
        
        let selfClient = createSelfClient()
        
        let preKeys = try! selfClient.keysStore.box.generatePreKeys(NSMakeRange(0, 2)).map { $0.data!.base64String() }.flatMap{$0}
        let lastKey = try! selfClient.keysStore.box.lastPreKey().data!.base64String()
        
        let client1 = createRemoteClient(Array(preKeys[0..<1]), lastKey: lastKey)
        let client2 = createRemoteClient(Array(preKeys[1..<2]), lastKey: lastKey)

        selfClient.missesClient(client1)
        selfClient.missesClient(client2)

        notifyChangeTrackers(selfClient)
        
        // when
        let firstRequest = self.sut.nextRequest()
        
        // then
        assertRequestEqualsExpectedRequest(firstRequest)
        XCTAssertTrue(waitForAllGroupsToBeEmptyWithTimeout(0.5))

        // and when
        let secondRequest = self.sut.nextRequest()
        
        // then
        assertRequestEqualsExpectedRequest(secondRequest)
        XCTAssertTrue(waitForAllGroupsToBeEmptyWithTimeout(0.5))
        
        // and when
        let thirdRequest = self.sut.nextRequest()
        
        // then
        XCTAssertNil(thirdRequest, "Should not request clients keys any more")
    }
    
    func testThatItRemovesMissingClientWhenResponseContainsItsKey() {
        //given
        let (selfClient, otherClient) = createClients()
        let (request, response) = missingClientsRequestAndResponse(selfClient, missingClients: [otherClient])
        
        //when
        self.sut.updateUpdatedObject(selfClient, requestUserInfo: request.userInfo, response: response, keysToParse: request.keys)
        
        //then
        XCTAssertEqual(selfClient.missingClients!.count, 0)
    }
    
    func testThatItRemovesMissingClientWhenResponseDoesNotContainItsKey() {
        //given
        let (selfClient, otherClient) = self.createClients()
        let (request, response) = self.missingClientsRequestAndResponse(selfClient, missingClients: [otherClient], payload: [String: [String: AnyObject]]())
        
        //when
        self.sut.updateUpdatedObject(selfClient, requestUserInfo: request.userInfo, response: response, keysToParse: request.keys)
        
        //then
        XCTAssertEqual(selfClient.missingClients!.count, 0)
    }
    
    func testThatItRemovesOtherMissingClientsEvenIfOneOfThemHasANilValue() {
        //given
        let (selfClient, otherClient) = createClients()
        let lastKey = try! selfClient.keysStore.lastPreKey().data!.base64String()
        let payload : [ String : [String : AnyObject]] = [
            otherClient.user!.remoteIdentifier!.transportString() :
            [
                otherClient.remoteIdentifier: [
                    "id": 3, "key": lastKey
                ],
                "2360fe0d2adc69e8" : NSNull()
            ]
        ]
        let (request, response) = missingClientsRequestAndResponse(selfClient, missingClients: [otherClient], payload: payload)
        
        //when
        self.sut.updateUpdatedObject(selfClient, requestUserInfo: request.userInfo, response: response, keysToParse: request.keys)
        
        //then
        XCTAssertEqual(selfClient.missingClients!.count, 0)
    }
    
    func testThatItRemovesMissingClientsIfTheRequestForThoseClientsDidNotGiveUsAnyPrekey() {
        
        //given
        let (selfClient, otherClient1) = createClients()
        let lastKey = try! selfClient.keysStore.lastPreKey().data!.base64String()
        let otherClient2 = self.createRemoteClient(generateValidPrekeysStrings(selfClient, howMany: 1), lastKey: lastKey)
        
        let payload : [ String : [String : AnyObject]] = [
            otherClient1.user!.remoteIdentifier!.transportString() : [:]
        ]
        let (request, response) = missingClientsRequestAndResponse(selfClient, missingClients: [otherClient1, otherClient2], payload: payload)
        
        //when
        self.sut.updateUpdatedObject(selfClient, requestUserInfo: request.userInfo, response: response, keysToParse: request.keys)
        
        //then
        XCTAssertEqual(selfClient.missingClients!.count, 0)
    }
    
    func testThatItAddsMissingClientToCurroptedClientsStoreIfTheRequestForTheClientDidNotGiveUsAnyPrekey() {
        
        //given
        let (selfClient, otherClient1) = createClients()
        
        let payload = [otherClient1.user!.remoteIdentifier!.transportString() : [otherClient1.remoteIdentifier: ""]] as [String: [String : AnyObject]]
        let (request, response) = missingClientsRequestAndResponse(selfClient, missingClients: [otherClient1], payload: payload)
        
        //when
        self.sut.updateUpdatedObject(selfClient, requestUserInfo: request.userInfo, response: response, keysToParse: request.keys)
        
        //then
        XCTAssertEqual(selfClient.missingClients!.count, 0)
        XCTAssertTrue(otherClient1.failedToEstablishSession)
    }
    
    
    func testThatItDoesNotRemovesMissingClientsIfTheRequestForThoseClientsGivesUsAtLeastOneNewPrekey() {
        
        //given
        let (selfClient, otherClient1) = createClients()
        let lastKey = try! selfClient.keysStore.lastPreKey().data!.base64String()
        let otherClient2 = self.createRemoteClient(generateValidPrekeysStrings(selfClient, howMany: 1), lastKey: lastKey)

        let payload : [ String : [String : AnyObject]] = [
            otherClient1.user!.remoteIdentifier!.transportString() :
                [
                    otherClient1.remoteIdentifier: [
                        "id": 3, "key": lastKey
                    ],
            ]
        ]
        let (request, response) = missingClientsRequestAndResponse(selfClient, missingClients: [otherClient1, otherClient2], payload: payload)
        
        //when
        
        self.sut.updateUpdatedObject(selfClient, requestUserInfo: request.userInfo, response: response, keysToParse: request.keys)
        
        //then
        XCTAssertEqual(selfClient.missingClients, Set(arrayLiteral: otherClient2))

    }
    
    func testThatItDoesNotRemovesMissingClientsThatWereNotInTheOriginalRequestWhenThePayloadDoesNotContainAnyPrekey() {
        
        //given
        let (selfClient, otherClient1) = createClients()
        let lastKey = try! selfClient.keysStore.lastPreKey().data!.base64String()
        let otherClient2 = self.createRemoteClient(generateValidPrekeysStrings(selfClient, howMany: 1), lastKey: lastKey)
        
        let payload : [ String : [String : AnyObject]] = [
            otherClient1.user!.remoteIdentifier!.transportString() : [:]
        ]
        let (request, response) = missingClientsRequestAndResponse(selfClient, missingClients: [otherClient1, otherClient2], payload: payload)
        
        //when
        let otherClient3 = self.createRemoteClient(generateValidPrekeysStrings(selfClient, howMany: 2), lastKey: lastKey)
        selfClient.missesClient(otherClient3)
        self.sut.updateUpdatedObject(selfClient, requestUserInfo: request.userInfo, response: response, keysToParse: request.keys)
        
        //then
        XCTAssertEqual(selfClient.missingClients, Set(arrayLiteral: otherClient3))
    }

    
    func testThatItRemovesMessagesMissingClientWhenEstablishedSessionWithClient() {
        //given
        let (selfClient, otherClient) = createClients()
        let message = messageThatMissesRecipient(otherClient)
        let (request, response) = missingClientsRequestAndResponse(selfClient, missingClients: [otherClient])
        
        //when
        self.sut.updateUpdatedObject(selfClient, requestUserInfo: request.userInfo, response: response, keysToParse: request.keys)
        
        //then
        XCTAssertEqual(message.missingRecipients.count, 0)
        XCTAssertFalse(message.isExpired)
    }
    
    func testThatItDoesNotExpireMessageWhenEstablishedSessionWithClient() {
        //given
        let (selfClient, otherClient) = createClients()
        let message = messageThatMissesRecipient(otherClient)
        let (request, response) = missingClientsRequestAndResponse(selfClient, missingClients: [otherClient])
        
        //when
        self.sut.updateUpdatedObject(selfClient, requestUserInfo: request.userInfo, response: response, keysToParse: request.keys)
        
        //then
        XCTAssertFalse(message.isExpired)
    }
    
    func testThatItSetsFailedToEstablishSessionOnAMessagesWhenFailedtoEstablishSessionWithClient() {
        //given
        let (selfClient, otherClient) = createClients()
        let message = messageThatMissesRecipient(otherClient)
        
        let payload: [String: [String: AnyObject]] = [otherClient.user!.remoteIdentifier!.transportString(): [otherClient.remoteIdentifier: ["key": "bad key"]]]
        let (request, response) = missingClientsRequestAndResponse(selfClient, missingClients: [otherClient], payload: payload)

        //when
        self.sut.updateUpdatedObject(selfClient, requestUserInfo: request.userInfo, response: response, keysToParse: request.keys)
        
        //then
        XCTAssertFalse(message.isExpired)
        XCTAssertTrue(otherClient.failedToEstablishSession)
    }
    
    func testThatItRemovesMessagesMissingClientWhenFailedToEstablishSessionWithClient() {
        //given
        let (selfClient, otherClient) = createClients()
        let message = messageThatMissesRecipient(otherClient)
        
        let payload: [String: [String: AnyObject]] = [otherClient.user!.remoteIdentifier!.transportString(): [otherClient.remoteIdentifier: ["key": "bad key"]]]
        let (request, response) = missingClientsRequestAndResponse(selfClient, missingClients: [otherClient], payload: payload)
        
        //when
        self.sut.updateUpdatedObject(selfClient, requestUserInfo: request.userInfo, response: response, keysToParse: request.keys)
        
        //then
        XCTAssertEqual(message.missingRecipients.count, 0)
    }
    
    func testThatItRemovesMessagesMissingClientWhenClientHasNoKey() {
        //given
        let (selfClient, otherClient) = createClients()
        let message = messageThatMissesRecipient(otherClient)
        let (request, response) = missingClientsRequestAndResponse(selfClient, missingClients: [otherClient], payload: [String: [String: AnyObject]]())
        
        //when
        self.sut.updateUpdatedObject(selfClient, requestUserInfo: request.userInfo, response: response, keysToParse: request.keys)
        
        //then
        XCTAssertEqual(message.missingRecipients.count, 0)
    }
    
    func testThatItDoesSetFailedToEstablishSessionOnAMessageWhenClientHasNoKey() {
        //given
        let (selfClient, otherClient) = createClients()
        let message = messageThatMissesRecipient(otherClient)
        let (request, response) = missingClientsRequestAndResponse(selfClient, missingClients: [otherClient], payload: [String: [String: AnyObject]]())

        //when
        self.sut.updateUpdatedObject(selfClient, requestUserInfo: request.userInfo, response: response, keysToParse: request.keys)
        
        //then
        XCTAssertFalse(message.isExpired)
        XCTAssertTrue(otherClient.failedToEstablishSession)
    }
    
    func generateValidPrekeysStrings(selfClient: UserClient, howMany: Int) -> [String] {
        return try! selfClient.keysStore.box.generatePreKeys(NSMakeRange(0, howMany)).map { $0.data!.base64String() }
    }
    
    func createClients() -> (UserClient, UserClient) {
        let selfClient = self.createSelfClient()
        let preKeys = try! selfClient.keysStore.box.generatePreKeys(NSMakeRange(0, 2)).map { $0.data!.base64String() }.flatMap{$0}
        let lastKey = try! selfClient.keysStore.box.lastPreKey().data!.base64String()!
        let otherClient = self.createRemoteClient(preKeys, lastKey: lastKey)
        return (selfClient, otherClient)
    }
    
    func createRemoteClient(preKeys: [String]?, lastKey: String?) -> UserClient {
        
        var mockUser: MockUser!
        var mockClient: MockUserClient!
        
        self.mockTransportSession.performRemoteChanges { (session) -> Void in
            if let session = session as? MockTransportSessionObjectCreation {
                mockUser = session.insertUserWithName("foo")
                if let preKeys = preKeys, lastKey = lastKey {
                    mockClient = session.registerClientForUser(mockUser, label: mockUser.name, type: "permanent", preKeys: preKeys, lastPreKey: lastKey)
                }
                else {
                    mockClient = session.registerClientForUser(mockUser, label: mockUser.name, type: "permanent")
                }
            }
        }
        XCTAssertTrue(waitForAllGroupsToBeEmptyWithTimeout(0.5))


        let client = UserClient.insertNewObjectInManagedObjectContext(self.sut.managedObjectContext)
        client.remoteIdentifier = mockClient.identifier
        let user = ZMUser.insertNewObjectInManagedObjectContext(self.sut.managedObjectContext)
        user.remoteIdentifier = NSUUID.uuidWithTransportString(mockUser.identifier)
        client.user = user
        return client
    }
    
    func assertRequestEqualsExpectedRequest(request: ZMTransportRequest?) {
        let client = ZMUser.selfUserInContext(self.sut.managedObjectContext).selfClient()
        let map = MissingClientsMap(Array(client!.missingClients!), pageSize: sut.requestsFactory.missingClientsUserPageSize)
        let expectedRequest = sut.requestsFactory.fetchMissingClientKeysRequest(map).transportRequest

        AssertOptionalNotNil(request, "Should return request if there is inserted UserClient object") { request in
            XCTAssertNotNil(request.payload, "Request should contain payload")
            XCTAssertEqual(request.method, expectedRequest.method)
            XCTAssertEqual(request.path, expectedRequest.path)
            XCTAssertTrue(request.payload.isEqual(expectedRequest.payload))
            
            self.mockTransportSession.completePreviouslySuspendendRequest(request)
        }
    }
    
    func missingClientsRequestAndResponse(selfClient: UserClient, missingClients: [UserClient], payload: [String: [String: AnyObject]]? = nil)
        -> (request: ZMUpstreamRequest, response: ZMTransportResponse)
    {
        let lastKey = try! selfClient.keysStore.lastPreKey().data!.base64String()

        // make sure that we are missing those clients
        for missingClient in missingClients {
            selfClient.missesClient(missingClient)
        }
        
        // generate payload
        var autoGeneratedPayload : [String: [String: AnyObject]] = [:]
        for missingClient in missingClients {
            autoGeneratedPayload[missingClient.user!.remoteIdentifier!.transportString()] = [
                missingClient.remoteIdentifier : [
                    "id" : 12,
                    "key" : lastKey
                ]
            ]
        }
        let payload = payload ?? autoGeneratedPayload
        let response = ZMTransportResponse(payload: payload, HTTPstatus: 200, transportSessionError: nil)
        
        let map = MissingClientsMap(Array(selfClient.missingClients!), pageSize: sut.requestsFactory.missingClientsUserPageSize)
        let request = sut.requestsFactory.fetchMissingClientKeysRequest(map)
        
        return (request, response)
    }
    
    func messageThatMissesRecipient(missingRecipient: UserClient) -> ZMClientMessage {
        let message = ZMClientMessage.insertNewObjectInManagedObjectContext(self.syncMOC)
        let data = ZMGenericMessage(text: self.name, nonce: NSUUID.createUUID().transportString()).data()
        message.addData(data)
        message.missesRecipient(missingRecipient)
        XCTAssertEqual(message.missingRecipients.count, 1)
        return message
    }
    
    func testThatItCreatesMissingClientsRequestAfterRemoteSelfClientIsFetched() {
     
        clientRegistrationStatus.mockPhase = .Registered
     
        let selfClient = createSelfClient()
     
        let remoteClientIdentifier = String.createAlphanumericalString()
     
         // when
         let newSelfClient = UserClient.createOrUpdateClient(["id": remoteClientIdentifier , "type": "permanent", "time": NSDate().transportString()], context: self.syncMOC)!
         newSelfClient.user = selfClient.user
         notifyChangeTrackers(selfClient)
     
         // when
         let request = self.sut.nextRequest()
     
         // then
         AssertOptionalNotNil(request, "Should create request to fetch clients' keys") {request in
             XCTAssertEqual(request.method, ZMTransportRequestMethod.MethodPOST)
             XCTAssertEqual(request.path, "/users/prekeys")
             let payloadDictionary = request.payload.asDictionary()
             let userPayload = payloadDictionary[payloadDictionary.keys.first!] as? NSArray
             AssertOptionalNotNil(userPayload, "Clients map should contain missid user id") {userPayload in
                 XCTAssertTrue(userPayload.containsObject(remoteClientIdentifier), "Clients map should contain all missed clients id for each user")
             }
         }
    }
}



// MARK: fetching other user's clients / RemoteIdentifierObjectSync
extension UserClientRequestStrategyTests {
    
    func testThatItDoesNotDeleteAnObjectWhenResponseContainsRemoteID() {
        let (_, otherClient) = self.createClients()
        let user = otherClient.user
        let payload =  [["id" : otherClient.remoteIdentifier]]
        let response = ZMTransportResponse(payload: payload, HTTPstatus: 200, transportSessionError: nil)
        
        //when
        self.sut.didReceiveResponse(response, remoteIdentifierObjectSync: nil, forRemoteIdentifiers:Set(arrayLiteral: user!.remoteIdentifier!))
        XCTAssertTrue(waitForAllGroupsToBeEmptyWithTimeout(0.2))
        XCTAssertFalse(otherClient.deleted)
    }
    
    func testThatItAddsNewInsertedClientsToIgnoredClients() {
        let (selfClient, otherClient) = self.createClients()
        let user = otherClient.user
        let payload =  [["id" : otherClient.remoteIdentifier]]
        let response = ZMTransportResponse(payload: payload, HTTPstatus: 200, transportSessionError: nil)
        
        //when
        self.sut.didReceiveResponse(response, remoteIdentifierObjectSync: nil, forRemoteIdentifiers:Set(arrayLiteral: user!.remoteIdentifier!))
        XCTAssertTrue(waitForAllGroupsToBeEmptyWithTimeout(0.2))
        XCTAssertFalse(selfClient.trustedClients.contains(otherClient))
        XCTAssertTrue(selfClient.ignoredClients.contains(otherClient))
    }
    
    func testThatItDeletesAnObjectWhenResponseDoesNotContainRemoteID() {
        let (_, otherClient) = self.createClients()
        let user = otherClient.user
        let remoteID = "otherRemoteID"
        let payload =  [[remoteID]]
        XCTAssertNotEqual(otherClient.remoteIdentifier, remoteID)
        let response = ZMTransportResponse(payload: payload, HTTPstatus: 200, transportSessionError: nil)
        
        //when
        self.sut.didReceiveResponse(response, remoteIdentifierObjectSync: nil, forRemoteIdentifiers:Set(arrayLiteral: user!.remoteIdentifier!))
        XCTAssertTrue(waitForAllGroupsToBeEmptyWithTimeout(0.2))
        XCTAssertTrue(otherClient.deleted)
    }
}

// MARK: - Updating from push events
extension UserClientRequestStrategyTests {
    
    static func payloadForAddingClient(clientId : String,
        label : String = "device label",
        time : NSDate = NSDate(timeIntervalSince1970: 0)
        ) -> [String: AnyObject] {
        
            return [
                "client" : [
                    "id" : clientId,
                    "label" : label,
                    "time" : time.transportString(),
                    "type" : "permanent",
                ],
                "type" : "user.client-add"
            ]
    }
    
    static func payloadForDeletingClient(clientId : String) -> [String: AnyObject] {
            
            return [
                "client" : [
                    "id" : clientId,
                ],
                "type" : "user.client-remove"
            ]
    }
    
    func testThatItAddsAnIgnoredSelfUserClientWhenReceivingAPush() {
        
        // given
        let selfUser = ZMUser.selfUserInContext(self.syncMOC)
        let (selfClient, _) = createClients()
        let clientId = "94766bd92f56923d"
        let clientLabel = "iPhone 23sd Plus Air Pro C"
        let clientTime = NSDate(timeIntervalSince1970: 1234555)
        
        XCTAssertEqual(selfUser.clients.count, 1)
        let payload = [
            "id" : "27330a52-bab6-11e5-8183-22000b080265",
            "payload" : [
                UserClientRequestStrategyTests.payloadForAddingClient(clientId, label: clientLabel, time: clientTime)
            ],
            "transient" : false
        ]
        
        let events = ZMUpdateEvent.eventsArrayFromPushChannelData(payload)
        guard let event = events!.first else {
            XCTFail()
            return
        }
        
        // when
        self.sut.processEvents([event], liveEvents:true, prefetchResult: .None)
        
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
        let selfUser = ZMUser.selfUserInContext(self.syncMOC)
        let clientId = "94766bd92f56923d"
        
        XCTAssertEqual(selfUser.clients.count, 0)
        let payload = UserClientRequestStrategyTests.payloadForAddingClient(clientId)
        let event = ZMUpdateEvent(fromEventStreamPayload: payload, uuid: nil)
        
        // when
        self.sut.processEvents([event], liveEvents:false, prefetchResult: .None)
        
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
        let selfUser = ZMUser.selfUserInContext(self.syncMOC)
        let existingClient = self.createSelfClient()
        
        XCTAssertEqual(selfUser.clients.count, 1)
        let payload = [
            "id" : "27330a52-bab6-11e5-8183-22000b080265",
            "payload" : [
                UserClientRequestStrategyTests.payloadForAddingClient(existingClient.remoteIdentifier)
            ],
            "transient" : false
        ]
        
        let events = ZMUpdateEvent.eventsArrayFromPushChannelData(payload)
        guard let event = events!.first else {
            XCTFail()
            return
        }
        
        // when
        self.sut.processEvents([event], liveEvents:true, prefetchResult: .None)
        
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
        let selfUser = ZMUser.selfUserInContext(self.syncMOC)
        let existingClient1 = self.createSelfClient()
        let existingClient2 = self.createClientForUser(selfUser, createSessionWithSelfUser:false)
        
        XCTAssertEqual(selfUser.clients.count, 2)
        let payload = [
            "id" : "27330a52-bab6-11e5-8183-22000b080265",
            "payload" : [
                UserClientRequestStrategyTests.payloadForDeletingClient(existingClient2.remoteIdentifier)
            ],
            "transient" : false
        ]
        
        let events = ZMUpdateEvent.eventsArrayFromPushChannelData(payload)
        guard let event = events!.first else {
            XCTFail()
            return
        }
        
        // when
        self.sut.processEvents([event], liveEvents:true, prefetchResult: .None)
        
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
        let selfUser = ZMUser.selfUserInContext(syncMOC)
        let existingClient = createSelfClient()

        let fingerprint = try? syncMOC.zm_cryptKeyStore.box.localFingerprint()
        let previousLastPrekey = try? syncMOC.zm_cryptKeyStore.lastPreKey()
        
        XCTAssertEqual(selfUser.clients.count, 1)
        let payload = [
            "id" : "27330a52-bab6-11e5-8183-22000b080265",
            "payload" : [
                UserClientRequestStrategyTests.payloadForDeletingClient(existingClient.remoteIdentifier)
            ],
            "transient" : false
        ]
        
        let events = ZMUpdateEvent.eventsArrayFromPushChannelData(payload)
        guard let event = events!.first else { return XCTFail() }
        
        // when
        self.sut.processEvents([event], liveEvents:true, prefetchResult: .None)
        
        // then
        let newFingerprint = try? syncMOC.zm_cryptKeyStore.box.localFingerprint()
        let newLastPrekey = try? syncMOC.zm_cryptKeyStore.lastPreKey()
        
        XCTAssertNotNil(fingerprint)
        XCTAssertNotNil(newFingerprint)
        XCTAssertNotEqual(fingerprint, newFingerprint)
        XCTAssertNil(selfUser.clients.first?.remoteIdentifier)
        XCTAssertNil(syncMOC.persistentStoreMetadataForKey(ZMPersistedClientIdKey))
        XCTAssertNotNil(fingerprint)
        XCTAssertNotNil(newFingerprint)
        XCTAssertNotEqual(previousLastPrekey, newLastPrekey)
    }
    
    func testThatItCreatesARequestForClientsThatNeedToUploadSignalingKeys() {
        
        // given
        clientRegistrationStatus.mockPhase = .Registered

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
        let response = ZMTransportResponse(payload: nil, HTTPstatus: 200, transportSessionError: nil)
        request?.completeWithResponse(response)
        XCTAssertTrue(waitForAllGroupsToBeEmptyWithTimeout(0.2))
        
        // then
        XCTAssertNotNil(existingClient.apsVerificationKey)
        XCTAssertNotNil(existingClient.apsDecryptionKey)
        XCTAssertFalse(existingClient.needsToUploadSignalingKeys)
        XCTAssertFalse(existingClient.hasLocalModificationsForKey(ZMUserClientNeedsToUpdateSignalingKeysKey))

    }
    
    func testThatItRetriesOnceWhenUploadSignalingKeysFails() {
        
        // given
        clientRegistrationStatus.mockPhase = .Registered
        
        let existingClient = createSelfClient()
        XCTAssertNil(existingClient.apsVerificationKey)
        XCTAssertNil(existingClient.apsDecryptionKey)
        
        existingClient.needsToUploadSignalingKeys = true
        existingClient.setLocallyModifiedKeys(Set(arrayLiteral: ZMUserClientNeedsToUpdateSignalingKeysKey))
        self.sut.contextChangeTrackers.forEach{$0.objectsDidChange(Set(arrayLiteral: existingClient))}
        
        // when
        let request = self.sut.nextRequest()
        XCTAssertNotNil(request)
        let badResponse = ZMTransportResponse(payload: ["label": "bad-request"], HTTPstatus: 400, transportSessionError: nil)

        request?.completeWithResponse(badResponse)
        XCTAssertTrue(waitForAllGroupsToBeEmptyWithTimeout(0.2))
        
        // and when
        let secondRequest = self.sut.nextRequest()
        XCTAssertNotNil(secondRequest)
        let success = ZMTransportResponse(payload: nil, HTTPstatus: 200, transportSessionError: nil)

        request?.completeWithResponse(success)
        XCTAssertTrue(waitForAllGroupsToBeEmptyWithTimeout(0.2))
        
        // and when
        let thirdRequest = self.sut.nextRequest()
        XCTAssertNil(thirdRequest)
        
    }
    
    
    func testThatItResetsKeyForMissingClientIfThereIsNoMissingClient(){
        // given
        let client = self.createSelfClient()
        client.setLocallyModifiedKeys(Set(arrayLiteral: ZMUserClientMissingKey))
        XCTAssertTrue(client.keysThatHaveLocalModifications.contains(ZMUserClientMissingKey))

        // when
        let shouldCreateRequest = sut.shouldCreateRequestToSyncObject(client, forKeys: Set(arrayLiteral: ZMUserClientMissingKey), withSync: sut.modifiedSync)
        
        // then
        XCTAssertFalse(shouldCreateRequest)
        XCTAssertFalse(client.keysThatHaveLocalModifications.contains(ZMUserClientMissingKey))
        
    }
    
    func testThatItDoesNotResetKeyForMissingClientIfThereIsAMissingClient(){
        // given
        let client = self.createSelfClient()
        client.missesClient(UserClient.insertNewObjectInManagedObjectContext(self.syncMOC))
        client.setLocallyModifiedKeys(Set(arrayLiteral: ZMUserClientMissingKey))
        XCTAssertTrue(client.keysThatHaveLocalModifications.contains(ZMUserClientMissingKey))
        
        // when
        let shouldCreateRequest = sut.shouldCreateRequestToSyncObject(client, forKeys: Set(arrayLiteral: ZMUserClientMissingKey), withSync: sut.modifiedSync)
        
        // then
        XCTAssertTrue(shouldCreateRequest)
        XCTAssertTrue(client.keysThatHaveLocalModifications.contains(ZMUserClientMissingKey))
        
    }

}


