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
import WireSyncEngine
import WireMockTransport

class OTRTests : IntegrationTest {
    
    override func setUp() {
        super.setUp()
        
        createSelfUserAndConversation()
        createExtraUsersAndConversations()
    }
        
    func testThatItSendsEncryptedTextMessage() {
        // given
        XCTAssert(login())
        
        guard let conversation = self.conversation(for: self.selfToUser1Conversation) else {return XCTFail()}
        
        let client1 = user1.clients.anyObject() as! MockUserClient
        let text = "Foo bar, but encrypted"
        self.mockTransportSession.resetReceivedRequests()
        
        // when
        var message: ZMConversationMessage?
        userSession?.performChanges {
            message = conversation.append(text: text)
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertNotNil(message)
        let expected = "/conversations/\(conversation.remoteIdentifier!.transportString())/otr/messages"
        let requests = mockTransportSession.receivedRequests()
        XCTAssertEqual(requests[0].path, expected)
        XCTAssertEqual(requests[1].path, "/users/prekeys")
        XCTAssertEqual(requests[2].path, "/users/\(user1.identifier)/clients/\(client1.identifier!)")
        XCTAssertEqual(requests[3].path, expected)
    }
    
    func testThatItSendsEncryptedImageMessage() {
        // given
        XCTAssert(login())

        guard let conversation = self.conversation(for: self.selfToUser1Conversation) else { return XCTFail() }
        self.mockTransportSession.resetReceivedRequests()
        let imageData = self.verySmallJPEGData()
        let client1 = user1.clients.anyObject() as! MockUserClient
        
        // when
        var message: ZMConversationMessage? = nil
        userSession?.performChanges {
             message = conversation.append(imageFromData: imageData)
        }
        
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertNotNil(message)
        let requests = mockTransportSession.receivedRequests()
        let messageSendingPath = "/conversations/\(conversation.remoteIdentifier!.transportString())/otr/messages"
        XCTAssertEqual(requests[0].path, "/assets/v3")
        XCTAssertEqual(requests[1].path, messageSendingPath)
        XCTAssertEqual(requests[2].path, "/users/prekeys")
        XCTAssertEqual(requests[3].path, "/users/\(user1.identifier)/clients/\(client1.identifier!)")
        XCTAssertEqual(requests[4].path, messageSendingPath)
    }
    
    func testThatItSendsARequestToUpdateSignalingKeys() {
        
        // given
        XCTAssert(login())
        self.mockTransportSession.resetReceivedRequests()
        
    
        var didReregister = false
        self.mockTransportSession.responseGeneratorBlock = { response in
            if response.path.contains("/clients/") && response.payload?.asDictionary()?["sigkeys"] != nil {
                didReregister = true
                return ZMTransportResponse(payload: [] as ZMTransportData, httpStatus: 200, transportSessionError: nil)
            }
            return nil
        }
        
        // when
        self.userSession?.performChanges {
            UserClient.resetSignalingKeysInContext(self.userSession!.managedObjectContext)
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // then
        XCTAssertTrue(didReregister)
    }

    func testThatItCreatesNewKeysIfReqeustToSyncSignalingKeysFailedWithBadRequest() {
        
        // given
        XCTAssert(login())
        self.mockTransportSession.resetReceivedRequests()

        var tryCount = 0
        var (firstMac, firstEnc) = (String(), String())
        self.mockTransportSession.responseGeneratorBlock = { response in
            guard let payload = response.payload?.asDictionary() else { return nil }
            
            if response.path.contains("/clients/") && payload["sigkeys"] != nil {
                let keys = payload["sigkeys"] as? [String: Any]
                let macKey = keys?["mackey"] as? String
                let encKey = keys?["enckey"] as? String
                
                if tryCount == 0 {
                    tryCount += 1
                    guard let mac = macKey, let enc = encKey else { XCTFail("No signaling keys in payload"); return nil }
                    (firstMac, firstEnc) = (mac, enc)
                    return ZMTransportResponse(payload: ["label" : "bad-request"] as ZMTransportData, httpStatus: 400, transportSessionError: nil)
                }
                tryCount += 1
                XCTAssertNotEqual(macKey, firstMac)
                XCTAssertNotEqual(encKey, firstEnc)
                return ZMTransportResponse(payload: [] as ZMTransportData, httpStatus: 200, transportSessionError: nil)
            }
            return nil
        }
        
        // when
        userSession?.performChanges {
            UserClient.resetSignalingKeysInContext(self.userSession!.managedObjectContext)
        }
        
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(tryCount, 2)
    }

}

