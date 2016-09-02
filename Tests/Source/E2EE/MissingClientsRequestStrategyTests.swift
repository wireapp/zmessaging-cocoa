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

class FakeConfirmationStatus : BackgroundAPNSConfirmationStatus {
    override var needsToSyncMessages: Bool {
        return true
    }
}

class MissingClientsRequestStrategyTests: RequestStrategyTestBase {

    var sut: MissingClientsRequestStrategy!
    var clientRegistrationStatus: ZMMockClientRegistrationStatus!
    var confirmationStatus : FakeConfirmationStatus!
    var loginProvider: FakeCredentialProvider!
    var updateProvider: FakeCredentialProvider!
    var cookieStorage : ZMPersistentCookieStorage!
    var fakeApplication : FakeApplication!
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
        let newKeyStore = FakeKeysStore()
        self.syncMOC.userInfo.setObject(newKeyStore, forKey: "ZMUserClientKeysStore")
        cookieStorage = ZMPersistentCookieStorage(forServerName: "myServer")
        let cookie = ZMCookie(managedObjectContext: self.syncMOC, cookieStorage: cookieStorage)
        loginProvider = FakeCredentialProvider()
        updateProvider = FakeCredentialProvider()
        fakeApplication = FakeApplication()
        fakeApplication.mockApplicationState = UIApplicationState.Active
        confirmationStatus = FakeConfirmationStatus(application: fakeApplication, managedObjectContext: self.syncMOC, backgroundActivityFactory: FakeBackgroundActivityFactory())
        
        clientRegistrationStatus = ZMMockClientRegistrationStatus(managedObjectContext: self.syncMOC, loginCredentialProvider:loginProvider, updateCredentialProvider:updateProvider, cookie:cookie, registrationStatusDelegate: nil)
        
        sut = MissingClientsRequestStrategy(clientRegistrationStatus: clientRegistrationStatus, apnsConfirmationStatus: confirmationStatus, managedObjectContext: self.syncMOC)
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        clientRegistrationStatus.tearDown()
        clientRegistrationStatus = nil
        sut.tearDown()
        sut = nil
        super.tearDown()
    }
    
    func testThatItCreatesMissingClientsRequest() {
        
        // given
        let client = UserClient.insertNewObjectInManagedObjectContext(self.syncMOC)
        
        let missingUser = ZMUser.insertNewObjectInManagedObjectContext(self.syncMOC)
        missingUser.remoteIdentifier = NSUUID.createUUID()
        
        let firstMissingClient = UserClient.insertNewObjectInManagedObjectContext(self.syncMOC)
        firstMissingClient.remoteIdentifier = NSString.createAlphanumericalString()
        firstMissingClient.user = missingUser
        
        let secondMissingClient = UserClient.insertNewObjectInManagedObjectContext(self.syncMOC)
        secondMissingClient.remoteIdentifier = NSString.createAlphanumericalString()
        secondMissingClient.user = missingUser
        
        // when
        client.missesClient(firstMissingClient)
        client.missesClient(secondMissingClient)
        
        let request = sut.requestsFactory.fetchMissingClientKeysRequest(client.missingClients!)
        _ = [missingUser.remoteIdentifier!.transportString(): [firstMissingClient.remoteIdentifier, secondMissingClient.remoteIdentifier]]
        
        // then
        AssertOptionalNotNil(request, "Should create request to fetch clients' keys") {request in
            XCTAssertEqual(request.transportRequest.method, ZMTransportRequestMethod.MethodPOST)
            XCTAssertEqual(request.transportRequest.path, "/users/prekeys")
            let userPayload = request.transportRequest.payload.asDictionary()[missingUser.remoteIdentifier!.transportString()] as? NSArray
            AssertOptionalNotNil(userPayload, "Clients map should contain missid user id") {userPayload in
                XCTAssertTrue(userPayload.containsObject(firstMissingClient.remoteIdentifier), "Clients map should contain all missed clients id for each user")
                XCTAssertTrue(userPayload.containsObject(secondMissingClient.remoteIdentifier), "Clients map should contain all missed clients id for each user")
            }
        }
    }
    
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
        sut.notifyChangeTrackers(client)
        
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
        sut.notifyChangeTrackers(client)
        
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
        sut.notifyChangeTrackers(client)
        
        // when
        let request = self.sut.nextRequest()
        
        // then
        XCTAssertNil(request, "Should not fetch missing clients keys if missing key is not modified")
    }
    
    func testThatItDoesNotCreateARequestToFetchMissedKeysIfClientDoesNotHaveMissingClientsAndMissingKeyIsModified() {
        // given
        let client = createSelfClient()
        createRemoteClient(nil, lastKey: nil)
        
        client.missingClients = nil
        client.setLocallyModifiedKeys(Set(arrayLiteral: ZMUserClientMissingKey))
        sut.notifyChangeTrackers(client)
        
        // when
        let request = self.sut.nextRequest()
        
        // then
        XCTAssertNil(request, "Should not fetch missing clients keys if missing key is not modified")
    }
    
    func testThatItPaginatesMissedClientsRequest() {
        
        clientRegistrationStatus.mockPhase = .Registered
        self.sut.requestsFactory = MissingClientsRequestFactory(pageSize: 1)
        
        // given
        
        let selfClient = createSelfClient()
        let (prekeys, lastKey) = generatePrekeyAndLastKey(selfClient)
        
        let client1 = createRemoteClient(Array(prekeys[0..<1]), lastKey: lastKey)
        let client2 = createRemoteClient(Array(prekeys[1..<2]), lastKey: lastKey)
        
        selfClient.missesClient(client1)
        selfClient.missesClient(client2)
        
        sut.notifyChangeTrackers(selfClient)
        
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
        let lastKey = try! selfClient.keysStore.lastPreKey()
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
        let lastKey = try! selfClient.keysStore.lastPreKey()
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
        let lastKey = try! selfClient.keysStore.lastPreKey()
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
        let lastKey = try! selfClient.keysStore.lastPreKey()
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
        
        let payload: [String: [String: AnyObject]] = [otherClient.user!.remoteIdentifier!.transportString(): [otherClient.remoteIdentifier: ["key": "a2V5"]]]
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
        
        let payload: [String: [String: AnyObject]] = [otherClient.user!.remoteIdentifier!.transportString(): [otherClient.remoteIdentifier: ["key": "a2V5"]]]
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
    
    func generateValidPrekeysStrings(selfClient: UserClient, howMany: UInt16) -> [String] {
        var prekeys : [String] = []
        selfClient.keysStore.encryptionContext.perform { (sessionsDirectory) in
            let keysAndIds = try! sessionsDirectory.generatePrekeys(Range<UInt16>(0..<howMany))
            prekeys = keysAndIds.map { $0.prekey }
        }
        return prekeys
    }
    
    func assertRequestEqualsExpectedRequest(request: ZMTransportRequest?) {
        let client = ZMUser.selfUserInContext(self.sut.managedObjectContext).selfClient()
        let expectedRequest = sut.requestsFactory.fetchMissingClientKeysRequest(client!.missingClients!).transportRequest
        
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
        let lastKey = try! selfClient.keysStore.lastPreKey()
        
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
        let request = sut.requestsFactory.fetchMissingClientKeysRequest(selfClient.missingClients!)
        
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
        sut.notifyChangeTrackers(selfClient)
        
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

