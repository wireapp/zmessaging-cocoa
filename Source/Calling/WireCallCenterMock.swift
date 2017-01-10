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

public class WireCallCenterMock : WireCallCenter {
    
    public var callState : CallState = .none
    
    public required init(userId: UUID, clientId: String, registerObservers: Bool) {
        super.init(userId: userId, clientId: clientId, registerObservers: false)
    }
    
    override public func startCall(conversationId: UUID, video: Bool) -> Bool {
        return true
    }
    
    override public func answerCall(conversationId: UUID) -> Bool {
        return true
    }
    
    override public func closeCall(conversationId: UUID) {
        
    }
    
    override public func ignoreCall(conversationId: UUID) {
        
    }
    
    override public func received(data: Data, currentTimestamp: Date, serverTimestamp: Date, conversationId: UUID, userId: UUID, clientId: String) {
        
    }
    
    public override func callState(conversationId: UUID) -> CallState {
        return callState
    }
    
    public override func toogleVideo(conversationID: UUID, active: Bool) {
        
    }
    
}
