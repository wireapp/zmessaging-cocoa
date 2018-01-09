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

private let zmLog = ZMSLog(tag: "Services")


public extension ServiceUser {
    fileprivate func requestToAddService(to conversation: ZMConversation) -> ZMTransportRequest {
        guard let remoteIdentifier = conversation.remoteIdentifier else {
            fatal("conversation is not synced with the backend")
        }
        
        let path = "/conversations/\(remoteIdentifier.transportString())/bots"
        
        let payload: NSDictionary = ["provider": self.providerIdentifier,
                                     "service": self.serviceIdentifier,
                                     "locale": NSLocale.formattedLocaleIdentifier()]
        
        return ZMTransportRequest(path: path, method: .methodPOST, payload: payload as ZMTransportData)
    }
    
}

public extension ZMConversation {
    public func add(serviceUser: ServiceUser, in userSession: ZMUserSession, completion: ((Bool)->())?) {
        let request = serviceUser.requestToAddService(to: self)
        
        request.add(ZMCompletionHandler(on: userSession.managedObjectContext, block: { (response) in
            
            guard response.httpStatus == 201,
                  let responseDictionary = response.payload?.asDictionary(),
                  let userAddEventPayload = responseDictionary["event"] as? ZMTransportData,
                  let event = ZMUpdateEvent(fromEventStreamPayload: userAddEventPayload, uuid: nil) else {
                    zmLog.error("Wrong response for adding a bot: \(response)")
                    completion?(false)
                    return
            }
            
            completion?(true)
            
            userSession.syncManagedObjectContext.performGroupedBlock {
                // Process user added event
                userSession.operationLoop.syncStrategy.processUpdateEvents([event], ignoreBuffer: true)
            }
        }))
        
        // TODO: abusing search requests here
        userSession.transportSession.enqueueSearch(request)
    }
}

public extension ZMUserSession {
    public func startConversation(with serviceUser: ServiceUser, completion: ((ZMConversation?)->())?) {
        guard self.transportSession.reachability.mayBeReachable else {
            completion?(nil)
            return
        }
        
        let selfUser = ZMUser.selfUser(in: self.managedObjectContext)
        
        let conversation = ZMConversation.insertNewObject(in: self.managedObjectContext)
        conversation.lastModifiedDate = Date()
        conversation.conversationType = .group
        conversation.creator = selfUser
        conversation.team = selfUser.team
        var onCreatedRemotelyToken: NSObjectProtocol? = nil
        
        _ = onCreatedRemotelyToken // remove warning
        
        onCreatedRemotelyToken = conversation.onCreatedRemotely {
            conversation.add(serviceUser: serviceUser, in: self) { result in
                completion?(result ? conversation : nil)
                onCreatedRemotelyToken = nil
            }
        }

        self.managedObjectContext.saveOrRollback()
    }
}
