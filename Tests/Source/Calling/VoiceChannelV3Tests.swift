//
//  VoiceChannelV3Tests.swift
//  zmessaging-cocoa
//
//  Created by Jacob on 06/03/17.
//  Copyright © 2017 Zeta Project Gmbh. All rights reserved.
//

import Foundation

import Foundation
@testable import zmessaging

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
        
        wireCallCenterMock = WireCallCenterV3Mock(userId: selfUser.remoteIdentifier!, clientId: selfClient.remoteIdentifier!, registerObservers: false)
        
        sut = VoiceChannelV3(conversation: conversation!)
    }
    
    override func tearDown() {
        super.tearDown()
        
        ZMUserSession.callingProtocolStrategy = .version3
        wireCallCenterMock = nil
    }
    
    func testThatItStartsACall_whenTheresNotAnIncomingCall() {
        // given
        wireCallCenterMock?.callState = .none
        
        // when
        _ = sut.join(video: false)
        
        // then
        XCTAssertTrue(wireCallCenterMock!.didCallStartCall)
    }
    
    func testThatItAnswers_whenTheresAnIncomingCall() {
        // given
        wireCallCenterMock?.callState = .incoming(video: false)
        
        // when
        _ = sut.join(video: false)
        
        // then
        XCTAssertTrue(wireCallCenterMock!.didCallAnswerCall)
    }
    
    func testThatItAnswers_whenTheresAnIncomingDegradedCall() {
        // given
        wireCallCenterMock?.callState = .incoming(video: false)
        conversation?.setValue(NSNumber.init(value: ZMConversationSecurityLevel.secureWithIgnored.rawValue), forKey: "securityLevel")
        
        // when
        _ = sut.join(video: false)
        
        // then
        XCTAssertTrue(wireCallCenterMock!.didCallAnswerCall)
    }
    
    func testMappingFromCallStateToVoiceChannelV2State() {
        // given
        let callStates : [CallState] =  [.none, .incoming(video: false), .answered, .established, .outgoing, .terminating(reason: CallClosedReason.normal), .unknown]
        let notSecureMapping : [VoiceChannelV2State] = [.noActiveUsers, .incomingCall, .selfIsJoiningActiveChannel, .selfConnectedToActiveChannel, .outgoingCall, .noActiveUsers, .invalid]
        let secureWithIgnoredMapping : [VoiceChannelV2State] = [.noActiveUsers, .incomingCallDegraded, .selfIsJoiningActiveChannel, .selfConnectedToActiveChannel, .outgoingCallDegraded, .noActiveUsers, .invalid]
        
        // then
        XCTAssertEqual(callStates.map({ $0.voiceChannelState(securityLevel: .notSecure)}), notSecureMapping)
        XCTAssertEqual(callStates.map({ $0.voiceChannelState(securityLevel: .secureWithIgnored)}), secureWithIgnoredMapping)
    }
    
}
