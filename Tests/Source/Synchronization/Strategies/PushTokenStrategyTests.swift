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

@testable import WireSyncEngine
import WireRequestStrategy
import WireTesting


class PushTokenStrategyTests: MessagingTest {

    var sut : PushTokenStrategy!
    var mockApplicationStatus : MockApplicationStatus!
    let deviceToken = Data(base64Encoded: "xeJOQeTUMpA3koRJNJSHVH7xTxYsd67jqo4So5yNsdU=")!
    var deviceTokenString: String {
        return deviceToken.zmHexEncodedString()
    }

    let deviceTokenB = Data(base64Encoded: "DBFjMBFIXEVYYVAJBFsCLVZeDDgKUzBETToPSxhaAUo=")!
    var deviceTokenBString : String {
        return deviceTokenB.zmHexEncodedString()
    }

    let identifier = "com.wire.zclient"
    let transportTypeNormal = "APNS"
    let transportTypeVOIP = "APNS_VOIP"
    
    override func setUp() {
        super.setUp()
        mockApplicationStatus = MockApplicationStatus()
        mockApplicationStatus.mockSynchronizationState = .eventProcessing
        sut = PushTokenStrategy(withManagedObjectContext: uiMOC, applicationStatus: mockApplicationStatus)
        createSelfClient()
    }
    
    override func tearDown() {
        sut = nil
        super.tearDown()
    }
    
    func insertPushKitToken(isRegistered: Bool, shouldBeDeleted: Bool = false) {
        let client = ZMUser.selfUser(in: self.uiMOC).selfClient()
        var token = PushToken(deviceToken: deviceTokenB, appIdentifier: identifier, transportType: transportTypeVOIP, isRegistered: isRegistered)
        token.isMarkedForDeletion = shouldBeDeleted
        client?.pushToken = token
        try! uiMOC.save()
        client?.modifiedKeys = ["pushToken"]
        notifyChangeTrackers()
    }

    func notifyChangeTrackers() {
        let client = ZMUser.selfUser(in: self.uiMOC).selfClient()
        sut.contextChangeTrackers.forEach{$0.objectsDidChange([client!])}
    }

    func clearPushKitToken() {
        let client = ZMUser.selfUser(in: self.uiMOC).selfClient()
        client?.pushToken = nil
        try! uiMOC.save()
    }

    func pushKitToken() -> PushToken? {
        let client = ZMUser.selfUser(in: self.uiMOC).selfClient()
        return client?.pushToken
    }
    
    func fakeResponse(transport: String, fallback: String? = nil) -> ZMTransportResponse {
        var responsePayload = ["token": deviceTokenBString,
                               "app": identifier,
                               "transport": transport]
        if let fallback = fallback {
            responsePayload["fallback"] = fallback
        }
        return ZMTransportResponse(payload:responsePayload as ZMTransportData?, httpStatus:201, transportSessionError:nil, headers:[:])
    }
}

extension PushTokenStrategyTests {
    
    func testThatItDoesNotReturnARequestWhenThereIsNoPushToken() {
        // given
        clearPushKitToken()
        
        // when
        let req = sut.nextRequest()
        
        // then
        XCTAssertNil(req)
    }

    func testThatItReturnsNoRequestIfTheClientIsNotRegistered() {
        // given
        mockApplicationStatus.mockSynchronizationState = .unauthenticated
        insertPushKitToken(isRegistered: false)
        sut.contextChangeTrackers.forEach{$0.objectsDidChange(Set())}
        
        // when
        let req = sut.nextRequest()
        
        // then
        XCTAssertNil(req)
    }
}


// MARK: Reregistering
extension PushTokenStrategyTests {
    
    func testThatItNilsTheTokenWhenReceivingAPushRemoveEvent() {
        // given
        insertPushKitToken(isRegistered: true)
        
        let payload = ["type": "user.push-remove",
                       "token" : deviceTokenBString]
        let event = ZMUpdateEvent(fromEventStreamPayload: payload as ZMTransportData, uuid: nil)!
        
        // when
        syncMOC.performGroupedBlockAndWait {
            self.sut.processEvents([event], liveEvents: true, prefetchResult: nil)
            try! self.syncMOC.save()
        }
        
        // then
        XCTAssertNil(pushKitToken())
    }

}

