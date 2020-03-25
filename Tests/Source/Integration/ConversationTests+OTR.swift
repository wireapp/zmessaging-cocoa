//
//  ConversationTests+OTR.swift
//  WireSyncEngine-iOS-Tests
//
//  Created by David Henner on 21.02.20.
//  Copyright © 2020 Zeta Project Gmbh. All rights reserved.
//

import Foundation

class ConversationTestsOTRSwift: ConversationTestsBase {
    func testThatItSendsFailedOTRMessageAfterMisingClientsAreFetchedButSessionIsNotCreated() {
        // GIVEN
        XCTAssertTrue(self.login())
        
        let conv = conversation(for: selfToUser1Conversation)
        
        mockTransportSession.responseGeneratorBlock = { [weak self] request -> ZMTransportResponse? in
            guard let `self` = self,
                let path = (request.path as NSString?),
                path.pathComponents.contains("prekeys") else { return nil }

            let payload: NSDictionary = [
                self.user1.identifier: [
                    (self.user1.clients.anyObject() as? MockUserClient)?.identifier: [
                        "id": 0,
                        "key": "invalid key".data(using: .utf8)!.base64String()
                    ]
                ]
            ]
           return ZMTransportResponse(payload: payload, httpStatus: 201, transportSessionError: nil)
        }
        
        // WHEN
        var message: ZMConversationMessage?
        mockTransportSession.resetReceivedRequests()
        performIgnoringZMLogError {
            self.userSession?.perform {
                message = conv?.append(text: "Hello World")
            }
            _ = self.waitForAllGroupsToBeEmpty(withTimeout: 0.5)
        }
        
        // THEN
        let expectedPath = "/conversations/\(conv!.remoteIdentifier!.transportString())/otr"
        
        // then we expect it to receive a bomb message
        // when resending after fetching the (faulty) prekeys
        var messagesReceived = 0
        for request in mockTransportSession.receivedRequests() {
            guard request.path.hasPrefix(expectedPath), let data = request.binaryData else { continue }
            guard let otrMessage = try? NewOtrMessage(serializedData: data) else { return XCTFail("otrMessage was nil") }
            
            let userEntries = otrMessage.recipients
            let clientEntry = userEntries.first?.clients.first
            if clientEntry?.text == "💣".data(using: .utf8) {
                messagesReceived += 1
            }
        }
        XCTAssertEqual(messagesReceived, 1)
        XCTAssertEqual(message?.deliveryState, ZMDeliveryState.sent)
    }
    
    func testThatItSendsFailedSessionOTRMessageAfterMissingClientsAreFetchedButSessionIsNotCreated() {
        // GIVEN
        XCTAssertTrue(self.login())
        
        let conv = conversation(for: selfToUser1Conversation)
        
        var message: ZMAssetClientMessage?
        
        mockTransportSession.responseGeneratorBlock = { [weak self] request -> ZMTransportResponse? in
            guard let `self` = self,
                let path = request.path as NSString?,
                path.pathComponents.contains("prekeys") else { return nil }
            let payload: NSDictionary = [
                self.user1.identifier: [
                    (self.user1.clients.anyObject() as? MockUserClient)?.identifier: [
                        "id": 0,
                        "key": "invalid key".data(using: .utf8)!.base64String()
                    ]
                ]
            ]
            return ZMTransportResponse(payload: payload, httpStatus: 201, transportSessionError: nil)
        }
        
        // WHEN
        mockTransportSession.resetReceivedRequests()
        performIgnoringZMLogError {
            self.userSession?.perform {
                message = conv?.append(imageFromData: self.verySmallJPEGData(), nonce: NSUUID.create()) as? ZMAssetClientMessage
            }
            _ = self.waitForAllGroupsToBeEmpty(withTimeout: 0.5)
        }
        
        // THEN
        let expectedPath = "/conversations/\(conv!.remoteIdentifier!.transportString())/otr/messages"
        
        // then we expect it to receive a bomb medium
        // when resending after fetching the (faulty) prekeys
        var bombsReceived = 0
        
        for request in mockTransportSession.receivedRequests() {
            guard request.path.hasPrefix(expectedPath), let data = request.binaryData else { continue }
            guard let otrMessage = try? NewOtrMessage(serializedData: data) else { return XCTFail() }
            
            let userEntries = otrMessage.recipients
            let clientEntry = userEntries.first?.clients.first
            
            if clientEntry?.text == "💣".data(using: .utf8) {
                bombsReceived += 1
            }
        }
        
        XCTAssertEqual(bombsReceived, 1)
        XCTAssertEqual(message?.deliveryState, ZMDeliveryState.sent)
    }
}
