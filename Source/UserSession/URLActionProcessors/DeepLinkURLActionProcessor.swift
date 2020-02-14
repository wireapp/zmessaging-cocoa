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

class DeepLinkURLActionProcessor: URLActionProcessor {
    
    var uiMOC: NSManagedObjectContext
    var syncMOC: NSManagedObjectContext
    weak var showContentDelegate: ShowContentDelegate?
    
    init(contextProvider: ZMManagedObjectContextProvider, showContentdelegate: ShowContentDelegate?) {
        self.uiMOC = contextProvider.managedObjectContext
        self.syncMOC = contextProvider.syncManagedObjectContext
        self.showContentDelegate = showContentdelegate
    }
    
    func process(urlAction: URLAction, delegate: URLActionDelegate?) {
        switch urlAction {
            
        case .openConversation(let id):
            guard let conversation = ZMConversation(remoteID: id, createIfNeeded: false, in: uiMOC) else {
                delegate?.failedToPerformAction(urlAction, error: DeepLinkRequestError.invalidConversationLink)
                return
            }
            
            showContentDelegate?.showConversation(conversation, at: nil)
        case .openUserProfile(let id):
            if let user = ZMUser(remoteID: id, createIfNeeded: false, in: uiMOC) {
                showContentDelegate?.showUserProfile(user: user)
            } else {
                showContentDelegate?.showConnectionRequest(userId: id)
            }
            
        default:
            break
        }
        
        delegate?.completedURLAction(urlAction)
    }
    
}
