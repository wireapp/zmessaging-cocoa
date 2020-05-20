//
// Wire
// Copyright (C) 2017 Wire Swiss GmbH
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
import WireRequestStrategy
import XCTest

public extension AssetRequestFactory {
    // We need this method for visibility in ObjC
    
    @objc(profileImageAssetRequestWithData:)
    func profileImageAssetRequest(with data: Data) -> ZMTransportRequest? {
        return upstreamRequestForAsset(withData: data, shareable: true, retention: .eternal)
    }
}

class SlowSyncTests_Swift: IntegrationTest {
    
    override func setUp() {
        super.setUp()
        createSelfUserAndConversation()
        createExtraUsersAndConversations()
    }
    
    func testThatItDoesAQuickSyncOnStarTupIfItHasReceivedNotificationsEarlier() {
        // GIVEN
        XCTAssertTrue(login())
        
        mockTransportSession.performRemoteChanges { _ in
            let message = GenericMessage(content: Text(content: "Hello, Test!"), nonce: .create())
            guard
                let client = self.user1.clients.anyObject() as? MockUserClient,
                let selfClient = self.selfUser.clients.anyObject() as? MockUserClient,
                let data = try? message.serializedData() else {
                    return XCTFail()
            }
            self.groupConversation.encryptAndInsertData(from: client, to: selfClient, data: data)
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        mockTransportSession.resetReceivedRequests()
        
        // WHEN
        recreateSessionManager()
        
        // THEN
        var hasNotificationsRequest = false
        for request in mockTransportSession.receivedRequests() {
            if request.path.hasPrefix("/notifications") {
                hasNotificationsRequest = true
            }
            
            XCTAssertFalse(request.path.hasPrefix("/conversations"))
            XCTAssertFalse(request.path.hasPrefix("/connections"))
        }
        
        XCTAssertTrue(hasNotificationsRequest)
    }
    
    func testThatItDoesAQuickSyncAfterTheWebSocketWentDown() {
        // GIVEN
        XCTAssertTrue(login())
        
        mockTransportSession.performRemoteChanges { _ in
            let message = GenericMessage(content: Text(content: "Hello, Test!"), nonce: .create())
            guard
                let client = self.user1.clients.anyObject() as? MockUserClient,
                let selfClient = self.selfUser.clients.anyObject() as? MockUserClient,
                let data = try? message.serializedData() else {
                    return XCTFail()
            }
            self.groupConversation.encryptAndInsertData(from: client, to: selfClient, data: data)
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        mockTransportSession.resetReceivedRequests()
        
        // WHEN
        mockTransportSession.performRemoteChanges { session in
            session.simulatePushChannelClosed()
            session.simulatePushChannelOpened()
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // THEN
        var hasNotificationsRequest = false
        for request in mockTransportSession.receivedRequests() {
            if request.path.hasPrefix("/notifications") {
                hasNotificationsRequest = true
            }
            
            XCTAssertFalse(request.path.hasPrefix("/conversations"))
            XCTAssertFalse(request.path.hasPrefix("/connections"))
        }
              
        XCTAssertTrue(hasNotificationsRequest)
    }
}
