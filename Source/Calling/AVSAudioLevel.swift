//
// Wire
// Copyright (C) 2020 Wire Swiss GmbH
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
import avs

struct AVSActiveSpeakersChange: Codable {
    let audioLevels: [AudioLevel]
    
    struct AudioLevel: Codable {
        let userId: UUID
        let clientId: String
        let audioLevel: Int
        
        enum CodingKeys: String, CodingKey {
            case userId = "userid"
            case clientId = "clientid"
            case audioLevel = "audio_level"
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case audioLevels = "audio_levels"
    }
}

struct AVSAudioLevel {
    let client: AVSClient
    let audioLevel: Int
}

extension AVSAudioLevel {
    init(audioLevel: AVSActiveSpeakersChange.AudioLevel) {
        self.client = AVSClient(userId: audioLevel.userId, clientId: audioLevel.clientId)
        self.audioLevel = audioLevel.audioLevel
    }
}

extension AVSAudioLevel: Equatable {
    
}