// MARK: - PushKit
extension PushTokenStrategyTests {
    
    func testThatItReturnsARequestWhenThePushKitTokenIsNotRegistered() throws {
        // given
        insertPushKitToken(isRegistered: false)

        // when
        let req = sut.nextRequest()
        
        // then
        guard let request = req else { return XCTFail() }
        guard let payloadString = request.payload as? String else { return XCTFail() }

        let expectedPayload = ["token": "0c11633011485c4558615009045b022d565e0c380a5330444d3a0f4b185a014a",
                               "app": "com.wire.zclient",
                               "transport": "APNS_VOIP",
                               "client" : (ZMUser.selfUser(in: self.uiMOC).selfClient()?.remoteIdentifier)!]

        let payloadDictionary = try! JSONDecoder().decode([String:String].self, from: payloadString.data(using: .utf8)!)
        
        XCTAssertEqual(request.method, .methodPOST)
        XCTAssertEqual(request.path, "/push/tokens")
        XCTAssertEqual(payloadDictionary, expectedPayload)
    }

    func testThatItMarksThePushKitTokenAsRegisteredWhenTheRequestCompletes() {
        // given
        insertPushKitToken(isRegistered: false)

        let response = fakeResponse(transport: transportTypeVOIP)
        
        // when
        let request = sut.nextRequest()
        request?.complete(with:response)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        guard let token = pushKitToken() else { XCTFail("Push token should not be nil"); return }
        XCTAssertTrue(token.isRegistered)
        XCTAssertEqual(token.appIdentifier, identifier)
        XCTAssertEqual(token.deviceToken, deviceTokenB)
    }
    
    func testThatItDoesNotRegisterThePushKitTokenAgainAfterTheRequestCompletes() {
        // given
        insertPushKitToken(isRegistered: false)
        let response = fakeResponse(transport: transportTypeVOIP, fallback: "APNS")
        
        // when
        let request = sut.nextRequest()
        request?.complete(with:response)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertNotNil(ZMUser.selfUser(in: self.uiMOC).selfClient()?.pushToken)
        notifyChangeTrackers()
        
        // and when
        let request2 = sut.nextRequest()
        XCTAssertNil(request2);
    }
}


// MARK: - Deleting Tokens
extension PushTokenStrategyTests {
    
    func testThatItSyncsTokensThatWereMarkedToDeleteAndDeletesThem() {
        // given
        insertPushKitToken(isRegistered: true, shouldBeDeleted: true)
        sut.contextChangeTrackers.forEach{$0.objectsDidChange(Set())}
        let response = ZMTransportResponse(payload:nil, httpStatus:200, transportSessionError:nil, headers:[:])
        
        // when
        let req = sut.nextRequest()
        
        guard let request = req else { return XCTFail() }
        XCTAssertEqual(request.method, .methodDELETE)
        XCTAssertTrue(request.path.contains("push/tokens"))
        XCTAssertNil(request.payload)
        
        request.complete(with:response)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertNil(pushKitToken())
        notifyChangeTrackers()

        // and when
        let request2 = sut.nextRequest()
        XCTAssertNil(request2);
    }
    
    func testThatItDoesNotDeleteTokensThatAreNotMarkedForDeletion() {
        // given
        insertPushKitToken(isRegistered: true, shouldBeDeleted: true)
        XCTAssertNotNil(pushKitToken())
        let response = ZMTransportResponse(payload:nil, httpStatus:200, transportSessionError:nil, headers:[:])
        
        // when
        let req = sut.nextRequest()
        
        guard let request = req else { return XCTFail() }
        XCTAssertEqual(request.method, .methodDELETE)
        XCTAssertTrue(request.path.contains("push/tokens"))
        XCTAssertNil(request.payload)
        
        // and replacing the token while the request is in progress
        insertPushKitToken(isRegistered: true)
        
        request.complete(with:response)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertNotNil(pushKitToken())
    }
}


