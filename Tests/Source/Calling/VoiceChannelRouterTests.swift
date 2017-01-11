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
import XCTest

@testable import zmessaging


class VoiceChannelRouterTests : MessagingTest {
    
    var wireCallCenterMock : WireCallCenterV3Mock? = nil
    var conversation : ZMConversation?

    override func setUp() {
        super.setUp()
        
        let selfUser = ZMUser.selfUser(in: syncMOC)
        selfUser.remoteIdentifier = UUID.create()
        
        let selfClient = createSelfClient()
        
        conversation = ZMConversation.insertNewObject(in: self.syncMOC)
        conversation?.remoteIdentifier = UUID.create()
        
        wireCallCenterMock = WireCallCenterV3Mock(userId: selfUser.remoteIdentifier!, clientId: selfClient.remoteIdentifier!, registerObservers: false)
    }
    
    override func tearDown() {
        super.tearDown()
        
        VoiceChannelRouter.isCallingV3Enabled = false
        wireCallCenterMock = nil
    }
    
    func testCurrenVoiceChannel_oneToOne_idle_callingV3Disabled() {
        // given
        let sut = VoiceChannelRouter(conversation: conversation!)
        conversation?.conversationType = .oneOnOne
        
        // then
        XCTAssertTrue(sut.currentVoiceChannel === sut.v2)
    }
    
    func testCurrenVoiceChannel_oneToOne_idle_callingV3Enabled() {
        // given
        let sut = VoiceChannelRouter(conversation: conversation!)
        conversation?.conversationType = .oneOnOne
        VoiceChannelRouter.isCallingV3Enabled = true
        
        // then
        XCTAssertTrue(sut.currentVoiceChannel === sut.v3)
    }
    
    func testCurrenVoiceChannel_group_idle_callingV3Enabled() {
        // given
        let sut = VoiceChannelRouter(conversation: conversation!)
        conversation?.conversationType = .group
        VoiceChannelRouter.isCallingV3Enabled = true
        
        // then
        XCTAssertTrue(sut.currentVoiceChannel === sut.v2)
    }
    
    func testCurrenVoiceChannel_oneToOne_incomingV2Call_callingV3Enabled() {
        // given
        let sut = VoiceChannelRouter(conversation: conversation!)
        conversation?.conversationType = .oneOnOne
        conversation?.callDeviceIsActive = true
        VoiceChannelRouter.isCallingV3Enabled = true
        
        // then
        XCTAssertTrue(sut.currentVoiceChannel === sut.v2)
    }
    
    func testCurrenVoiceChannel_oneToOne_incomingV3Call_callingV3Disabled() {
        // given
        let sut = VoiceChannelRouter(conversation: conversation!)
        conversation?.conversationType = .oneOnOne
        wireCallCenterMock?.callState = .incoming(video: false)
        
        // then
        XCTAssertTrue(sut.currentVoiceChannel === sut.v3)
    }
    
}
