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

import Foundation
@testable import WireSyncEngine

class VoiceChannelV3Tests : MessagingTest {
    
    var wireCallCenterMock : WireCallCenterV3Mock? = nil
    var conversation : ZMConversation?
    var sut : VoiceChannelV3!
    
    override func setUp() {
        super.setUp()
        
        let selfUser = ZMUser.selfUser(in: syncMOC)
        selfUser.remoteIdentifier = UUID.create()
        
        let selfClient = createSelfClient()
        
        conversation = ZMConversation.insertNewObject(in: self.syncMOC)
        conversation?.remoteIdentifier = UUID.create()
        
        wireCallCenterMock = WireCallCenterV3Mock(userId: selfUser.remoteIdentifier!, clientId: selfClient.remoteIdentifier!, uiMOC: uiMOC)
        
        sut = VoiceChannelV3(conversation: conversation!)
    }
    
    override func tearDown() {
        super.tearDown()
        
        ZMUserSession.callingProtocolStrategy = .version3
        wireCallCenterMock = nil
    }
    
    func testThatItStartsACall_whenTheresNotAnIncomingCall() {
        // given
        wireCallCenterMock?.mockCallState = .none
        
        // when
        _ = sut.join(video: false)
        
        // then
        XCTAssertTrue(wireCallCenterMock!.didCallStartCall)
    }
    
    func testThatItAnswers_whenTheresAnIncomingCall() {
        // given
        wireCallCenterMock?.mockCallState = .incoming(video: false, shouldRing: false)
        
        // when
        _ = sut.join(video: false)
        
        // then
        XCTAssertTrue(wireCallCenterMock!.didCallAnswerCall)
    }
    
    func testThatItDoesntAnswer_whenTheresAnIncomingDegradedCall() {
        // given
        wireCallCenterMock?.mockCallState = .incoming(video: false, shouldRing: false)
        conversation?.setValue(NSNumber.init(value: ZMConversationSecurityLevel.secureWithIgnored.rawValue), forKey: "securityLevel")
        
        // when
        _ = sut.join(video: false)
        
        // then
        XCTAssertFalse(wireCallCenterMock!.didCallAnswerCall)
    }
    
    func testMappingFromCallStateToVoiceChannelV2State() {
        // given
        let callStates : [CallState] =  [.none, .incoming(video: false, shouldRing: true), .answered, .established, .outgoing, .terminating(reason: CallClosedReason.normal), .unknown]
        let notSecureMapping : [VoiceChannelV2State] = [.noActiveUsers, .incomingCall, .selfIsJoiningActiveChannel, .selfConnectedToActiveChannel, .outgoingCall, .noActiveUsers, .invalid]
        let secureWithIgnoredMapping : [VoiceChannelV2State] = [.noActiveUsers, .incomingCallDegraded, .selfIsJoiningActiveChannelDegraded, .selfConnectedToActiveChannel, .outgoingCallDegraded, .noActiveUsers, .invalid]
        
        // then
        XCTAssertEqual(callStates.map({ $0.voiceChannelState(securityLevel: .notSecure)}), notSecureMapping)
        XCTAssertEqual(callStates.map({ $0.voiceChannelState(securityLevel: .secureWithIgnored)}), secureWithIgnoredMapping)
    }
    
}
