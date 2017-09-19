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
import CoreData
import WireDataModel

/// Abstraction of queue
public protocol GenericAsyncQueue {
    
    func performAsync(_ block: @escaping () -> ())
}

extension DispatchQueue: GenericAsyncQueue {
    
    public func performAsync(_ block: @escaping () -> ()) {
        self.async(execute: block)
    }
}

extension NSManagedObjectContext: GenericAsyncQueue {
    
    public func performAsync(_ block: @escaping () -> ()) {
        self.performGroupedBlock(block)
    }
}

@objc public protocol PostLoginAuthenticationObserver: NSObjectProtocol {
    
    /// Invoked when the authentication has proven invalid
    @objc optional func authenticationInvalidated(_ error: NSError)
    
    /// Invoked when a client is successfully registered
    @objc optional func clientRegistrationDidSucceed()
    
    /// Invoken when there was an error registering the client
    @objc optional func clientRegistrationDidFail(_ error: NSError)
    
    /// Invoked when the client is deleted remotely
    @objc optional func didDetectSelfClientDeletion()
    
    /// Account was successfully deleted
    @objc optional func accountDeleted()
}

/// Authentication events that could happen after login
private enum PostLoginAuthenticationEvent {
    
    /// The cookie is not valid anymore
    case authenticationInvalidated(error: NSError)
    
    /// Client failed to register
    case clientRegistrationDidFail(error: NSError)
    
    /// Client registered client
    case clientRegistrationDidSucceed
    
    /// Client is deleted remotely
    case didDetectSelfClientDeletion
    
    /// Account was successfully deleted on the backend
    case accountDeleted
}

@objc public class PostLoginAuthenticationNotification : NSObject {
    
    static private let name = Notification.Name(rawValue: "PostLoginAuthenticationNotification")
    static private let eventKey = "event"
    
    fileprivate static func notify(event: PostLoginAuthenticationEvent, context: NSManagedObjectContext) {
        NotificationInContext(name: self.name, context: context.zm_userInterface, userInfo: [self.eventKey: event]).post()
    }
    
    @objc static public func addObserver(_ observer: PostLoginAuthenticationObserver, context: NSManagedObjectContext) -> Any {
        return NotificationInContext.addObserver(name: self.name, context: context.zm_userInterface)
        {
            [weak observer] note in
            guard let event = note.userInfo[eventKey] as? PostLoginAuthenticationEvent,
                let observer = observer else { return }
            
            switch event {
            case .authenticationInvalidated(let error):
                observer.authenticationInvalidated?(error)
            case .clientRegistrationDidFail(let error):
                observer.clientRegistrationDidFail?(error)
            case .didDetectSelfClientDeletion:
                observer.didDetectSelfClientDeletion?()
            case .clientRegistrationDidSucceed:
                observer.clientRegistrationDidSucceed?()
            case .accountDeleted:
                observer.accountDeleted?()
            }
            
        }
    }
    
}

public extension PostLoginAuthenticationNotification {
    
    static func notifyAuthenticationInvalidated(error: NSError, context: NSManagedObjectContext) {
        self.notify(event: .authenticationInvalidated(error: error), context: context)
    }
    
    @objc(notifyClientRegistrationDidSucceedInContext:)
    static func notifyClientRegistrationDidSucceed(context: NSManagedObjectContext) {
        self.notify(event: .clientRegistrationDidSucceed, context: context)
    }
    
    @objc(notifyDidDetectSelfClientDeletionInContext:)
    static func notifyDidDetectSelfClientDeletion(context: NSManagedObjectContext) {
        self.notify(event: .didDetectSelfClientDeletion, context: context)
    }

    static func notifyClientRegistrationDidFail(error: NSError, context: NSManagedObjectContext) {
        self.notify(event: .clientRegistrationDidFail(error: error), context: context)
    }
    
    @objc(notifyAccountDeletedInContext:)
    static func notifyAccountDeleted(context: NSManagedObjectContext) {
        self.notify(event: .accountDeleted, context: context)
    }
}
