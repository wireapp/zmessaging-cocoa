
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
@testable import WireSyncEngine
import WireUtilities
import WireTesting
import WireMockTransport
import WireDataModel

typealias PostLoginAuthenticationHandler = (_ event : WireSyncEngine.PostLoginAuthenticationEvent, _ accountId: UUID) -> Void

extension PostLoginAuthenticationObserver {
    
    func addObserver(context : NSManagedObjectContext, handler: @escaping PostLoginAuthenticationHandler) -> Any {
        return PostLoginAuthenticationObserverToken(managedObjectContext: context, handler: handler)
    }
    
}

@objcMembers
class PostLoginAuthenticationObserverToken : NSObject, PostLoginAuthenticationObserver {
    
    var token : Any?
    var handler : PostLoginAuthenticationHandler
    
    convenience init(managedObjectContext: NSManagedObjectContext, handler: @escaping PostLoginAuthenticationHandler) {
        self.init(managedObjectContext: managedObjectContext, groupQueue: managedObjectContext, handler: handler)
    }
    
    init(managedObjectContext: NSManagedObjectContext?, groupQueue: ZMSGroupQueue, handler: @escaping PostLoginAuthenticationHandler) {
        self.handler = handler
        super.init()
        if let managedObjectContext = managedObjectContext {
            self.token = PostLoginAuthenticationNotification.addObserver(self, context: managedObjectContext)
        } else {
            self.token = PostLoginAuthenticationNotification.addObserver(self, queue: groupQueue)
        }
        
    }
    
    func authenticationInvalidated(_ error: NSError, accountId: UUID) {
        handler(.authenticationInvalidated(error: error), accountId)
    }
    
    func clientRegistrationDidSucceed(accountId: UUID) {
        handler(.clientRegistrationDidSucceed, accountId)
    }
    
    func clientRegistrationDidFail(_ error: NSError, accountId: UUID) {
        handler(.clientRegistrationDidFail(error: error), accountId)
    }
    
    func accountDeleted(accountId: UUID) {
        handler(.accountDeleted, accountId)
    }
    
}

@objc
public enum PostLoginAuthenticationEventObjC : Int {
    case authenticationInvalidated
    case clientRegistrationDidSucceed
    case clientRegistrationDidFail
    case accountDeleted
}

public typealias PostLoginAuthenticationObjCHandler = (_ event : PostLoginAuthenticationEventObjC, _ accountId: UUID, _ error: NSError?) -> Void

@objcMembers
public class PostLoginAuthenticationObserverObjCToken : NSObject {
    
    var token : Any?
    
    convenience init(managedObjectContext: NSManagedObjectContext, handler: @escaping PostLoginAuthenticationObjCHandler) {
        self.init(managedObjectContext: managedObjectContext, groupQueue: managedObjectContext, handler: handler)
    }
    
    public convenience init(dispatchGroup: ZMSDispatchGroup, handler: @escaping PostLoginAuthenticationObjCHandler) {
        let queue = DispatchGroupQueue(queue: .main)
        queue.add(dispatchGroup)
        self.init(managedObjectContext: nil, groupQueue: queue, handler: handler)
    }
    
    init(managedObjectContext: NSManagedObjectContext?, groupQueue: ZMSGroupQueue, handler: @escaping PostLoginAuthenticationObjCHandler) {
        self.token = PostLoginAuthenticationObserverToken(
            managedObjectContext: managedObjectContext,
            groupQueue: groupQueue,
            handler: { (event, accountId) in
            switch event {
            case .clientRegistrationDidSucceed:
                handler(.clientRegistrationDidSucceed, accountId, nil)
            case .clientRegistrationDidFail(error: let error):
                handler(.clientRegistrationDidFail, accountId, error)
            case .authenticationInvalidated(error: let error):
                handler(.authenticationInvalidated, accountId, error)
            case .accountDeleted:
                handler(.accountDeleted, accountId, nil)
            }
        })
    }
}

@objcMembers
public class PostLoginAuthenticationNotificationEvent : NSObject {
    
    let event : PostLoginAuthenticationEventObjC
    let accountId : UUID
    var error : NSError?
    
    init(event : PostLoginAuthenticationEventObjC, accountId : UUID, error : NSError?) {
        self.event = event
        self.accountId = accountId
        self.error = error
    }
    
}

@objcMembers
public class PostLoginAuthenticationNotificationRecorder : NSObject {
    
