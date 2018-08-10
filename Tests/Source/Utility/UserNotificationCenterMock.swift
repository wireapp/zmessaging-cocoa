////
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
import WireSyncEngine

class UserNotificationCenterMock: UserNotificationCenter {
    
    weak var delegate: UNUserNotificationCenterDelegate?
    
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
        
    }
    
    func requestAuthorization(options: UNAuthorizationOptions,
                              completionHandler: @escaping (Bool, Error?) -> Void)
    {
        
    }
    
    func add(_ request: UNNotificationRequest,
             withCompletionHandler: ((Error?) -> Void)?)
    {
        
    }
    
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        
    }
    
    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        
    }
    
    func removeAllNotifications(withIdentifiers identifiers: [String]) {
        
    }
}
