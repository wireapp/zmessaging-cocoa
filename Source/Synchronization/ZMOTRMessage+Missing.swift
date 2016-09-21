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


import Foundation

@objc public protocol SelfClientDeletionDelegate {
    
    /// Invoked when the self client needs to be deleted
    func deleteSelfClient()
}

/// HTTP status of a request that has
private let ClientNotAuthorizedResponseStatus = 403

/// Label for clients that are missing from the uploaded payload
private let MissingLabel = "missing"

/// Label for clients that were deleted and are still present in the uploaded payload
private let DeletedLabel = "deleted"

/// Label error for uploading a message with a client that does not exist
private let UnknownClientLabel = "unknown-client"

/// Error label
private let ErrorLabel = "label"

/// MARK: - Missing and deleted clients
extension ZMOTRMessage {
    
    /// Checks if the response for uploading this message contains a list of missing, deleted and reduntant clients
    /// If it does, updated the corresponding clients as needed (add/remove clients)
    /// - returns: whether the request needs to be retried (after missing messages are fetched)
    public func parseUploadResponse(_ response: ZMTransportResponse, clientDeletionDelegate: ZMClientClientRegistrationStatusProvider) -> Bool {
        
        // In case the self client got deleted remotely we will receive an event through the push channel and log out.
        // If we for some reason miss the push the BE will repond with a 403 and 'unknown-client' label to our
        // next sending attempt and we will logout and delete the current selfClient then
        if response.httpStatus == ClientNotAuthorizedResponseStatus,
            let payload = response.payload as? [String:AnyObject],
            let label = payload[ErrorLabel] as? String ,
            label == UnknownClientLabel
        {
            clientDeletionDelegate.didDetectCurrentClientDeletion()
            return false
        }
        
        guard let payload = response.payload as? [String:AnyObject] else { return false }
        
        if let deletedMap = payload[DeletedLabel] as? [String:AnyObject] {
            self.processDeletedClients(deletedMap)
        }
        
        if let missingMap = payload[MissingLabel] as? [String:AnyObject] {
            return self.processMissingClients(missingMap)
        } else {
            return false
        }
    }
    
    /// Parses the "missing" clients and creates the corresponding UserClients, then set them as missing
    /// - returns: true if there were any missing clients
    fileprivate func processMissingClients(_ missingMap: [String:AnyObject]) -> Bool {
        
        let allMissingClients = Set(missingMap.flatMap { pair -> [UserClient] in
            
            // user
            guard let userID = UUID(uuidString: pair.0) else { return []}
            let user = ZMUser(remoteID: userID, createIfNeeded: true, in: self.managedObjectContext!)!
            
            // client
            guard let clientIDs = pair.1 as? [String] else { fatal("Missing client ID is not parsed properly") }
            let clients = clientIDs.map { UserClient.fetchUserClient(withRemoteId: $0, forUser: user, createIfNeeded: true)! }
            
            // is this user not there?
            self.conversation?.checkIfMissingActiveParticipant(user)
            
            return clients
        })
        
        self.registersNewMissingClients(allMissingClients)
        return allMissingClients.count > 0
    }
    
    /// Adds clients to those missing for this message
    fileprivate func registersNewMissingClients(_ missingClients: Set<UserClient>) {
        guard missingClients.count > 0 else { return }
        
        let selfClient = ZMUser.selfUser(in: self.managedObjectContext!).selfClient()!
        selfClient.missesClients(missingClients)
        self.missesRecipients(missingClients)
        
        selfClient.addNewClientsToIgnored(missingClients, causedBy: self)

    }
    
    /// Parses the "deleted" clients and removes them
    fileprivate func processDeletedClients(_ deletedMap: [String:AnyObject]) {
        
        let allDeletedClients = Set(deletedMap.flatMap { pair -> [UserClient] in
            
            // user
            guard let userID = UUID(uuidString: pair.0) else { return [] }
            guard let user = ZMUser(remoteID: userID, createIfNeeded: false, in: self.managedObjectContext!) else { return [] }
            
            // clients
            guard let clientIDs = pair.1 as? [String] else { fatal("Deleted client ID is not parsed properly") }
            let clientIDsSet = Set(clientIDs)
            return user.clients.filter {
                guard let remoteIdentifier = $0.remoteIdentifier else { return false }
                return clientIDsSet.contains(remoteIdentifier)
            }
        })
        
        allDeletedClients.forEach {
            $0.deleteClientAndEndSession()
        }
    }

}

extension ZMConversation {
    
    /// If a missing client is not in this conversation, then we are out of sync with the BE
    /// and we should refetch
    fileprivate func checkIfMissingActiveParticipant(_ user: ZMUser) {
        // are we out of sync?
        guard !self.activeParticipants.contains(user) else { return }
        
        self.needsToBeUpdatedFromBackend = true
        if(self.conversationType == .oneOnOne || self.conversationType == .connection) {
            if(user.connection == nil) {
                if(self.connection == nil) {
                    user.connection = ZMConnection.insertNewObject(in: self.managedObjectContext!)
                    self.connection = user.connection
                } else {
                    user.connection = self.connection
                }
            }
        } else if (self.connection == nil) {
            self.connection = user.connection
        }
        user.connection?.needsToBeUpdatedFromBackend = true
    }
}
