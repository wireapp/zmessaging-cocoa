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
@testable import WireSyncEngine

class CallParticipantsSnapshotTests: MessagingTest {

    private typealias Sut = WireSyncEngine.CallParticipantsSnapshot

    var mockWireCallCenterV3: WireCallCenterV3Mock!
    var mockFlowManager: FlowManagerMock!

    override func setUp() {
        super.setUp()
        mockFlowManager = FlowManagerMock()
        mockWireCallCenterV3 = WireCallCenterV3Mock(userId: UUID(),
                                                    clientId: UUID().transportString(),
                                                    uiMOC: uiMOC,
                                                    flowManager: mockFlowManager,
                                                    transport: WireCallCenterTransportMock())
    }
    
    override func tearDown() {
        mockFlowManager = nil
        mockWireCallCenterV3 = nil
        super.tearDown()
    }

    private func createSut(members: [AVSCallMember]) -> Sut {
        return Sut(conversationId: UUID(), members: members, callCenter: mockWireCallCenterV3)
    }

    // MARK: - Duplicates

    func testThat_ItDoesNotCrash_WhenInitialized_WithDuplicateCallMembers(){
        // Given
        let userId = UUID()
        let callMember1 = AVSCallMember(userId: userId, audioState: .established)
        let callMember2 = AVSCallMember(userId: userId, audioState: .connecting)

        // When
        let sut = createSut(members: [callMember1, callMember2])

        
        // Then
        XCTAssertEqual(sut.members.array, [callMember1])
    }
    
    func testThat_ItDoesNotCrash_WhenUpdated_WithDuplicateCallMembers(){
        // Given
        let userId = UUID()
        let callMember1 = AVSCallMember(userId: userId, audioState: .established)
        let callMember2 = AVSCallMember(userId: userId, audioState: .connecting)
        let sut = createSut(members: [])

        // when
        sut.callParticipantsChanged(participants: [callMember1, callMember2])
        
        // then
        XCTAssertEqual(sut.members.array, [callMember1])
    }

    func testThat_ItDoesNotConsider_AUserWithMultipleDevices_AsDuplicated() {
        // Given
        let userId = UUID()
        let callMember1 = AVSCallMember(userId: userId, clientId: "client1", audioState: .established)
        let callMember2 = AVSCallMember(userId: userId, clientId: "client2", audioState: .connecting)

        // When
        let sut = createSut(members: [callMember1, callMember2])

        // Then
        XCTAssertEqual(sut.members.array, [callMember1, callMember2])
    }

    // MARK: - Network Quality

    func testThat_ItTakesTheWorstNetworkQuality_FromParticipants() {
        func member(with quality: NetworkQuality) -> AVSCallMember {
            return AVSCallMember(userId: UUID(),
                                 audioState: .established,
                                 videoState: .started,
                                 networkQuality: quality)
        }

        // Given
        let normalQuality = member(with: .normal)
        let mediumQuality = member(with: .medium)
        let poorQuality = member(with: .poor)
        let problemQuality = member(with: .problem)
        let sut = createSut(members: [])

        XCTAssertEqual(sut.networkQuality, .normal)

        // When, then
        sut.callParticipantsChanged(participants: [normalQuality])
        XCTAssertEqual(sut.networkQuality, .normal)

        // When, then
        sut.callParticipantsChanged(participants: [mediumQuality, normalQuality])
        XCTAssertEqual(sut.networkQuality, .medium)

        // When, then
        sut.callParticipantsChanged(participants: [poorQuality, normalQuality])
        XCTAssertEqual(sut.networkQuality, .poor)

        // When, then
        sut.callParticipantsChanged(participants: [poorQuality, normalQuality, problemQuality])
        XCTAssertEqual(sut.networkQuality, .problem)

        // When, then
        sut.callParticipantsChanged(participants: [mediumQuality, poorQuality])
        XCTAssertEqual(sut.networkQuality, .poor)
    }

    func testThat_ItUpdatesNetworkQuality_WhenItChangesForParticipant() {
        // given
        let member1 = AVSCallMember(userId: UUID(), clientId: "member1", audioState: .established, networkQuality: .normal)
        let member2 = AVSCallMember(userId: UUID(), clientId: "member2", audioState: .established, networkQuality: .normal)
        let sut = createSut(members: [member1, member2])

        XCTAssertEqual(sut.networkQuality, .normal)

        // When, then
        sut.callParticpantNetworkQualityChanged(userId: member1.remoteId, clientId: member1.clientId!, networkQuality: .medium)
        XCTAssertEqual(sut.networkQuality, .medium)

        // When, then
        sut.callParticpantNetworkQualityChanged(userId: member2.remoteId, clientId: member2.clientId!, networkQuality: .poor)
        XCTAssertEqual(sut.networkQuality, .poor)

        // When, then
        sut.callParticpantNetworkQualityChanged(userId: member1.remoteId, clientId: member1.clientId!, networkQuality: .normal)
        sut.callParticpantNetworkQualityChanged(userId: member2.remoteId, clientId: member2.clientId!, networkQuality: .normal)
        XCTAssertEqual(sut.networkQuality, .normal)
    }

    // MARK: - Updates

    func testThat_ItUpdatesMember_WhenACompleteMatchFound() {
        // Given
        let userId = UUID()
        let clientId1 = "client1"
        let clientId2 = "client2"

        let member1 = AVSCallMember(userId: userId, clientId: clientId1, videoState: .started)
        let member2 = AVSCallMember(userId: userId, clientId: clientId2, videoState: .stopped)
        let sut = createSut(members: [member1, member2])

        // When
        sut.callParticpantVideoStateChanged(userId: userId, clientId: clientId2, videoState: .screenSharing)

        // Then
        let updatedMember2 = AVSCallMember(userId: userId, clientId: clientId2, videoState: .screenSharing)
        let expectation = [member1, updatedMember2]
        XCTAssertEqual(sut.members.array, expectation)
    }

    func testThat_ItUpdatesMember_WhenAPartialMatchFound() {
        // Given
        let userId = UUID()
        let clientId1 = "client1"

        let member1 = AVSCallMember(userId: userId, clientId: clientId1, audioState: .connecting)
        let member2 = AVSCallMember(userId: userId, clientId: nil, audioState: .connecting)
        let sut = createSut(members: [member1, member2])

        // When
        sut.callParticpantAudioEstablished(userId: userId, clientId: "client2")

        // Then
        let updatedMember2 = AVSCallMember(userId: userId, clientId: "client2", audioState: .established)
        let expectation = [member1, updatedMember2]
        XCTAssertEqual(sut.members.array, expectation)
    }

    func testThat_ItDoesNotUpdateMember_WhenNoMatchFound() {
        // Given
        let userId = UUID()
        let clientId1 = "client1"
        let clientId2 = "client2"

        let member1 = AVSCallMember(userId: userId, clientId: clientId1, videoState: .started)
        let member2 = AVSCallMember(userId: userId, clientId: clientId2, videoState: .stopped)
        let sut = createSut(members: [member1, member2])

        // When
        sut.callParticpantVideoStateChanged(userId: userId, clientId: "client3", videoState: .screenSharing)

        // Then
        let expectation = [member1, member2]
        XCTAssertEqual(sut.members.array, expectation)
    }

}
