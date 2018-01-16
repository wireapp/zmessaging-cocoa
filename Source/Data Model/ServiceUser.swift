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

public final class ServiceProvider: NSObject {
    public let identifier: String
    
    public let name:  String
    public let email: String
    public let url:   String
    public let providerDescription: String
    
    init?(payload: [AnyHashable: Any]) {
        guard let identifier  = payload["id"] as? String,
              let name        = payload["name"] as? String,
              let email       = payload["email"] as? String,
              let url         = payload["url"] as? String,
              let description = payload["description"] as? String
            else {
                return nil
            }
        self.identifier  = identifier
        self.name        = name
        self.email       = email
        self.url         = url
        self.providerDescription = description
        
        super.init()
    }
}

public final class ServiceDetails: NSObject {
    public let serviceIdentifier:  String
    public let providerIdentifier: String
    
    public let name: String
    public let serviceDescription: String
    public let assets: [[String: Any]]
    public let tags: [String]
    
    init?(payload: [AnyHashable: Any]) {
        guard let serviceIdentifier   = payload["id"] as? String,
              let providerIdentifier  = payload["provider"] as? String,
              let name                = payload["name"] as? String,
              let description         = payload["description"] as? String,
              let assets              = payload["assets"] as? [[String: Any]],
              let tags                = payload["tags"] as? [String]
            else {
                return nil
            }
        
        self.serviceIdentifier  = serviceIdentifier
        self.providerIdentifier = providerIdentifier
        self.name               = name
        self.serviceDescription = description
        self.assets             = assets
        self.tags               = tags

        super.init()
    }
}


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
    
    fileprivate func requestToFetchProvider() -> ZMTransportRequest {
        let path = "/providers/\(self.providerIdentifier)/"
        return ZMTransportRequest(path: path, method: .methodGET, payload: nil)
    }
    
    fileprivate func requestToFetchDetails() -> ZMTransportRequest {
        let path = "/providers/\(self.providerIdentifier)/services/\(self.serviceIdentifier)"
        return ZMTransportRequest(path: path, method: .methodGET, payload: nil)
    }
}

public extension ServiceUser {
    public func fetchProvider(in userSession: ZMUserSession, completion: @escaping (ServiceProvider?)->()) {
        let request = self.requestToFetchProvider()
        
        request.add(ZMCompletionHandler(on: userSession.managedObjectContext, block: { (response) in
            
            guard response.httpStatus == 200,
                let responseDictionary = response.payload?.asDictionary(),
                let provider = ServiceProvider(payload: responseDictionary) else {
                    zmLog.error("Wrong response for fetching a provider: \(response)")
                    completion(nil)
                    return
            }
            
            completion(provider)
        }))
        
        userSession.transportSession.enqueueOneTime(request)
    }
    
    public func fetchDetails(in userSession: ZMUserSession, completion: @escaping (ServiceDetails?)->()) {
        let request = self.requestToFetchDetails()
        
        request.add(ZMCompletionHandler(on: userSession.managedObjectContext, block: { (response) in
            
            guard response.httpStatus == 200,
                let responseDictionary = response.payload?.asDictionary(),
                let serviceDetails = ServiceDetails(payload: responseDictionary) else {
                    zmLog.error("Wrong response for fetching a service: \(response)")
                    completion(nil)
                    return
            }
            
            completion(serviceDetails)
        }))
        
        userSession.transportSession.enqueueOneTime(request)
    }
}

public enum AddBotError: Int, Error {
    case offline
    case general
    /// In case the conversation is already full, the backend is going to refuse to add the bot to the conversation.
    case tooManyParticipants
    /// The bot service is not responding to wire backend.
    case botNotResponding
    /// The bot rejected to be added to the conversation.
    case botRejected
}

public enum AddBotResult {
    case success(conversation: ZMConversation)
    case failure(error: AddBotError)
}

public extension ZMConversation {
    public func add(serviceUser: ServiceUser, in userSession: ZMUserSession, completion: ((AddBotError?)->())?) {
        let request = serviceUser.requestToAddService(to: self)
        
        request.add(ZMCompletionHandler(on: userSession.managedObjectContext, block: { (response) in
            
            guard response.httpStatus == 201,
                  let responseDictionary = response.payload?.asDictionary(),
                  let userAddEventPayload = responseDictionary["event"] as? ZMTransportData,
                  let event = ZMUpdateEvent(fromEventStreamPayload: userAddEventPayload, uuid: nil) else {
                    zmLog.error("Wrong response for adding a bot: \(response)")
                    completion?(AddBotError.general) // TODO: differentiate the possible errors
                    return
            }
            
            completion?(nil)
            
            userSession.syncManagedObjectContext.performGroupedBlock {
                // Process user added event
                userSession.operationLoop.syncStrategy.processUpdateEvents([event], ignoreBuffer: true)
            }
        }))
        
        userSession.transportSession.enqueueOneTime(request)
    }
}

public extension ZMUserSession {
    public func startConversation(with serviceUser: ServiceUser, completion: ((AddBotResult)->())?) {
        guard self.transportSession.reachability.mayBeReachable else {
            completion?(AddBotResult.failure(error: .offline))
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
            conversation.add(serviceUser: serviceUser, in: self) { error in
                if let error = error {
                    completion?(AddBotResult.failure(error: error))
                }
                else {
                    completion?(AddBotResult.success(conversation: conversation))
                }
                onCreatedRemotelyToken = nil
            }
        }

        self.managedObjectContext.saveOrRollback()
    }
}
