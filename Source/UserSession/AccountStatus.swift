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

public enum AccountState : UInt {
    case activated
    case newDevice // we want to show "you are using a new device"
    case deactivated // we want to show "you are using this device again"
}

public final class AccountStatus : NSObject, ZMInitialSyncCompletionObserver {

    let managedObjectContext: NSManagedObjectContext
    var authenticationToken : Any?
    var initialSyncToken: Any?
    
    public fileprivate (set) var accountState : AccountState = .activated
    
    public func initialSyncCompleted() {
        self.managedObjectContext.performGroupedBlock {
            if self.accountState == .deactivated || self.accountState == .newDevice {
                self.appendMessage(self.accountState)
                self.managedObjectContext.saveOrRollback()
            }
            self.accountState = .activated
        }
    }
    
    public func didCompleteLogin() {
        if !self.managedObjectContext.registeredOnThisDeviceBeforeConversationInitialization {
            accountState = .deactivated
        }
    }
    
    func didRegisterClient() {
        self.managedObjectContext.performGroupedBlock {
            if !self.managedObjectContext.registeredOnThisDeviceBeforeConversationInitialization {
                self.accountState = .newDevice
            }
            self.managedObjectContext.registeredOnThisDeviceBeforeConversationInitialization = false
        }
    }
    
    func appendMessage(_ state: AccountState) {
        let convRequest = NSFetchRequest<ZMConversation>(entityName:ZMConversation.entityName())
        let conversations = managedObjectContext.fetchOrAssert(request: convRequest)
        
        conversations.forEach{
            guard $0.conversationType == .oneOnOne || $0.conversationType == .group else { return }
            switch state {
            case .deactivated:
                $0.appendContinuedUsingThisDeviceMessage()
            case .newDevice:
                $0.appendStartedUsingThisDeviceMessage()
            default:
                return
            }
        }
    }
    
    @objc public init(managedObjectContext: NSManagedObjectContext) {
        self.managedObjectContext = managedObjectContext
        
        super.init()
        
        self.initialSyncToken = ZMUserSession.addInitialSyncCompletionObserver(self, context: managedObjectContext)
        self.authenticationToken = PostLoginAuthenticationNotification.addObserver(self, context: managedObjectContext)
    }
}

extension AccountStatus : PostLoginAuthenticationObserver {
    
    public func clientRegistrationDidSucceed(accountId: UUID) {
        didRegisterClient()
    }
    
}
