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

@objc public class UserExpirationObserver: NSObject {
    var expiringUsers: Set<ZMUser> = Set()
    
    func check(users: Set<ZMUser>) {
        let allWireless = Set(users.filter { $0.isWirelessUser }).subtracting(expiringUsers)
        
        let expired = Set(allWireless.filter { $0.isExpired })
        expiringUsers.subtract(expired)
        let notExpired = allWireless.subtracting(expired)
        
        expired.forEach { $0.needsToBeUpdatedFromBackend = true }
        notExpired.forEach {
            self.perform(#selector(expire(_:)), with: $0, afterDelay: $0.expiresAfter)
        }
        expiringUsers.formUnion(notExpired)
    }
    
    func expire(_ user: ZMUser) {
        user.needsToBeUpdatedFromBackend = true
        expiringUsers.remove(user)
    }
    
    func check(usersIn conversation: ZMConversation) {
        check(users: Set(conversation.activeParticipants.array as! [ZMUser]))
    }
}
