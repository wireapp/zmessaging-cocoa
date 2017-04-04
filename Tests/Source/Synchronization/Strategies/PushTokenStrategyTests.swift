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
    var clientRegistrationDelegate : ZMMockClientRegistrationStatus!
    let deviceTokenString = "c5e24e41e4d4329037928449349487547ef14f162c77aee3aa8e12a39c8db1d5"
    var deviceToken : Data {
        return deviceTokenString.zmDeviceTokenData()
    }

    let deviceTokenBString = "0c11633011485c4558615009045b022d565e0c380a5330444d3a0f4b185a014a"
    var deviceTokenB : Data {
        return deviceTokenBString.zmDeviceTokenData()
    }

    let identifier = "com.wire.zclient"
    let transportTypeNormal = "APNS"
    let transportTypeVOIP = "APNS_VOIP"
    
    override func setUp() {
        super.setUp()
        clientRegistrationDelegate = ZMMockClientRegistrationStatus()
        sut = PushTokenStrategy(managedObjectContext: uiMOC, clientRegistrationDelegate: clientRegistrationDelegate)
    }
    
    override func tearDown() {
        sut = nil
        super.tearDown()
    }
    
    func insertApplicationToken(isRegistered: Bool) {
        uiMOC.pushToken = ZMPushToken(deviceToken:deviceToken, identifier:identifier, transportType:transportTypeNormal, fallback:nil, isRegistered:isRegistered)
        try! uiMOC.save()
    }
    
    func insertPushKitToken(isRegistered: Bool) {
        uiMOC.pushKitToken = ZMPushToken(deviceToken:deviceTokenB, identifier:identifier, transportType:transportTypeVOIP, fallback:"APNS", isRegistered:isRegistered)
        try! uiMOC.save()
    }
    
    func simulateRegisteredPushTokens(){
        insertApplicationToken(isRegistered: true)
        insertPushKitToken(isRegistered: true)
    }
    
    func fakeResponse(transport: String, fallback: String? = nil) -> ZMTransportResponse {
        var responsePayload = ["token": "aabbccddeeff",
                               "app": "foo.bar",
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
        uiMOC.pushToken = nil;
        uiMOC.pushKitToken = nil;
        
        // when
        let req = sut.nextRequest()
        
        // then
        XCTAssertNil(req)
    }
    
    func testThatItDoesNotReturnAFetchRequest(){
        // when
        let req =  sut.fetchRequestForTrackedObjects()
        
        // then
        XCTAssertNil(req)
    }
    
    func testThatItReturnsNoRequestIfTheClientIsNotRegistered() {
        // given
        clientRegistrationDelegate.mockReadiness = false
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
    
    func checkThatItMarksATokenAsNotRegisteredWhenReceivingAPushRemoveEvent(token: String) {
        // given
        simulateRegisteredPushTokens()
        
        let payload = ["type": "user.push-remove",
                       "token" : token]
        let event = ZMUpdateEvent(fromEventStreamPayload: payload as ZMTransportData, uuid: nil)!
        
        // when
        syncMOC.performGroupedBlockAndWait {
            self.sut.processEvents([event], liveEvents: true, prefetchResult: nil)
            try! self.syncMOC.save()
        }
        
        // then
        XCTAssertNotNil(uiMOC.pushToken);
        XCTAssertEqual(uiMOC.pushToken.deviceToken, deviceToken);
        XCTAssertFalse(uiMOC.pushToken.isRegistered);
        
        XCTAssertNotNil(uiMOC.pushKitToken);
        XCTAssertEqual(uiMOC.pushKitToken.deviceToken, deviceTokenB);
        XCTAssertFalse(uiMOC.pushKitToken.isRegistered);
    }
    
    func testThatItMarksATokenAsNotRegisteredWhenReceivingAPushRemoveEvent_ApplicationToken() {
        checkThatItMarksATokenAsNotRegisteredWhenReceivingAPushRemoveEvent(token: deviceTokenString)
    }
    
    func testThatItMarksATokenAsNotRegisteredWhenReceivingAPushRemoveEvent_PushKit() {
        checkThatItMarksATokenAsNotRegisteredWhenReceivingAPushRemoveEvent(token: deviceTokenBString)
    }
    
}


// MARK: ApplicationToken
extension PushTokenStrategyTests {
    
    func testThatItReturnsARequestWhenThePushTokenIsNotRegistered() {
        // given
        insertApplicationToken(isRegistered: false)
        sut.contextChangeTrackers.forEach{$0.objectsDidChange(Set())}
        
        // when
        let req = sut.nextRequest()
        
        // then
        guard let request = req else {return XCTFail()}
        let expectedPayload = ["token": "c5e24e41e4d4329037928449349487547ef14f162c77aee3aa8e12a39c8db1d5",
                               "app": "com.wire.zclient",
                               "transport": "APNS"]
        
        XCTAssertEqual(request.method, .methodPOST)
        XCTAssertEqual(request.path, "/push/tokens")
        XCTAssertEqual(request.payload as! [String : String], expectedPayload)
    }
    
    func testThatItAddsTheClientIDIfTheClientIsSpecified_Application(){
        // given
        let client = setupSelfClient(inMoc: uiMOC)
        insertApplicationToken(isRegistered: false)
        sut.contextChangeTrackers.forEach{$0.objectsDidChange(Set())}
        
        // when
        let req = sut.nextRequest()
        
        // then
        guard let request = req else {return XCTFail()}
        let expectedPayload = ["token": "c5e24e41e4d4329037928449349487547ef14f162c77aee3aa8e12a39c8db1d5",
                               "app": "com.wire.zclient",
                               "transport": "APNS",
                               "client": client.remoteIdentifier!]
        
        XCTAssertEqual(request.method, .methodPOST)
        XCTAssertEqual(request.path, "/push/tokens")
        XCTAssertEqual(request.payload as! [String : String], expectedPayload)
    }
    
    func testThatItMarksThePushTokenAsRegisteredWhenTheRequestCompletes() {
        // given
        _ = setupSelfClient(inMoc: uiMOC)
        insertApplicationToken(isRegistered: false)
        sut.contextChangeTrackers.forEach{$0.objectsDidChange(Set())}

        let response = fakeResponse(transport: transportTypeNormal)
        
        // when
        let request = sut.nextRequest()
        request?.complete(with:response)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertNotNil(uiMOC.pushToken)
        XCTAssertTrue(uiMOC.pushToken.isRegistered)
        XCTAssertEqual(uiMOC.pushToken.appIdentifier, "foo.bar")
        let newDeviceToken = Data(bytes: [0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff])
        XCTAssertEqual(uiMOC.pushToken.deviceToken, newDeviceToken)
    }
    
    func testThatItDoesNotRegisterThePushTokenAgainAfterTheRequestCompletes() {
        
        // given
        _ = setupSelfClient(inMoc: uiMOC)
        insertApplicationToken(isRegistered: false)
        sut.contextChangeTrackers.forEach{$0.objectsDidChange(Set())}
        let response = fakeResponse(transport: transportTypeNormal)
        
        // when
        let request = sut.nextRequest()
        request?.complete(with:response)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertNotNil(uiMOC.pushToken)
        sut.contextChangeTrackers.forEach{$0.objectsDidChange(Set())}
        
        // and when
        let request2 = sut.nextRequest()
        XCTAssertNil(request2);
    }
    
}


// MARK: - PushKit
extension PushTokenStrategyTests {
    
    func testThatItReturnsARequestWhenThePushKitTokenIsNotRegistered() {
        // given
        insertPushKitToken(isRegistered: false)
        sut.contextChangeTrackers.forEach{$0.objectsDidChange(Set())}
        
        // when
        let req = sut.nextRequest()
        
        // then
        guard let request = req else {return XCTFail()}
        let expectedPayload = ["token": "0c11633011485c4558615009045b022d565e0c380a5330444d3a0f4b185a014a",
                               "app": "com.wire.zclient",
                               "transport": "APNS_VOIP",
                               "fallback" : "APNS"]
        
        XCTAssertEqual(request.method, .methodPOST)
        XCTAssertEqual(request.path, "/push/tokens")
        XCTAssertEqual(request.payload as! [String : String], expectedPayload)
    }
    
    func testThatItDoesNotIncludeFallbackInRequestWhenNotSet() {
        // given
        uiMOC.pushKitToken = ZMPushToken(deviceToken:deviceTokenB, identifier:identifier, transportType:transportTypeVOIP, fallback:nil, isRegistered:false)
        try! uiMOC.save()
        sut.contextChangeTrackers.forEach{$0.objectsDidChange(Set())}
        
        // when
        let req = sut.nextRequest()
        
        // then
        guard let request = req else {return XCTFail()}
        let expectedPayload = ["token": "0c11633011485c4558615009045b022d565e0c380a5330444d3a0f4b185a014a",
                               "app": "com.wire.zclient",
                               "transport": "APNS_VOIP"]
        
        XCTAssertEqual(request.method, .methodPOST)
        XCTAssertEqual(request.path, "/push/tokens")
        XCTAssertEqual(request.payload as! [String : String], expectedPayload)
    }
    
    func testThatItAddsTheClientIDIfTheClientIsSpecified_PushKit(){
        // given
        let client = setupSelfClient(inMoc: uiMOC)
        insertPushKitToken(isRegistered: false)
        sut.contextChangeTrackers.forEach{$0.objectsDidChange(Set())}
        
        // when
        let req = sut.nextRequest()
        
        // then
        guard let request = req else {return XCTFail()}
        let expectedPayload = ["token": "0c11633011485c4558615009045b022d565e0c380a5330444d3a0f4b185a014a",
                               "app": "com.wire.zclient",
                               "transport": "APNS_VOIP",
                               "fallback" : "APNS",
                               "client": client.remoteIdentifier!]
        
        XCTAssertEqual(request.method, .methodPOST)
        XCTAssertEqual(request.path, "/push/tokens")
        XCTAssertEqual(request.payload as! [String : String], expectedPayload)
    }
    
    func testThatItMarksThePushKitTokenAsRegisteredWhenTheRequestCompletes() {
        // given
        _ = setupSelfClient(inMoc: uiMOC)
        insertPushKitToken(isRegistered: false)
        sut.contextChangeTrackers.forEach{$0.objectsDidChange(Set())}
        
        let response = fakeResponse(transport: transportTypeVOIP, fallback: "APNS")
        
        // when
        let request = sut.nextRequest()
        request?.complete(with:response)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertNotNil(uiMOC.pushKitToken)
        XCTAssertTrue(uiMOC.pushKitToken.isRegistered)
        XCTAssertEqual(uiMOC.pushKitToken.appIdentifier, "foo.bar")
        let newDeviceToken = Data(bytes: [0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff])
        XCTAssertEqual(uiMOC.pushKitToken.deviceToken, newDeviceToken)
    }
    
    func testThatItDoesNotRegisterThePushKitTokenAgainAfterTheRequestCompletes() {
        // given
        _ = setupSelfClient(inMoc: uiMOC)
        insertPushKitToken(isRegistered: false)
        sut.contextChangeTrackers.forEach{$0.objectsDidChange(Set())}
        let response = fakeResponse(transport: transportTypeVOIP, fallback: "APNS")
        
        // when
        let request = sut.nextRequest()
        request?.complete(with:response)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertNotNil(uiMOC.pushKitToken)
        sut.contextChangeTrackers.forEach{$0.objectsDidChange(Set())}
        
        // and when
        let request2 = sut.nextRequest()
        XCTAssertNil(request2);
    }
}


// MARK: - Deleting Tokens
extension PushTokenStrategyTests {
    
    func insertTokenMarkedForDeletion(transport: String) {
        if transport == transportTypeVOIP {
            uiMOC.pushKitToken = ZMPushToken(deviceToken:deviceToken, identifier:identifier, transportType:transport, fallback:nil, isRegistered:true)
            uiMOC.pushKitToken = uiMOC.pushKitToken.forDeletionMarkedCopy()
        } else {
            uiMOC.pushToken = ZMPushToken(deviceToken:deviceToken, identifier:identifier, transportType:transport, fallback:nil, isRegistered:true)
            uiMOC.pushToken = uiMOC.pushToken.forDeletionMarkedCopy()
        }
        try! uiMOC.save()
    }
    
    func checkThatItSyncsTokensThatWereMarkedToDeleteAndDeletesThem(transport: String) {
        // given
        insertTokenMarkedForDeletion(transport: transport)
        if transport == transportTypeVOIP {
            insertApplicationToken(isRegistered: true)
        } else {
            insertPushKitToken(isRegistered: true)
        }
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
        if transport == transportTypeVOIP {
            XCTAssertNil(uiMOC.pushKitToken)
            XCTAssertNotNil(uiMOC.pushToken)
        } else {
            XCTAssertNil(uiMOC.pushToken)
            XCTAssertNotNil(uiMOC.pushKitToken)
        }
        sut.contextChangeTrackers.forEach{$0.objectsDidChange(Set())}

        // and when
        let request2 = sut.nextRequest()
        XCTAssertNil(request2);
    }
    
    func testThatItSyncsTokensThatWereMarkedToDeleteAndDeletesThem_PushKit() {
        checkThatItSyncsTokensThatWereMarkedToDeleteAndDeletesThem(transport: transportTypeVOIP)
    }
    
    func testThatItSyncsTokensThatWereMarkedToDeleteAndDeletesThem_ApplicationToken() {
        checkThatItSyncsTokensThatWereMarkedToDeleteAndDeletesThem(transport: transportTypeNormal)
    }

    func testThatItDoesNotDeleteTokensThatAreNotMarkedForDeletion() {
        // given
        insertTokenMarkedForDeletion(transport: transportTypeVOIP)
        XCTAssertNotNil(uiMOC.pushKitToken);
        sut.contextChangeTrackers.forEach{$0.objectsDidChange(Set())}
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
        XCTAssertNotNil(uiMOC.pushKitToken);
    }
}