    private var token : Any?
    public var notifications : [PostLoginAuthenticationNotificationEvent] = []
    
    init(managedObjectContext: NSManagedObjectContext) {
        super.init()
        
        token = PostLoginAuthenticationObserverObjCToken(managedObjectContext: managedObjectContext) { [weak self] (event, accountId, error) in
            self?.notifications.append(PostLoginAuthenticationNotificationEvent(event: event, accountId: accountId, error: error))
        }
    }
    
    public init(dispatchGroup: ZMSDispatchGroup) {
        super.init()
        let queue = DispatchGroupQueue(queue: .main)
        queue.add(dispatchGroup)
        token = PostLoginAuthenticationObserverObjCToken(managedObjectContext: nil, groupQueue: queue) { [weak self] (event, accountId, error) in
            self?.notifications.append(PostLoginAuthenticationNotificationEvent(event: event, accountId: accountId, error: error))
        }
    }
    
}

class UserClientRequestStrategyTests: RequestStrategyTestBase, PostLoginAuthenticationObserver {
    
    var sut: UserClientRequestStrategy!
    var clientRegistrationStatus: ZMMockClientRegistrationStatus!
    var authenticationStatus: MockAuthenticationStatus!
    var clientUpdateStatus: ZMMockClientUpdateStatus!
    let fakeCredentialsProvider = FakeCredentialProvider()
    
    var cookieStorage : ZMPersistentCookieStorage!
    
    var spyKeyStore: SpyUserClientKeyStore!
    
    var postLoginAuthenticationObserverToken : Any?
    
    var receivedAuthenticationEvents : [WireSyncEngine.PostLoginAuthenticationEvent] = []
    
    override func setUp() {
        super.setUp()
        self.syncMOC.performGroupedBlockAndWait {
            self.spyKeyStore = SpyUserClientKeyStore(accountDirectory: self.accountDirectory, applicationContainer: self.sharedContainerURL)
            self.cookieStorage = ZMPersistentCookieStorage(forServerName: "myServer", userIdentifier: self.userIdentifier)

            self.clientRegistrationStatus = ZMMockClientRegistrationStatus(managedObjectContext: self.syncMOC, cookieStorage: self.cookieStorage, registrationStatusDelegate: nil)
            self.clientUpdateStatus = ZMMockClientUpdateStatus(syncManagedObjectContext: self.syncMOC)
            self.sut = UserClientRequestStrategy(clientRegistrationStatus: self.clientRegistrationStatus, clientUpdateStatus:self.clientUpdateStatus, context: self.syncMOC, userKeysStore: self.spyKeyStore)
            let selfUser = ZMUser.selfUser(in: self.syncMOC)
            selfUser.remoteIdentifier = self.userIdentifier
            self.postLoginAuthenticationObserverToken = PostLoginAuthenticationObserverToken(managedObjectContext: self.uiMOC, handler: { [weak self] (event, _) in
                self?.receivedAuthenticationEvents.append(event)
            })
            self.syncMOC.saveOrRollback()
        }
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: spyKeyStore.cryptoboxDirectory)
        
