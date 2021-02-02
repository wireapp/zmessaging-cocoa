//
// Wire
// Copyright (C) 2017 Wire Swiss GmbH
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

@objc public protocol DeleteAccountObserver: NSObjectProtocol {
    /// Account was successfully deleted
    @objc optional func accountDeleted(accountId : UUID)
}

/// Authentication events that could happen after login
enum DeleteAccountEvent {
    /// Account was successfully deleted on the backend
    case accountDeleted
}

@objcMembers public class DeleteAccountNotification : NSObject {
    
    static private let name = Notification.Name(rawValue: "DeleteAccountNotification")
    static private let eventKey = "event"
    
    fileprivate static func notify(event: DeleteAccountEvent, context: NSManagedObjectContext) {
        NotificationInContext(name: self.name, context: context.notificationContext, object:context, userInfo: [self.eventKey: event]).post()
    }
    
    static public func addObserver(_ observer: DeleteAccountObserver,
                                   context: NSManagedObjectContext) -> Any {
         return self.addObserver(observer, context: context, queue: context)
    }
    
    static public func addObserver(_ observer: DeleteAccountObserver,
                                   queue: ZMSGroupQueue) -> Any {
        return self.addObserver(observer, context: nil, queue: queue)
    }

    static public func addObserver(_ observer: DeleteAccountObserver) -> Any {
        return self.addObserver(observer, context: nil, queue: DispatchGroupQueue(queue: DispatchQueue.main))
    }

    static private func addObserver(_ observer: DeleteAccountObserver, context: NSManagedObjectContext? = nil, queue: ZMSGroupQueue) -> Any {
        
        let token = NotificationInContext.addUnboundedObserver(name: name, context: context?.notificationContext, queue:nil) { [weak observer] (note) in            
            guard
                let event = note.userInfo[eventKey] as? DeleteAccountEvent,
                let observer = observer,
                let context = note.object as? NSManagedObjectContext else { return }
            
            context.performGroupedBlock {
                guard let accountId = ZMUser.selfUser(in: context).remoteIdentifier else {
                    return
                }
                
                queue.performGroupedBlock {
                    switch event {
                    case .accountDeleted:
                        observer.accountDeleted?(accountId: accountId)
                    }
                }
            }
        }
                
        return SelfUnregisteringNotificationCenterToken(token)
    }
    
    static public func addObserver(_ observer: DeleteAccountObserver, userSession: ZMUserSession) -> Any {
        return self.addObserver(observer, context: userSession.managedObjectContext)
    }
}

@objc public extension DeleteAccountNotification {
    @objc(notifyAccountDeletedInContext:)
    static func notifyAccountDeleted(context: NSManagedObjectContext) {
        self.notify(event: .accountDeleted, context: context)
    }
}
