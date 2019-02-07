//
// Wire
// Copyright (C) 2019 Wire Swiss GmbH
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

extension ZMUserTranscoder {
    
    @objc
    public func processUpdateEvent(_ updateEvent: ZMUpdateEvent) {
        switch updateEvent.type {
        case .userUpdate:
            processUserUpdate(updateEvent)
        case .userDelete:
            processUserDeletion(updateEvent)
        default:
            break
        }
    }
    
    private func processUserUpdate(_ updateEvent: ZMUpdateEvent) {
        guard updateEvent.type == .userUpdate else { return }
        
        guard let userPayload = updateEvent.payload["user"] as? [String: Any],
              let userId = (userPayload["id"] as? String).flatMap(UUID.init)
        else {
            return Logging.eventProcessing.error("Malformed user.update update event, skipping...")
        }
        
        let user = ZMUser.fetchAndMerge(with: userId, createIfNeeded: true, in: managedObjectContext)
        user?.update(withTransportData: userPayload, authoritative: false)
    }
    
    private func processUserDeletion(_ updateEvent: ZMUpdateEvent) {
        guard updateEvent.type == .userDelete else { return }
        
        guard let userId = (updateEvent.payload["id"] as? String).flatMap(UUID.init),
              let user = ZMUser.fetchAndMerge(with: userId, createIfNeeded: false, in: managedObjectContext)
        else {
            return Logging.eventProcessing.error("Malformed user.delete update event, skipping...")
        }
        
        if user.isSelfUser {
            deleteAccount()
        } else {
            user.markAccountAsDeleted(at: updateEvent.timeStamp() ?? Date())
        }
    }
    
    private func deleteAccount() {
        PostLoginAuthenticationNotification.notifyAccountDeleted(context: managedObjectContext)
    }
    
}
