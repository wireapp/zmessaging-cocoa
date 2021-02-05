//
//  CallParticipantsKind.swift
//  WireSyncEngine-ios
//
//  Created by David Henner on 04.02.21.
//  Copyright © 2021 Zeta Project Gmbh. All rights reserved.
//

import Foundation

public enum CallParticipantsKind {
    case all
    case smoothedActiveSpeakers
}

extension CallParticipantsKind {
    
    func isActive(activeSpeaker: AVSActiveSpeakersChange.ActiveSpeaker) -> Bool {
        switch self {
        case .all:
            return activeSpeaker.audioLevelNow > 0
        case .smoothedActiveSpeakers:
            return activeSpeaker.audioLevel > 0
        }
    }

}