        self.clientRegistrationStatus.tearDown()
        self.clientRegistrationStatus = nil
        self.clientUpdateStatus = nil
        self.spyKeyStore = nil
        self.sut.tearDown()
        self.sut = nil
        self.receivedAuthenticationEvents = []
        self.postLoginAuthenticationObserverToken = nil
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
        syncMOC.performGroupedBlockAndWait {
            
            // given
            let client = self.createSelfClient(self.sut.managedObjectContext!)
            self.sut.notifyChangeTrackers(client)
            self.clientRegistrationStatus.mockPhase = .unregistered
            
            // when
            self.clientRegistrationStatus.prepareForClientRegistration()
            
            let request = self.sut.nextRequest()
            
            // then
            let expectedRequest = try! self.sut.requestsFactory.registerClientRequest(client, credentials: self.fakeCredentialsProvider.emailCredentials(), cookieLabel: "mycookie").transportRequest!
            
            AssertOptionalNotNil(request, "Should return request if there is inserted UserClient object") { request in
                XCTAssertNotNil(request.payload, "Request should contain payload")
                XCTAssertEqual(request.method, expectedRequest.method,"")
                XCTAssertEqual(request.path, expectedRequest.path, "")
            }
        }
    }
    
    func testThatItDoesNotReturnRequestIfThereIsNoInsertedObject() {
        syncMOC.performGroupedBlockAndWait {
            
            // given
            let client = self.createSelfClient(self.sut.managedObjectContext!)
            self.sut.notifyChangeTrackers(client)
            
            // when
            self.clientRegistrationStatus.prepareForClientRegistration()
            
            let _ = self.sut.nextRequest()
            let nextRequest = self.sut.nextRequest()
            
            // then
            XCTAssertNil(nextRequest, "Should return request only if UserClient object inserted")
        }
    }
    
    
    func testThatItStoresTheRemoteIdentifierWhenUpdatingAnInsertedObject() {
        
        syncMOC.performGroupedBlockAndWait {
            // given
            let client = self.createSelfClient(self.sut.managedObjectContext!)
            self.sut.managedObjectContext!.saveOrRollback()
            
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
    }
    
    func testThatItStoresTheLastGeneratedPreKeyIDWhenUpdatingAnInsertedObject() {
        
        var client: UserClient! = nil
        var maxID_before: UInt16! = nil
        
        syncMOC.performGroupedBlock {
            // given
            self.clientRegistrationStatus.mockPhase = .unregistered
            
            client = self.createSelfClient(self.sut.managedObjectContext!)
            maxID_before = UInt16(client.preKeysRangeMax)
            XCTAssertEqual(maxID_before, 0)
            
            self.sut.notifyChangeTrackers(client)
            guard let request = self.sut.nextRequest() else { return XCTFail() }
            let response = ZMTransportResponse(payload: ["id": "fakeRemoteID"] as ZMTransportData, httpStatus: 200, transportSessionError: nil)
            
            // when
            request.complete(with: response)
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        
        syncMOC.performGroupedBlockAndWait {
            // then
            let maxID_after = UInt16(client.preKeysRangeMax)
            let expectedMaxID = self.spyKeyStore.lastGeneratedKeys.last?.id
            
            XCTAssertNotEqual(maxID_after, maxID_before)
            XCTAssertEqual(maxID_after, expectedMaxID)
        }
    }
    
    func testThatItStoresTheSignalingKeysWhenUpdatingAnInsertedObject() {
        
        var client: UserClient! = nil
        syncMOC.performGroupedBlock {
            // given
            self.clientRegistrationStatus.mockPhase = .unregistered
            
            client = self.createSelfClient(self.syncMOC)
            XCTAssertNil(client.apsDecryptionKey)
            XCTAssertNil(client.apsVerificationKey)
            
            self.sut.notifyChangeTrackers(client)
            guard let request = self.sut.nextRequest() else { return XCTFail() }
            let response = ZMTransportResponse(payload: ["id": "fakeRemoteID"] as ZMTransportData, httpStatus: 200, transportSessionError: nil)
            
            // when
            request.complete(with: response)
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        
        syncMOC.performGroupedBlockAndWait {
            // then
            XCTAssertNotNil(client.apsDecryptionKey)
            XCTAssertNotNil(client.apsVerificationKey)
        }
    }
    
    func testThatItNotifiesObserversWhenUpdatingAnInsertedObject() {
        
        syncMOC.performGroupedBlock {
            // given
            self.clientRegistrationStatus.mockPhase = .unregistered
            
            let client = self.createSelfClient(self.syncMOC)
            self.sut.notifyChangeTrackers(client)
            
            guard let request = self.sut.nextRequest() else { return XCTFail() }
            let response = ZMTransportResponse(payload: ["id": "fakeRemoteID"] as ZMTransportData, httpStatus: 200, transportSessionError: nil)
            
            // when
            request.complete(with: response)
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.2))

        syncMOC.performGroupedBlockAndWait {
            // then
            XCTAssertEqual(self.receivedAuthenticationEvents.count, 1, "should only receive one notification")
            guard let event = self.receivedAuthenticationEvents.first else { return XCTFail() }
            guard case WireSyncEngine.PostLoginAuthenticationEvent.clientRegistrationDidSucceed = event else {
                return XCTFail()
            }
        }
    }
    
    
    func testThatItProcessFailedInsertResponseWithAuthenticationError_NoEmail() {
        
        syncMOC.performGroupedBlock {
            // given
            self.clientRegistrationStatus.mockPhase = .unregistered
            
            let client = self.createSelfClient(self.syncMOC)
            self.sut.notifyChangeTrackers(client)
            
            guard let request = self.sut.nextRequest() else { return XCTFail() }
            let responsePayload = ["code": 403, "message": "Re-authentication via password required", "label": "missing-auth"] as [String : Any]
            let response = ZMTransportResponse(payload: responsePayload as ZMTransportData, httpStatus: 403, transportSessionError: nil)
            
            // when
            request.complete(with: response)
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        
        syncMOC.performGroupedBlockAndWait {
            // then
            let expectedError = NSError(domain: NSError.ZMUserSessionErrorDomain, code: Int(ZMUserSessionErrorCode.invalidCredentials.rawValue), userInfo: nil)
            XCTAssertEqual(self.receivedAuthenticationEvents.count, 1, "should only receive one notification")
            guard let event = self.receivedAuthenticationEvents.first else { return XCTFail() }
            
            
            if case WireSyncEngine.PostLoginAuthenticationEvent.clientRegistrationDidFail(error:  let error) = event {
                XCTAssertEqual(error, expectedError)
            } else {
                XCTFail()
            }
        }
    }
    
    
    func testThatItProcessFailedInsertResponseWithAuthenticationError_HasEmail() {
        
        let emailAddress = "hello@example.com"
        
        syncMOC.performGroupedBlock {
            // given
            self.clientRegistrationStatus.mockPhase = .unregistered
            
            let selfUser = ZMUser.selfUser(in: self.syncMOC)
            selfUser.setValue(emailAddress, forKey: #keyPath(ZMUser.emailAddress))
            
            let client = self.createSelfClient(self.syncMOC)
            self.sut.notifyChangeTrackers(client)
            
            guard let request = self.sut.nextRequest() else { return XCTFail() }
            let responsePayload = ["code": 403, "message": "Re-authentication via password required", "label": "missing-auth"] as [String : Any]
            let response = ZMTransportResponse(payload: responsePayload as ZMTransportData, httpStatus: 403, transportSessionError: nil)
            
            // when
            request.complete(with: response)
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        
        syncMOC.performGroupedBlockAndWait {
            // then
            let expectedError = NSError(domain: NSError.ZMUserSessionErrorDomain, code: Int(ZMUserSessionErrorCode.needsPasswordToRegisterClient.rawValue), userInfo: [
                ZMEmailCredentialKey: emailAddress,
                ZMUserHasPasswordKey: true,
                ZMUserUsesCompanyLoginCredentialKey: false,
                ZMUserLoginCredentialsKey: LoginCredentials(emailAddress: emailAddress, phoneNumber: nil, hasPassword: true, usesCompanyLogin: false)
            ])

            XCTAssertEqual(self.receivedAuthenticationEvents.count, 1, "should only receive one notification")
            guard let event = self.receivedAuthenticationEvents.first else { return XCTFail() }
            
            if case WireSyncEngine.PostLoginAuthenticationEvent.clientRegistrationDidFail(error:  let error) = event {
                XCTAssertEqual(error, expectedError)
            } else {
                XCTFail()
            }
        }
    }
    
    
    func testThatItProcessFailedInsertResponseWithTooManyClientsError() {
        
        syncMOC.performGroupedBlock {
            // given
            self.cookieStorage.authenticationCookieData = Data()
            self.clientRegistrationStatus.mockPhase = .unregistered
            
            let client = self.createSelfClient(self.syncMOC)
            self.sut.notifyChangeTrackers(client)
            let selfUser = ZMUser.selfUser(in: self.syncMOC)
            selfUser.remoteIdentifier = UUID.create()
            
            
            guard let request = self.sut.nextRequest() else {
                XCTFail()
                return
            }
            let responsePayload = ["code": 403, "message": "Too many clients", "label": "too-many-clients"] as [String : Any]
            let response = ZMTransportResponse(payload: responsePayload as ZMTransportData?, httpStatus: 403, transportSessionError: nil)
            
            
            _ = NSError(domain: NSError.ZMUserSessionErrorDomain, code: Int(ZMUserSessionErrorCode.canNotRegisterMoreClients.rawValue), userInfo: nil)
            
            // when
            self.clientRegistrationStatus.mockPhase = nil
            request.complete(with: response)
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        
        syncMOC.performGroupedBlockAndWait {
            // then
            XCTAssertEqual(self.clientRegistrationStatus.currentPhase,ZMClientRegistrationPhase.fetchingClients)
        }
    }
    
}



// MARK: Updating
extension UserClientRequestStrategyTests {
    
    func testThatItReturnsRequestIfNumberOfRemainingKeysIsLessThanMinimum() {
        
        syncMOC.performGroupedBlockAndWait {
            // given
            self.clientRegistrationStatus.mockPhase = .registered
            
            let client = UserClient.insertNewObject(in: self.sut.managedObjectContext!)
            client.remoteIdentifier = UUID.create().transportString()
            self.sut.managedObjectContext!.saveOrRollback()
            
            client.numberOfKeysRemaining = Int32(self.sut.minNumberOfRemainingKeys - 1)
            client.setLocallyModifiedKeys(Set(arrayLiteral: ZMUserClientNumberOfKeysRemainingKey))
            self.sut.notifyChangeTrackers(client)
            
            // when
            guard let request = self.sut.nextRequest() else {
                XCTFail()
                return
            }
            
            // then
            let expectedRequest = try! self.sut.requestsFactory.updateClientPreKeysRequest(client).transportRequest
            
            AssertOptionalNotNil(request, "Should return request if there is inserted UserClient object") { request in
                XCTAssertNotNil(request.payload, "Request should contain payload")
                XCTAssertEqual(request.method, expectedRequest?.method)
                XCTAssertEqual(request.path, expectedRequest?.path)
            }
        }
    }
    
    func testThatItDoesNotReturnsRequestIfNumberOfRemainingKeysIsLessThanMinimum_NoRemoteIdentifier() {
        syncMOC.performGroupedBlockAndWait {
            
            // given
            self.clientRegistrationStatus.mockPhase = .registered
            
            let client = UserClient.insertNewObject(in: self.sut.managedObjectContext!)
            
            // when
            client.remoteIdentifier = nil
            self.sut.managedObjectContext!.saveOrRollback()
            
            client.numberOfKeysRemaining = Int32(self.sut.minNumberOfRemainingKeys - 1)
            client.setLocallyModifiedKeys(Set(arrayLiteral: ZMUserClientNumberOfKeysRemainingKey))
            self.sut.notifyChangeTrackers(client)
            
            // then
            XCTAssertNil(self.sut.nextRequest())
        }
    }
    
    func testThatItDoesNotReturnRequestIfNumberOfRemainingKeysIsAboveMinimum() {
        syncMOC.performGroupedBlockAndWait {
            
            // given
            let client = UserClient.insertNewObject(in: self.sut.managedObjectContext!)
            client.remoteIdentifier = UUID.create().transportString()
            self.sut.managedObjectContext!.saveOrRollback()
            
            client.numberOfKeysRemaining = Int32(self.sut.minNumberOfRemainingKeys)
            
            client.setLocallyModifiedKeys(Set(arrayLiteral: ZMUserClientNumberOfKeysRemainingKey))
            self.sut.notifyChangeTrackers(client)
            
            // when
            let request = self.sut.nextRequest()
            
            // then
            XCTAssertNil(request, "Should not return request if there are enouth keys left")
        }
    }
    
    func testThatItResetsNumberOfRemainingKeysAfterNewKeysUploaded() {
        syncMOC.performGroupedBlockAndWait {
            // given
            let client = UserClient.insertNewObject(in: self.sut.managedObjectContext!)
            client.remoteIdentifier = UUID.create().transportString()
            self.sut.managedObjectContext!.saveOrRollback()
            
            client.numberOfKeysRemaining = Int32(self.sut.minNumberOfRemainingKeys - 1)
            let expectedNumberOfKeys = client.numberOfKeysRemaining + Int32(self.sut.requestsFactory.keyCount)
            
            // when
            let response = ZMTransportResponse(payload: nil, httpStatus: 200, transportSessionError: nil)
            let _ = self.sut.updateUpdatedObject(client, requestUserInfo: nil, response: response, keysToParse: Set(arrayLiteral: ZMUserClientNumberOfKeysRemainingKey))
            
            // then
            XCTAssertEqual(client.numberOfKeysRemaining, expectedNumberOfKeys)
        }
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
        
        syncMOC.performGroupedBlockAndWait {
            // given
            let nextResponse = ZMTransportResponse(payload: self.payloadForClients() as ZMTransportData?, httpStatus: 200, transportSessionError: nil)
            
            // when
            _ = self.sut.nextRequest()
            self.sut.didReceive(nextResponse, forSingleRequest: self.sut.fetchAllClientsSync)
            
            // then
            AssertOptionalNotNil(self.clientUpdateStatus.fetchedClients, "userinfo should contain clientIDs") { clients in
                XCTAssertEqual(self.clientUpdateStatus.fetchedClients.count, 2)
                for client in self.clientUpdateStatus.fetchedClients {
                    XCTAssertEqual(client?.label!, "client")
                }
            }
        }
    }
    
    func testThatDeletesClientsThatWereNotInTheFetchResponse() {
        
        var selfUser: ZMUser!
        var selfClient: UserClient!
        var newClient: UserClient!
        
        syncMOC.performGroupedBlockAndWait {
            // given
            selfClient = self.createSelfClient()
            selfUser = ZMUser.selfUser(in: self.syncMOC)
            let nextResponse = ZMTransportResponse(payload: self.payloadForClients() as ZMTransportData?, httpStatus: 200, transportSessionError: nil)
            newClient = UserClient.insertNewObject(in: self.syncMOC)
            newClient.user = selfUser
            newClient.remoteIdentifier = "deleteme"
            self.syncMOC.saveOrRollback()
            
            // when
            _ = self.sut.nextRequest()
            self.sut.didReceive(nextResponse, forSingleRequest: self.sut.fetchAllClientsSync)
        }
        
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        
        // then
        syncMOC.performGroupedBlockAndWait {
            XCTAssertTrue(selfUser.clients.contains(selfClient))
            XCTAssertFalse(selfUser.clients.contains(newClient))
        }
    }
}


// MARK: Deleting
extension UserClientRequestStrategyTests {
    
    func testThatItCreatesARequestToDeleteAClient_UpdateStatus() {
        
        syncMOC.performGroupedBlockAndWait {
            // given
            self.clientRegistrationStatus.mockPhase = .unregistered
            self.clientUpdateStatus.mockPhase = .deletingClients
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
            self.sut.notifyChangeTrackers(clients[0])
            
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
    }
    
    func testThatItDeletesAClientOnSuccess() {
        
        // given
        var client : UserClient!
        
        self.syncMOC.performGroupedBlock {
            client =  UserClient.insertNewObject(in: self.syncMOC)
            client.remoteIdentifier = "\(client.objectID)"
            client.user = ZMUser.selfUser(in: self.syncMOC)
            self.syncMOC.saveOrRollback()
            
            let response = ZMTransportResponse(payload: [:] as ZMTransportData, httpStatus: 200, transportSessionError: nil)
            
            // when
            let _ = self.sut.updateUpdatedObject(client, requestUserInfo:nil, response: response, keysToParse:Set(arrayLiteral: ZMUserClientMarkedToDeleteKey))
        }
        
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        self.syncMOC.performGroupedBlockAndWait {
            XCTAssertTrue(client.isZombieObject)
        }
    }
}



// MARK: - Updating from push events
extension UserClientRequestStrategyTests {
    
    static func payloadForAddingClient(_ clientId : String,
        label : String = "device label",
        time : Date = Date(timeIntervalSince1970: 12345)
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
        let clientId = "94766bd92f56923d"
        let clientLabel = "iPhone 23sd Plus Air Pro C"
        let clientTime = Date(timeIntervalSince1970: 1234555)
        var selfUser: ZMUser! = nil
        var selfClient: UserClient! = nil
        
        syncMOC.performGroupedBlock {
            selfUser = ZMUser.selfUser(in: self.syncMOC)
            selfClient = self.createSelfClient()
            _ = self.createRemoteClient()
            XCTAssertEqual(selfUser.clients.count, 1)
        }
        
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        
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
        syncMOC.performGroupedBlockAndWait {
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
    }
    
    func testThatItAddsASelfUserClientWhenDownloadingAClientEvent() {
        
        // given
        let clientId = "94766bd92f56923d"
        var selfUser: ZMUser! = nil
        syncMOC.performGroupedBlockAndWait {
            selfUser = ZMUser.selfUser(in: self.syncMOC)
            XCTAssertEqual(selfUser.clients.count, 0)
        }
        
        let payload = UserClientRequestStrategyTests.payloadForAddingClient(clientId)
        let event = ZMUpdateEvent(fromEventStreamPayload: payload, uuid: nil)!
        
        // when
        self.syncMOC.performGroupedBlock {
            self.sut.processEvents([event], liveEvents:false, prefetchResult: .none)
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        self.syncMOC.performGroupedBlockAndWait {
            XCTAssertEqual(selfUser.clients.count, 1)
            guard let newClient = selfUser.clients.first else {
                XCTFail()
                return
            }
            XCTAssertEqual(newClient.remoteIdentifier, clientId)
        }
            
    }
    
    func testThatItDoesNotAddASelfUserClientWhenReceivingAPushIfTheClientExistsAlready() {
        
        // given
        var selfUser: ZMUser! = nil
        var existingClient: UserClient! = nil
        syncMOC.performGroupedBlockAndWait {
            selfUser = ZMUser.selfUser(in: self.syncMOC)
            existingClient = self.createSelfClient()
            XCTAssertEqual(selfUser.clients.count, 1)
        }
        
        // when
        syncMOC.performGroupedBlockAndWait {
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
            
            self.sut.processEvents([event], liveEvents:true, prefetchResult: .none)
        }
        
        // then
        syncMOC.performGroupedBlockAndWait {
            XCTAssertEqual(selfUser.clients.count, 1)
            guard let newClient = selfUser.clients.first else {
                XCTFail()
                return
            }
            XCTAssertEqual(newClient, existingClient)
        }
    }
    
    func testThatItDeletesASelfClientWhenReceivingAPush() {
        
        syncMOC.performGroupedBlockAndWait {
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
    }
    
    func testThatItInvalidatesTheCurrentSelfClientAndWipeCryptoBoxWhenReceivingAPush() {
        
        syncMOC.performGroupedBlockAndWait {
            // given
            let selfUser = ZMUser.selfUser(in: self.syncMOC)
            let existingClient = self.createSelfClient()
            
            var fingerprint : Data?
            self.syncMOC.zm_cryptKeyStore.encryptionContext.perform { (sessionsDirectory) in
                fingerprint = sessionsDirectory.localFingerprint
            }
            let previousLastPrekey = try? self.syncMOC.zm_cryptKeyStore.lastPreKey()
            
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
            self.syncMOC.zm_cryptKeyStore.encryptionContext.perform { (sessionsDirectory) in
                newFingerprint = sessionsDirectory.localFingerprint
            }
            let newLastPrekey = try? self.syncMOC.zm_cryptKeyStore.lastPreKey()
            
            XCTAssertNotNil(fingerprint)
            XCTAssertNotNil(newFingerprint)
            XCTAssertNotEqual(fingerprint, newFingerprint)
            XCTAssertNil(selfUser.clients.first?.remoteIdentifier)
            XCTAssertNil(self.syncMOC.persistentStoreMetadata(forKey: ZMPersistedClientIdKey))
            XCTAssertNotNil(fingerprint)
            XCTAssertNotNil(newFingerprint)
            XCTAssertNotEqual(previousLastPrekey, newLastPrekey)
        }
    }
    
    func testThatItCreatesARequestForClientsThatNeedToUploadSignalingKeys() {
        
        var existingClient: UserClient! = nil
        syncMOC.performGroupedBlock {
            // given
            self.clientRegistrationStatus.mockPhase = .registered
            
            existingClient = self.createSelfClient()
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
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        syncMOC.performGroupedBlock {
            XCTAssertNotNil(existingClient.apsVerificationKey)
            XCTAssertNotNil(existingClient.apsDecryptionKey)
            XCTAssertFalse(existingClient.needsToUploadSignalingKeys)
            XCTAssertFalse(existingClient.hasLocalModifications(forKey: ZMUserClientNeedsToUpdateSignalingKeysKey))
        }
    }
    
    func testThatItRetriesOnceWhenUploadSignalingKeysFails() {
        
        syncMOC.performGroupedBlock {
            // given
            self.clientRegistrationStatus.mockPhase = .registered
            
            let existingClient = self.createSelfClient()
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
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        
        // and when
        syncMOC.performGroupedBlock {
            let secondRequest = self.sut.nextRequest()
            XCTAssertNotNil(secondRequest)
            let success = ZMTransportResponse(payload: nil, httpStatus: 200, transportSessionError: nil)
            
            secondRequest?.complete(with: success)
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        
        // and when
        syncMOC.performGroupedBlock {
            let thirdRequest = self.sut.nextRequest()
            XCTAssertNil(thirdRequest)
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.2))
    }


}

extension UserClientRequestStrategy {
    
    func notifyChangeTrackers(_ object: ZMManagedObject) {
        self.contextChangeTrackers.forEach { $0.objectsDidChange(Set([object])) }
    }
}
