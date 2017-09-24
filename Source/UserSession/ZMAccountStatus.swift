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


import WireTransport
import WireDataModel

@objc public enum AccountState : UInt {
    case newDeviceNewAccount // we don't want to show any system message
    case newDeviceExistingAccount // we want to show "you are using a new device"
    case oldDeviceDeactivatedAccount // we want to show "you are using this device again"
    case oldDeviceActiveAccount // we don't want to show any system message
}


@objc public protocol ZMCookieProvider : NSObjectProtocol {
    var data : Data? { get }
}

extension ZMPersistentCookieStorage : ZMCookieProvider {
    public var data : Data? {
        return authenticationCookieData
    }
}

public final class ZMAccountStatus : NSObject, ZMInitialSyncCompletionObserver {

    let managedObjectContext: NSManagedObjectContext
    let cookieProvider : ZMCookieProvider
    var authenticationToken : Any?
    var registrationToken : Any?
    var initialSyncToken: Any?
    
    public fileprivate (set) var currentAccountState : AccountState = .newDeviceNewAccount
    
    public lazy var hadHistoryBeforeLogin : Bool = {
        let convRequest = NSFetchRequest<ZMConversation>(entityName:ZMConversation.entityName())
        guard let convCount = try? self.managedObjectContext.count(for: convRequest) else { return false }
        let hasHistory = convCount > 1
        return hasHistory
    }()
    
    var hasCookie : Bool {
        return cookieProvider.data != nil
    }
    
    public func initialSyncCompleted() {
        self.managedObjectContext.performGroupedBlock {
            if self.currentAccountState == .oldDeviceDeactivatedAccount || self.currentAccountState == .newDeviceExistingAccount {
                self.appendMessage(self.currentAccountState)
                self.managedObjectContext.saveOrRollback()
            }
            self.currentAccountState = .oldDeviceActiveAccount
        }
    }
    
    func didRegisterClient() {
        self.managedObjectContext.performGroupedBlock {
            if self.currentAccountState == .newDeviceNewAccount && !self.managedObjectContext.registeredOnThisDeviceBeforeConversationInitialization {
                self.currentAccountState = .newDeviceExistingAccount
            }
            self.managedObjectContext.registeredOnThisDeviceBeforeConversationInitialization = false
        }
    }
    
    func failedToAuthenticate() {
        self.managedObjectContext.performGroupedBlock {
            if self.currentAccountState == .oldDeviceActiveAccount && !self.hasCookie {
                self.currentAccountState = .oldDeviceDeactivatedAccount
            }
        }
    }
    
    func appendMessage(_ state: AccountState){
        let convRequest = NSFetchRequest<ZMConversation>(entityName:ZMConversation.entityName())
        let conversations = managedObjectContext.fetchOrAssert(request: convRequest)
        
        conversations.forEach{
            guard $0.conversationType == .oneOnOne || $0.conversationType == .group else { return }
            switch state {
            case .oldDeviceDeactivatedAccount:
                $0.appendContinuedUsingThisDeviceMessage()
            case .newDeviceExistingAccount:
                $0.appendStartedUsingThisDeviceMessage()
            default:
                return
            }
        }
    }
    
    @objc public init(managedObjectContext: NSManagedObjectContext, cookieStorage: ZMCookieProvider) {
        self.managedObjectContext = managedObjectContext
        self.cookieProvider = cookieStorage
        
        super.init()
        
        switch (hasCookie, hadHistoryBeforeLogin) {
        case (true, true):
            currentAccountState = .oldDeviceActiveAccount
        case (false, true):
            currentAccountState = .oldDeviceDeactivatedAccount
        case (false, false):
            currentAccountState = .newDeviceNewAccount
        case (true, false):
            currentAccountState = .newDeviceNewAccount 
        }
                
        self.initialSyncToken = ZMUserSession.addInitialSyncCompletionObserver(self, context: managedObjectContext)
        self.authenticationToken = PostLoginAuthenticationNotification.addObserver(self, context: managedObjectContext)
    }
}

extension ZMAccountStatus : PostLoginAuthenticationObserver {
    
    public func authenticationInvalidated(_ error: NSError) {
        failedToAuthenticate()
    }
    
    public func clientRegistrationDidSucceed(accountId: UUID) {
        didRegisterClient()
    }
}
