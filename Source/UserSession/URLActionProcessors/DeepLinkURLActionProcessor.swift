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
    var transportSession: TransportSessionType
    var eventProcessor: UpdateEventProcessor

    init(contextprovider: ContextProvider,
         transportSession: TransportSessionType,
         eventProcessor: UpdateEventProcessor) {
        self.uiMOC = contextprovider.viewContext
        self.syncMOC = contextprovider.syncContext
        self.transportSession = transportSession
        self.eventProcessor = eventProcessor
    }
    
    func process(urlAction: URLAction, delegate: PresentationDelegate?) {
        switch urlAction {
        case let .joinConversation(key: key, code: code):
            delegate?.shouldPerformAction(urlAction) { [weak self] shouldJoin in
                guard shouldJoin, let strongSelf = self else { return }
                ZMConversation.join(key: key,
                                    code: code,
                                    transportSession: strongSelf.transportSession,
                                    eventProcessor: strongSelf.eventProcessor,
                                    moc: strongSelf.syncMOC) { (result) in
                    switch result {
                    case .success(let conversation):
                        delegate?.showConversation(conversation, at: nil)
                    case .failure(let error) :
                        delegate?.failedToPerformAction(urlAction, error: error)
                    }
                    delegate?.completedURLAction(urlAction)
                }
            }
            
        case .openConversation(let id):
            guard let conversation = ZMConversation(remoteID: id, createIfNeeded: false, in: uiMOC) else {
                delegate?.failedToPerformAction(urlAction, error: DeepLinkRequestError.invalidConversationLink)
                return
            }
            
            delegate?.showConversation(conversation, at: nil)
            delegate?.completedURLAction(urlAction)

        case .openUserProfile(let id):
            if let user = ZMUser(remoteID: id, createIfNeeded: false, in: uiMOC) {
                delegate?.showUserProfile(user: user)
            } else {
                delegate?.showConnectionRequest(userId: id)
            }

            delegate?.completedURLAction(urlAction)
            
        default:
            delegate?.completedURLAction(urlAction)
        }
    }
}
