//
// Wire
// Copyright (C) 2018 Wire Swiss GmbH
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
import XCTest

@testable import WireSyncEngine

final class DummyServiceUser: NSObject, ServiceUser {
    
    var previewImageData: Data? = nil
    
    var completeImageData: Data? = nil
    
    var name: String? = "Service user"
    
    var displayName: String = "Service"
    
    var initials: String? = "S"
    
    var handle: String? = "service"
    
    var isSelfUser: Bool = false
    
    var smallProfileImageCacheKey: String? = ""
    
    var mediumProfileImageCacheKey: String? = ""
    
    var isConnected: Bool = false
    
    var accentColorValue: ZMAccentColor = ZMAccentColor.brightOrange
    
    var imageMediumData: Data! = Data()
    
    var imageSmallProfileData: Data! = Data()
    
    var imageSmallProfileIdentifier: String! = ""
    
    var imageMediumIdentifier: String! = ""
    
    var isTeamMember: Bool = false
    
    var teamRole: TeamRole = .member
    
    var canBeConnected: Bool = false
    
    var isServiceUser: Bool = true
    
    func requestPreviewProfileImage() {
        
    }
    
    func requestCompleteProfileImage() {
        
    }
    
    func imageData(for size: ProfileImageSize, queue: DispatchQueue, completion: @escaping (Data?) -> Void) {
        
    }
    
    func refreshData() {
        
    }
    
    func connect(message: String) {
        
    }
    
    func isGuest(in conversation: ZMConversation) -> Bool {
        return false
    }
    
    var connectionRequestMessage: String? = ""
    
    var totalCommonConnections: UInt = 0
    
    var serviceIdentifier: String?
    var providerIdentifier: String?
    
    init(serviceIdentifier: String, providerIdentifier: String) {
        self.serviceIdentifier = serviceIdentifier
        self.providerIdentifier = providerIdentifier
        super.init()
    }
}

public final class ServiceUserTests : IntegrationTest {
    public override func setUp() {
        super.setUp()
        self.createSelfUserAndConversation()
        self.createExtraUsersAndConversations()
        
        XCTAssertTrue(self.login())
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    }
    
    func createService() -> ServiceUser {
        var mockServiceId: String!
        var mockProviderId: String!
        mockTransportSession.performRemoteChanges { (remoteChanges) in
            let mockService = remoteChanges.insertService(withName: "Service A",
                                                          identifier: UUID().transportString(),
                                                          provider: UUID().transportString())
            
            mockServiceId = mockService.identifier
            mockProviderId = mockService.provider
        }
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        return DummyServiceUser(serviceIdentifier: mockServiceId, providerIdentifier: mockProviderId)
    }
    
    func testThatItAddsServiceToExistingConversation() throws {
        // given
        let jobIsDone = expectation(description: "service is added")
        let service = self.createService()
        let conversation = self.conversation(for: self.groupConversation)!
        
        // when
        conversation.add(serviceUser: service, in: self.userSession!, completion: { error in
            // expect
            XCTAssertNil(error)
            jobIsDone.fulfill()
        })
        
        // then
        XCTAssertTrue(waitForCustomExpectations(withTimeout: 0.5))
    }
    
    func testThatItCreatesConversationAndAddsUser() {
        // given
        let jobIsDone = expectation(description: "service is added")
        let service = self.createService()
       
        // when
        self.userSession!.startConversation(with: service) { conversation in
            XCTAssertNotNil(conversation)
            jobIsDone.fulfill()
        }
        
        // then
        XCTAssertTrue(waitForCustomExpectations(withTimeout: 0.5))
    }
    
    func testThatItDetectsTheSuccessResponse() {
        // GIVEN
        let response = ZMTransportResponse(payload: nil, httpStatus: 201, transportSessionError: nil)
        // WHEN
        let error = AddBotError(response: response)
        // THEN
        XCTAssertEqual(error, nil)
    }
    
    func testThatItDetectsTheConversationFullResponse() {
        // GIVEN
        let response = ZMTransportResponse(payload: nil, httpStatus: 403, transportSessionError: nil)
        // WHEN
        let error = AddBotError(response: response)
        // THEN
        XCTAssertEqual(error, .tooManyParticipants)
    }
    
    func testThatItDetectsBotRejectedResponse() {
        // GIVEN
        let response = ZMTransportResponse(payload: nil, httpStatus: 419, transportSessionError: nil)
        // WHEN
        let error = AddBotError(response: response)
        // THEN
        XCTAssertEqual(error, .botRejected)
    }
    
    func testThatItDetectsBotNotResponding() {
        // GIVEN
        let response = ZMTransportResponse(payload: nil, httpStatus: 502, transportSessionError: nil)
        // WHEN
        let error = AddBotError(response: response)
        // THEN
        XCTAssertEqual(error, .botNotResponding)
    }
    
    func testThatItDetectsGeneralError() {
        // GIVEN
        let response = ZMTransportResponse(payload: nil, httpStatus: 500, transportSessionError: nil)
        // WHEN
        let error = AddBotError(response: response)
        // THEN
        XCTAssertEqual(error, .general)
    }
}
