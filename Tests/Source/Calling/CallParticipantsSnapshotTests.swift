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

    private let alice = User()
    private let bob = User()

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
        let member1 = AVSCallMember(userId: alice.userId, clientId: alice.iphone, audioState: .established)
        let member2 = AVSCallMember(userId: alice.userId, clientId: alice.iphone, audioState: .connecting)

        // When
        let sut = createSut(members: [member1, member2])

        
        // Then
        XCTAssertEqual(sut.members.array, [member1])
    }
    
    func testThat_ItDoesNotCrash_WhenUpdated_WithDuplicateCallMembers(){
        // Given
        let member1 = AVSCallMember(userId: alice.userId, clientId: alice.iphone, audioState: .established)
        let member2 = AVSCallMember(userId: alice.userId, clientId: alice.iphone, audioState: .connecting)
        let sut = createSut(members: [])

        // when
        sut.callParticipantsChanged(participants: [member1, member2])
        
        // then
        XCTAssertEqual(sut.members.array, [member1])
    }

    func testThat_ItDoesNotConsider_AUserWithMultipleDevices_AsDuplicated() {
        // Given
        let member1 = AVSCallMember(userId: alice.userId, clientId: alice.iphone, audioState: .established)
        let member2 = AVSCallMember(userId: alice.userId, clientId: alice.desktop, audioState: .connecting)

        // When
        let sut = createSut(members: [member1, member2])

        // Then
        XCTAssertEqual(sut.members.array, [member1, member2])
    }

    // MARK: - Network Quality

    func testThat_ItTakesTheWorstNetworkQuality_FromParticipants() {
        // Given
        let normalQuality = AVSCallMember(userId: alice.userId, clientId: alice.iphone, networkQuality: .normal)
        let mediumQuality = AVSCallMember(userId: alice.userId, clientId: alice.desktop, networkQuality: .medium)
        let poorQuality = AVSCallMember(userId: bob.userId, clientId: bob.iphone, networkQuality: .poor)
        let problemQuality = AVSCallMember(userId: bob.userId, clientId: bob.desktop, networkQuality: .problem)
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

    // MARK: - Updates

    func testThat_ItUpdatesNetworkQuality_WhenItChangesForParticipant() {
        // Given
        let member1 = AVSCallMember(userId: alice.userId, clientId: alice.iphone, audioState: .established, networkQuality: .normal)
        let member2 = AVSCallMember(userId: bob.userId, clientId: bob.iphone, audioState: .established, networkQuality: .normal)
        let sut = createSut(members: [member1, member2])

        XCTAssertEqual(sut.networkQuality, .normal)

        // When, then
        sut.callParticipantNetworkQualityChanged(userId: member1.remoteId, clientId: member1.clientId, networkQuality: .medium)
        XCTAssertEqual(sut.networkQuality, .medium)

        // When, then
        sut.callParticipantNetworkQualityChanged(userId: member2.remoteId, clientId: member2.clientId, networkQuality: .poor)
        XCTAssertEqual(sut.networkQuality, .poor)

        // When, then
        sut.callParticipantNetworkQualityChanged(userId: member1.remoteId, clientId: member1.clientId, networkQuality: .normal)
        sut.callParticipantNetworkQualityChanged(userId: member2.remoteId, clientId: member2.clientId, networkQuality: .normal)
        XCTAssertEqual(sut.networkQuality, .normal)
    }

    func testThat_ItUpdatesAudioState_WhenItChangesForParticipant() {
        // Given
        let member1 = AVSCallMember(userId: alice.userId, clientId: alice.iphone, audioState: .connecting)
        let member2 = AVSCallMember(userId: bob.userId, clientId: bob.iphone, audioState: .connecting)
        let sut = createSut(members: [member1, member2])

        // When
        sut.callParticipantAudioEstablished(userId: member1.remoteId, clientId: member1.clientId)

        // Then
        let updatedMember1 = AVSCallMember(userId: alice.userId, clientId: alice.iphone, audioState: .established)
        XCTAssertEqual(sut.members.array, [updatedMember1, member2])
    }

    func testThat_ItUpdatesVideoState_WhenItChangesForParticipant() {
        // Given
        let member1 = AVSCallMember(userId: alice.userId, clientId: alice.iphone, videoState: .stopped)
        let member2 = AVSCallMember(userId: bob.userId, clientId: bob.iphone, videoState: .stopped)
        let sut = createSut(members: [member1, member2])

        // When
        sut.callParticipantVideoStateChanged(userId: member1.remoteId, clientId: member1.clientId, videoState: .screenSharing)

        // Then
        let updatedMember1 = AVSCallMember(userId: alice.userId, clientId: alice.iphone, videoState: .screenSharing)
        XCTAssertEqual(sut.members.array, [updatedMember1, member2])
    }

    func testThat_ItDoesNotUpdateMember_WhenNoMatchFound() {
        // Given
        let member1 = AVSCallMember(userId: alice.userId, clientId: alice.iphone, videoState: .stopped)
        let member2 = AVSCallMember(userId: bob.userId, clientId: bob.iphone, videoState: .stopped)
        let sut = createSut(members: [member1, member2])

        // When
        let unknownMember = AVSCallMember(userId: alice.userId, clientId: alice.desktop, videoState: .stopped)
        sut.callParticipantVideoStateChanged(userId: unknownMember.remoteId, clientId: unknownMember.clientId, videoState: .screenSharing)

        // Then
        XCTAssertEqual(sut.members.array, [member1, member2])
    }

}

private extension CallParticipantsSnapshotTests {

    struct User {

        let userId = UUID()
        let iphone = "String"
        let desktop = "Desktop"

    }
}
