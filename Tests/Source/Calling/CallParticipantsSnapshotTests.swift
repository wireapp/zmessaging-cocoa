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

class CallParticipantsSnapshotTests : MessagingTest {

    var mockWireCallCenterV3 : WireCallCenterV3Mock!
    var mockFlowManager : FlowManagerMock!

    override func setUp() {
        super.setUp()
        mockFlowManager = FlowManagerMock()
        mockWireCallCenterV3 = WireCallCenterV3Mock(userId: UUID(), clientId: "foo", uiMOC: uiMOC, flowManager: mockFlowManager, transport: WireCallCenterTransportMock())
    }
    
    override func tearDown() {
        mockFlowManager = nil
        mockWireCallCenterV3 = nil
        super.tearDown()
    }

    func testThatItDoesNotCrashWhenInitializedWithDuplicateCallMembers(){
        // given
        let userId = UUID()
        let callMember1 = AVSCallMember(userId: userId, audioState: .established)
        let callMember2 = AVSCallMember(userId: userId, audioState: .connecting)

        // when
        let sut = WireSyncEngine.CallParticipantsSnapshot(conversationId: UUID(),
                                                          members: [callMember1, callMember2],
                                                          callCenter: mockWireCallCenterV3)
        
        // then
        // it does not crash and
        XCTAssertEqual(sut.members.array.count, 1)
        if let first = sut.members.array.first {
            XCTAssertTrue(first.audioState == .established)
        }
    }
    
    func testThatItDoesNotCrashWhenUpdatedWithDuplicateCallMembers(){
        // given
        let userId = UUID()
        let callMember1 = AVSCallMember(userId: userId, audioState: .established)
        let callMember2 = AVSCallMember(userId: userId, audioState: .connecting)
        let sut = WireSyncEngine.CallParticipantsSnapshot(conversationId: UUID(),
                                                          members: [],
                                                          callCenter: mockWireCallCenterV3)

        // when
        sut.callParticipantsChanged(participants: [callMember1, callMember2])
        
        // then
        // it does not crash and
        XCTAssertEqual(sut.members.array.count, 1)
        if let first = sut.members.array.first {
            XCTAssertTrue(first.audioState == .established)
        }
    }

    func testThatItDoesNotConsiderAUserWithMultipleDevicesAsDuplicated() {
        // given
        let userId = UUID()
        let callMember1 = AVSCallMember(userId: userId, clientId: "client1", audioState: .established)
        let callMember2 = AVSCallMember(userId: userId, clientId: "client2", audioState: .connecting)

        // when
        let sut = WireSyncEngine.CallParticipantsSnapshot(conversationId: UUID(),
                                                          members: [callMember1, callMember2],
                                                          callCenter: mockWireCallCenterV3)

        // then
        // it does not crash and
        XCTAssertEqual(sut.members.array, [callMember1, callMember2])
    }

    func testThatItTakesTheWorstNetworkQualityFromParticipants() {
        // given
        let normalQuality = AVSCallMember(userId: UUID(), audioState: .established, videoState: .started, networkQuality: .normal)
        let mediumQuality = AVSCallMember(userId: UUID(), audioState: .established, videoState: .started, networkQuality: .medium)
        let poorQuality = AVSCallMember(userId: UUID(), audioState: .established, videoState: .started, networkQuality: .poor)
        let problemQuality = AVSCallMember(userId: UUID(), audioState: .established, videoState: .started, networkQuality: .problem)

        let sut = WireSyncEngine.CallParticipantsSnapshot(conversationId: UUID(),
                                                          members: [],
                                                          callCenter: mockWireCallCenterV3)
        XCTAssertEqual(sut.networkQuality, .normal)

        // when
        sut.callParticipantsChanged(participants: [normalQuality])
        // then
        XCTAssertEqual(sut.networkQuality, .normal)

        // when
        sut.callParticipantsChanged(participants: [mediumQuality, normalQuality])
        // then
        XCTAssertEqual(sut.networkQuality, .medium)

        // when
        sut.callParticipantsChanged(participants: [poorQuality, normalQuality])
        // then
        XCTAssertEqual(sut.networkQuality, .poor)

        // when
        sut.callParticipantsChanged(participants: [mediumQuality, poorQuality])
        // then
        XCTAssertEqual(sut.networkQuality, .poor)

        // when
        sut.callParticipantsChanged(participants: [problemQuality, poorQuality])
        // then
        XCTAssertEqual(sut.networkQuality, .problem)
    }

    func testThatItUpdatesNetworkQualityWhenItChangesForParticipant() {
        // given
        let callMember1 = AVSCallMember(userId: UUID(), audioState: .established, networkQuality: .normal)
        let callMember2 = AVSCallMember(userId: UUID(), audioState: .established, networkQuality: .normal)
        let sut = WireSyncEngine.CallParticipantsSnapshot(conversationId: UUID(),
                                                          members: [callMember1, callMember2],
                                                          callCenter: mockWireCallCenterV3)
        XCTAssertEqual(sut.networkQuality, .normal)

        // when
        sut.callParticpantNetworkQualityChanged(userId: callMember1.remoteId, networkQuality: .medium)

        // then
        XCTAssertEqual(sut.networkQuality, .medium)

        // when
        sut.callParticpantNetworkQualityChanged(userId: callMember2.remoteId, networkQuality: .poor)

        // then
        XCTAssertEqual(sut.networkQuality, .poor)

        // when
        sut.callParticpantNetworkQualityChanged(userId: callMember1.remoteId, networkQuality: .normal)
        sut.callParticpantNetworkQualityChanged(userId: callMember2.remoteId, networkQuality: .normal)

        // then
        XCTAssertEqual(sut.networkQuality, .normal)
    }

    func testThatItUpdatesVideoStateOnlyWhenUserIdAndClientIdMatch() {
        // given
        let userId = UUID()
        let clientId1 = "client1"
        let clientId2 = "client2"

        let callMember1 = AVSCallMember(userId: userId, clientId: clientId1, videoState: .started)
        let callMember2 = AVSCallMember(userId: userId, clientId: clientId2, videoState: .stopped)

        let sut = WireSyncEngine.CallParticipantsSnapshot(conversationId: UUID(),
                                                          members: [callMember1, callMember2],
                                                          callCenter: mockWireCallCenterV3)
        // when
        sut.callParticpantVideoStateChanged(userId: userId, clientId: clientId2, videoState: .screenSharing)

        // then
        let updatedCallMember2 = AVSCallMember(userId: userId, clientId: clientId2, videoState: .screenSharing)
        let expectation = [callMember1, updatedCallMember2]
        XCTAssertEqual(sut.members.array, expectation)
    }

    func testThatItUpdatesTheCallMemberWithAClientId() {
        // given
        let userId = UUID()
        let clientId = "clientId"

        let callMember = AVSCallMember(userId: userId, clientId: nil, videoState: .stopped)

        let sut = WireSyncEngine.CallParticipantsSnapshot(conversationId: UUID(),
                                                          members: [callMember],
                                                          callCenter: mockWireCallCenterV3)
        // when
        sut.callParticpantVideoStateChanged(userId: userId, clientId: clientId, videoState: .started)

        // then
        let expectation = [AVSCallMember(userId: userId, clientId: clientId, videoState: .started)]
        XCTAssertEqual(sut.members.array, expectation)
    }
}
