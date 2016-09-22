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
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
        let newKeyStore = FakeKeysStore()
        self.syncMOC.userInfo.setObject(newKeyStore, forKey: "ZMUserClientKeysStore" as NSCopying)
        cookieStorage = ZMPersistentCookieStorage(forServerName: "myServer")
        let cookie = ZMCookie(managedObjectContext: self.syncMOC, cookieStorage: cookieStorage)
        loginProvider = FakeCredentialProvider()
        updateProvider = FakeCredentialProvider()
        confirmationStatus = FakeConfirmationStatus(application: self.application, managedObjectContext: self.syncMOC, backgroundActivityFactory: FakeBackgroundActivityFactory())
        
        clientRegistrationStatus = ZMMockClientRegistrationStatus(managedObjectContext: self.syncMOC, loginCredentialProvider:loginProvider, update:updateProvider, cookie:cookie, registrationStatusDelegate: nil)
        
        sut = MissingClientsRequestStrategy(clientRegistrationStatus: clientRegistrationStatus, apnsConfirmationStatus: confirmationStatus, managedObjectContext: self.syncMOC)
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        clientRegistrationStatus.tearDown()
        clientRegistrationStatus = nil
        confirmationStatus.tearDown()
        confirmationStatus = nil
        sut.tearDown()
        sut = nil
        super.tearDown()
    }
    
    func testThatItCreatesMissingClientsRequest() {
        
        // given
        let client = UserClient.insertNewObject(in: self.syncMOC)
        
        let missingUser = ZMUser.insertNewObject(in: self.syncMOC)
        missingUser.remoteIdentifier = UUID.create()
        
        let firstMissingClient = UserClient.insertNewObject(in: self.syncMOC)
        firstMissingClient.remoteIdentifier = NSString.createAlphanumerical()
        firstMissingClient.user = missingUser
        
        let secondMissingClient = UserClient.insertNewObject(in: self.syncMOC)
        secondMissingClient.remoteIdentifier = NSString.createAlphanumerical()
        secondMissingClient.user = missingUser
        
        // when
        client.missesClient(firstMissingClient)
        client.missesClient(secondMissingClient)
        
        let request = sut.requestsFactory.fetchMissingClientKeysRequest(client.missingClients!)
        _ = [missingUser.remoteIdentifier!.transportString(): [firstMissingClient.remoteIdentifier, secondMissingClient.remoteIdentifier]]
        
        // then
        AssertOptionalNotNil(request, "Should create request to fetch clients' keys") { request in
            XCTAssertEqual(request.transportRequest.method, ZMTransportRequestMethod.methodPOST)
            XCTAssertEqual(request.transportRequest.path, "/users/prekeys")
            let userPayload = request.transportRequest.payload?.asDictionary()?[missingUser.remoteIdentifier!.transportString()] as? NSArray
            AssertOptionalNotNil(userPayload, "Clients map should contain missid user id") {userPayload in
                XCTAssertTrue(userPayload.contains(firstMissingClient.remoteIdentifier!), "Clients map should contain all missed clients id for each user")
                XCTAssertTrue(userPayload.contains(secondMissingClient.remoteIdentifier!), "Clients map should contain all missed clients id for each user")
            }
        }
    }
    
    func testThatItCreatesARequestToFetchMissedKeysIfClientHasMissingClientsAndMissingKeyIsModified() {
        // given
        clientRegistrationStatus.mockPhase = .registered
        
        let client = createSelfClient()
        
        let missingClient = UserClient.insertNewObject(in: self.sut.managedObjectContext)
        missingClient.remoteIdentifier = NSString.createAlphanumerical()
        let missingUser = ZMUser.insertNewObject(in: self.sut.managedObjectContext)
        missingUser.remoteIdentifier = UUID.create()
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
        
        client.mutableSetValue(forKey: ZMUserClientMissingKey).add(missingClient)
        sut.notifyChangeTrackers(client)
        
        // when
        let request = self.sut.nextRequest()
        
        // then
        XCTAssertNil(request, "Should not fetch missing clients keys if missing key is not modified")
    }
    
    func testThatItDoesNotCreateARequestToFetchMissedKeysIfClientDoesNotHaveMissingClientsAndMissingKeyIsNotModified() {
        // given
        let client = createSelfClient()
        let _ = createRemoteClient(nil, lastKey: nil)
        
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
        let _ = createRemoteClient(nil, lastKey: nil)
        
        client.missingClients = nil
        client.setLocallyModifiedKeys(Set(arrayLiteral: ZMUserClientMissingKey))
        sut.notifyChangeTrackers(client)
        
        // when
        let request = self.sut.nextRequest()
        
        // then
        XCTAssertNil(request, "Should not fetch missing clients keys if missing key is not modified")
    }
    
    func testThatItPaginatesMissedClientsRequest() {
        
        clientRegistrationStatus.mockPhase = .registered
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
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // and when
        let secondRequest = self.sut.nextRequest()
        
        // then
        assertRequestEqualsExpectedRequest(secondRequest)
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
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
        let _ = self.sut.updateUpdatedObject(selfClient, requestUserInfo: request.userInfo, response: response, keysToParse: request.keys)
        
        //then
        XCTAssertEqual(selfClient.missingClients!.count, 0)
    }
    
    func testThatItRemovesMissingClientWhenResponseDoesNotContainItsKey() {
        //given
        let (selfClient, otherClient) = self.createClients()
        let (request, response) = self.missingClientsRequestAndResponse(selfClient, missingClients: [otherClient], payload: [String: [String: AnyObject]]())
        
        //when
        let _ = self.sut.updateUpdatedObject(selfClient, requestUserInfo: request.userInfo, response: response, keysToParse: request.keys)
        
        //then
        XCTAssertEqual(selfClient.missingClients!.count, 0)
    }
    
    func testThatItRemovesOtherMissingClientsEvenIfOneOfThemHasANilValue() {
        //given
        let (selfClient, otherClient) = createClients()
        let lastKey = try! selfClient.keysStore.lastPreKey()
        let payload : [ String : [String : Any]] = [
            otherClient.user!.remoteIdentifier!.transportString() :
                [
                    otherClient.remoteIdentifier!: [
                        "id": 3, "key": lastKey
                    ],
                    "2360fe0d2adc69e8" : NSNull()
            ]
        ]
        let (request, response) = missingClientsRequestAndResponse(selfClient, missingClients: [otherClient], payload: payload)
        
        //when
        let _ = self.sut.updateUpdatedObject(selfClient, requestUserInfo: request.userInfo, response: response, keysToParse: request.keys)
        
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
        let _ = self.sut.updateUpdatedObject(selfClient, requestUserInfo: request.userInfo, response: response, keysToParse: request.keys)
        
        //then
        XCTAssertEqual(selfClient.missingClients!.count, 0)
    }
    
    func testThatItAddsMissingClientToCurroptedClientsStoreIfTheRequestForTheClientDidNotGiveUsAnyPrekey() {
        
        //given
        let (selfClient, otherClient1) = createClients()
        
        let payload = [otherClient1.user!.remoteIdentifier!.transportString() : [otherClient1.remoteIdentifier!: ""]] as [String: [String : Any]]
        let (request, response) = missingClientsRequestAndResponse(selfClient, missingClients: [otherClient1], payload: payload)
        
        //when
        _ = self.sut.updateUpdatedObject(selfClient, requestUserInfo: request.userInfo, response: response, keysToParse: request.keys)
        
        //then
        XCTAssertEqual(selfClient.missingClients!.count, 0)
        XCTAssertTrue(otherClient1.failedToEstablishSession)
    }
    
    
    func testThatItDoesNotRemovesMissingClientsIfTheRequestForThoseClientsGivesUsAtLeastOneNewPrekey() {
        
        //given
        let (selfClient, otherClient1) = createClients()
        let lastKey = try! selfClient.keysStore.lastPreKey()
        let otherClient2 = self.createRemoteClient(generateValidPrekeysStrings(selfClient, howMany: 1), lastKey: lastKey)
        
        let payload : [ String : [String : Any]] = [
            otherClient1.user!.remoteIdentifier!.transportString() :
                [
                    otherClient1.remoteIdentifier!: [
                        "id": 3, "key": lastKey
                    ],
            ]
        ]
        let (request, response) = missingClientsRequestAndResponse(selfClient, missingClients: [otherClient1, otherClient2], payload: payload)
        
        //when
        
        let _ = self.sut.updateUpdatedObject(selfClient, requestUserInfo: request.userInfo, response: response, keysToParse: request.keys)
        
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
        let _ = self.sut.updateUpdatedObject(selfClient, requestUserInfo: request.userInfo, response: response, keysToParse: request.keys)
        
        //then
        XCTAssertEqual(selfClient.missingClients, Set(arrayLiteral: otherClient3))
    }
    
    
    func testThatItRemovesMessagesMissingClientWhenEstablishedSessionWithClient() {
        //given
        let (selfClient, otherClient) = createClients()
        let message = messageThatMissesRecipient(otherClient)
        let (request, response) = missingClientsRequestAndResponse(selfClient, missingClients: [otherClient])
        
        //when
        let _ = self.sut.updateUpdatedObject(selfClient, requestUserInfo: request.userInfo, response: response, keysToParse: request.keys)
        
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
        let _ = self.sut.updateUpdatedObject(selfClient, requestUserInfo: request.userInfo, response: response, keysToParse: request.keys)
        
        //then
        XCTAssertFalse(message.isExpired)
    }
    
    func testThatItSetsFailedToEstablishSessionOnAMessagesWhenFailedtoEstablishSessionWithClient() {
        //given
        let (selfClient, otherClient) = createClients()
        let message = messageThatMissesRecipient(otherClient)
        
        let payload: [String: [String: Any]] = [otherClient.user!.remoteIdentifier!.transportString(): [otherClient.remoteIdentifier!: ["key": "a2V5"]]]
        let (request, response) = missingClientsRequestAndResponse(selfClient, missingClients: [otherClient], payload: payload)
        
        //when
        let _ = self.sut.updateUpdatedObject(selfClient, requestUserInfo: request.userInfo, response: response, keysToParse: request.keys)
        
        //then
        XCTAssertFalse(message.isExpired)
        XCTAssertTrue(otherClient.failedToEstablishSession)
    }
    
    func testThatItRemovesMessagesMissingClientWhenFailedToEstablishSessionWithClient() {
        //given
        let (selfClient, otherClient) = createClients()
        let message = messageThatMissesRecipient(otherClient)
        
        let payload: [String: [String: Any]] = [otherClient.user!.remoteIdentifier!.transportString(): [otherClient.remoteIdentifier!: ["key": "a2V5"]]]
        let (request, response) = missingClientsRequestAndResponse(selfClient, missingClients: [otherClient], payload: payload)
        
        //when
        let _ = self.sut.updateUpdatedObject(selfClient, requestUserInfo: request.userInfo, response: response, keysToParse: request.keys)
        
        //then
        XCTAssertEqual(message.missingRecipients.count, 0)
    }
    
    func testThatItRemovesMessagesMissingClientWhenClientHasNoKey() {
        //given
        let (selfClient, otherClient) = createClients()
        let message = messageThatMissesRecipient(otherClient)
        let (request, response) = missingClientsRequestAndResponse(selfClient, missingClients: [otherClient], payload: [String: [String: AnyObject]]())
        
        //when
        let _ = self.sut.updateUpdatedObject(selfClient, requestUserInfo: request.userInfo, response: response, keysToParse: request.keys)
        
        //then
        XCTAssertEqual(message.missingRecipients.count, 0)
    }
    
    func testThatItDoesSetFailedToEstablishSessionOnAMessageWhenClientHasNoKey() {
        //given
        let (selfClient, otherClient) = createClients()
        let message = messageThatMissesRecipient(otherClient)
        let (request, response) = missingClientsRequestAndResponse(selfClient, missingClients: [otherClient], payload: [String: [String: AnyObject]]())
        
        //when
        let _ = self.sut.updateUpdatedObject(selfClient, requestUserInfo: request.userInfo, response: response, keysToParse: request.keys)
        
        //then
        XCTAssertFalse(message.isExpired)
        XCTAssertTrue(otherClient.failedToEstablishSession)
    }
    
    func generateValidPrekeysStrings(_ selfClient: UserClient, howMany: UInt16) -> [String] {
        var prekeys : [String] = []
        selfClient.keysStore.encryptionContext.perform { (sessionsDirectory) in
            let keysAndIds = try! sessionsDirectory.generatePrekeys((0..<howMany))
            prekeys = keysAndIds.map { $0.prekey }
        }
        return prekeys
    }
    
    func assertRequestEqualsExpectedRequest(_ request: ZMTransportRequest?) {
        let client = ZMUser.selfUser(in: self.sut.managedObjectContext).selfClient()
        let expectedRequest = sut.requestsFactory.fetchMissingClientKeysRequest(client!.missingClients!).transportRequest!
        
        AssertOptionalNotNil(request, "Should return request if there is inserted UserClient object") { request in
            XCTAssertNotNil(request.payload, "Request should contain payload")
            XCTAssertEqual(request.method, expectedRequest.method)
            XCTAssertEqual(request.path, expectedRequest.path)
            XCTAssertTrue(request.payload!.isEqual(expectedRequest.payload))
            
            self.mockTransportSession.completePreviouslySuspendendRequest(request)
        }
    }
    
    func missingClientsRequestAndResponse(_ selfClient: UserClient, missingClients: [UserClient], payload: [String: [String: Any]]? = nil)
        -> (request: ZMUpstreamRequest, response: ZMTransportResponse)
    {
        let lastKey = try! selfClient.keysStore.lastPreKey()
        
        // make sure that we are missing those clients
        for missingClient in missingClients {
            selfClient.missesClient(missingClient)
        }
        
        // generate payload
        var autoGeneratedPayload : [String: [String: Any]] = [:]
        for missingClient in missingClients {
            autoGeneratedPayload[missingClient.user!.remoteIdentifier!.transportString()] = [
                missingClient.remoteIdentifier! : [
                    "id" : 12,
                    "key" : lastKey
                ]
            ]
        }
        let payload = payload ?? autoGeneratedPayload
        let response = ZMTransportResponse(payload: payload as ZMTransportData, httpStatus: 200, transportSessionError: nil)
        let request = sut.requestsFactory.fetchMissingClientKeysRequest(selfClient.missingClients!)
        
        return (request!, response)
    }
    
    func messageThatMissesRecipient(_ missingRecipient: UserClient) -> ZMClientMessage {
        let message = ZMClientMessage.insertNewObject(in: self.syncMOC)
        let data = ZMGenericMessage(text: self.name!, nonce: UUID.create().transportString()).data()!
        message.add(data)
        message.missesRecipient(missingRecipient)
        XCTAssertEqual(message.missingRecipients.count, 1)
        return message
    }
    
    func testThatItCreatesMissingClientsRequestAfterRemoteSelfClientIsFetched() {
        
        clientRegistrationStatus.mockPhase = .registered
        
        let selfClient = createSelfClient()
        
        let remoteClientIdentifier = String.createAlphanumerical()
        
        // when
        let payload = [
            "id": remoteClientIdentifier as AnyObject,
            "type": "permanent" as AnyObject,
            "time": Date().transportString() as AnyObject
        ]
        let newSelfClient = UserClient.createOrUpdateClient(payload, context: self.syncMOC)!
        newSelfClient.user = selfClient.user
        sut.notifyChangeTrackers(selfClient)
        
        // when
        let request = self.sut.nextRequest()
        
        // then
        AssertOptionalNotNil(request, "Should create request to fetch clients' keys") {request in
            XCTAssertEqual(request.method, ZMTransportRequestMethod.methodPOST)
            XCTAssertEqual(request.path, "/users/prekeys")
            let payloadDictionary = request.payload!.asDictionary()!
            let userPayload = payloadDictionary[payloadDictionary.keys.first!] as? NSArray
            AssertOptionalNotNil(userPayload, "Clients map should contain missid user id") {userPayload in
                XCTAssertTrue(userPayload.contains(remoteClientIdentifier), "Clients map should contain all missed clients id for each user")
            }
        }
    }
    
    func testThatItResetsKeyForMissingClientIfThereIsNoMissingClient(){
        // given
        let client = self.createSelfClient()
        client.setLocallyModifiedKeys(Set(arrayLiteral: ZMUserClientMissingKey))
        XCTAssertTrue(client.keysThatHaveLocalModifications.contains(ZMUserClientMissingKey))
        
        // when
        let shouldCreateRequest = sut.shouldCreateRequest(toSyncObject: client, forKeys: Set(arrayLiteral: ZMUserClientMissingKey), withSync: sut.modifiedSync)
        
        // then
        XCTAssertFalse(shouldCreateRequest)
        XCTAssertFalse(client.keysThatHaveLocalModifications.contains(ZMUserClientMissingKey))
        
    }
    
    func testThatItDoesNotResetKeyForMissingClientIfThereIsAMissingClient(){
        // given
        let client = self.createSelfClient()
        client.missesClient(UserClient.insertNewObject(in: self.syncMOC))
        client.setLocallyModifiedKeys(Set(arrayLiteral: ZMUserClientMissingKey))
        XCTAssertTrue(client.keysThatHaveLocalModifications.contains(ZMUserClientMissingKey))
        
        // when
        let shouldCreateRequest = sut.shouldCreateRequest(toSyncObject: client, forKeys: Set(arrayLiteral: ZMUserClientMissingKey), withSync: sut.modifiedSync)
        
        // then
        XCTAssertTrue(shouldCreateRequest)
        XCTAssertTrue(client.keysThatHaveLocalModifications.contains(ZMUserClientMissingKey))
        
    }
}

