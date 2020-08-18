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

/**
 * The snapshot of the state of a call.
 */

struct CallSnapshot {
    let callParticipants: CallParticipantsSnapshot
    let callState: CallState
    let callStarter: UUID
    let isVideo: Bool
    let isGroup: Bool
    let isConstantBitRate: Bool
    let videoState: VideoState
    let networkQuality: NetworkQuality
    let isConferenceCall: Bool
    var conversationObserverToken : NSObjectProtocol?

    /**
     * Updates the snapshot with the new state of the call.
     * - parameter callState: The new state of the call computed from AVS.
     */

    func update(with callState: CallState) -> CallSnapshot {
        return CallSnapshot(callParticipants: callParticipants,
                            callState: callState,
                            callStarter: callStarter,
                            isVideo: isVideo,
                            isGroup: isGroup,
                            isConstantBitRate: isConstantBitRate,
                            videoState: videoState,
                            networkQuality: networkQuality,
                            isConferenceCall: isConferenceCall,
                            conversationObserverToken: conversationObserverToken)
    }

    /**
     * Updates the snapshot with the CBR state.
     * - parameter enabled: Whether constant bitrate was enabled.
     */

    func updateConstantBitrate(_ enabled: Bool) -> CallSnapshot {
        return CallSnapshot(callParticipants: callParticipants,
                            callState: callState,
                            callStarter: callStarter,
                            isVideo: isVideo,
                            isGroup: isGroup,
                            isConstantBitRate: enabled,
                            videoState: videoState,
                            networkQuality: networkQuality,
                            isConferenceCall: isConferenceCall,
                            conversationObserverToken: conversationObserverToken)
    }

    /**
     * Updates the snapshot with the new video state.
     * - parameter videoState: The new video state.
     */

    func updateVideoState(_ videoState: VideoState) -> CallSnapshot {
        return CallSnapshot(callParticipants: callParticipants,
                            callState: callState,
                            callStarter: callStarter,
                            isVideo: isVideo,
                            isGroup: isGroup,
                            isConstantBitRate: isConstantBitRate,
                            videoState: videoState,
                            networkQuality: networkQuality,
                            isConferenceCall: isConferenceCall,
                            conversationObserverToken: conversationObserverToken)
    }

    /**
     * Updates the snapshot with the new network condition.
     * - parameter networkCondition: The new network condition.
     */

    func updateNetworkQuality(_ networkQuality: NetworkQuality) -> CallSnapshot {
        return CallSnapshot(callParticipants: callParticipants,
                            callState: callState,
                            callStarter: callStarter,
                            isVideo: isVideo,
                            isGroup: isGroup,
                            isConstantBitRate: isConstantBitRate,
                            videoState: videoState,
                            networkQuality: networkQuality,
                            isConferenceCall: isConferenceCall,
                            conversationObserverToken: conversationObserverToken)
    }

}
