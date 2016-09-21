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
import ZMCSystem
import ZMTransport
import ZMUtilities
import Cryptobox
import ZMCDataModel

private let zmLog = ZMSLog(tag: "Crypto")

struct MissingClientsRequestUserInfoKeys {
    static let clients = "clients"
}

public extension UserClient {
    public override class func predicateForObjectsThatNeedToBeUpdatedUpstream() -> NSPredicate {
        let baseModifiedPredicate = super.predicateForObjectsThatNeedToBeUpdatedUpstream()
        let remoteIdentifierPresentPredicate = NSPredicate(format: "\(ZMUserClientRemoteIdentifierKey) != nil")
        let notDeletedPredicate = NSPredicate(format: "\(ZMUserClientMarkedToDeleteKey) == NO")

        let modifiedPredicate = NSCompoundPredicate(andPredicateWithSubpredicates:[
            baseModifiedPredicate!,
            notDeletedPredicate,
            remoteIdentifierPresentPredicate
            ])
        return modifiedPredicate
    }
}


// Register new client, update it with new keys, deletes clients.
@objc
public final class MissingClientsRequestStrategy: ZMObjectSyncStrategy, ZMObjectStrategy, ZMUpstreamTranscoder {
    
    weak var clientRegistrationStatus: ZMClientRegistrationStatus?
    weak var apnsConfirmationStatus: BackgroundAPNSConfirmationStatus?

    fileprivate(set) var modifiedSync: ZMUpstreamModifiedObjectSync! = nil
    public var requestsFactory = MissingClientsRequestFactory()
    
    public init(clientRegistrationStatus:ZMClientRegistrationStatus,
                apnsConfirmationStatus: BackgroundAPNSConfirmationStatus,
                managedObjectContext: NSManagedObjectContext)
    {
        self.apnsConfirmationStatus = apnsConfirmationStatus
        self.clientRegistrationStatus = clientRegistrationStatus
        super.init(managedObjectContext: managedObjectContext)
        
        self.modifiedSync = ZMUpstreamModifiedObjectSync(transcoder: self, entityName: UserClient.entityName(), update: modifiedPredicate(), filter: nil, keysToSync: [ZMUserClientMissingKey], managedObjectContext: managedObjectContext)
    }
    
    func modifiedPredicate() -> NSPredicate {
        let baseModifiedPredicate = UserClient.predicateForObjectsThatNeedToBeUpdatedUpstream()
        let missingClientsPredicate = NSPredicate(format: "\(ZMUserClientMissingKey).@count > 0")
        
        let modifiedPredicate = NSCompoundPredicate(andPredicateWithSubpredicates:[
            baseModifiedPredicate,
            missingClientsPredicate,
            ])
        return modifiedPredicate
    }
    
    public func nextRequest() -> ZMTransportRequest? {
        guard let clientStatus = clientRegistrationStatus , clientStatus.currentPhase == .registered
        else { return nil }
        
        return modifiedSync.nextRequest()
    }
    
    public var contextChangeTrackers: [ZMContextChangeTracker] {
        return [modifiedSync]
    }
    
    public var hasOutstandingItems : Bool {
        return modifiedSync.hasOutstandingItems
    }
    public func shouldProcessUpdatesBeforeInserts() -> Bool {
        return false
    }
    
    public func shouldCreateRequest(toSyncObject managedObject: ZMManagedObject, forKeys keys: Set<String>, withSync sync: Any) -> Bool {
        
        var keysToSync = keys
        if keys.contains(ZMUserClientMissingKey),
            let client = managedObject as? UserClient , (client.missingClients == nil || client.missingClients?.count == 0)
        {
            keysToSync.remove(ZMUserClientMissingKey)
            client.resetLocallyModifiedKeys(Set(arrayLiteral: ZMUserClientMissingKey))
            modifiedSync.objectsDidChange(Set(arrayLiteral: client))
        }
        return (keysToSync.count > 0)
    }
    
    public func request(forUpdating managedObject: ZMManagedObject, forKeys keys: Set<String>) -> ZMUpstreamRequest? {
        guard let client = managedObject as? UserClient
        else { fatal("Called requestForUpdatingObject() on \(managedObject) to sync keys: \(keys)") }
        
        guard keys.contains(ZMUserClientMissingKey)
        else { fatal("Unknown keys to sync (\(keys))") }
        
        guard let missing = client.missingClients , missing.count > 0
        else { fatal("no missing clients found") }
        
        let request = requestsFactory.fetchMissingClientKeysRequest(missing)
        if let confStatus = apnsConfirmationStatus , confStatus.needsToSyncMessages {
            request?.transportRequest.forceToVoipSession()
        }
        return request
    }
    
    /// Returns whether synchronization of this object needs additional requests
    public func updateUpdatedObject(_ managedObject: ZMManagedObject, requestUserInfo: [AnyHashable: Any]?, response: ZMTransportResponse, keysToParse: Set<String>) -> Bool {
        
        if keysToParse.contains(ZMUserClientMissingKey) {
            return processResponseForUpdatingMissingClients(managedObject, requestUserInfo: requestUserInfo, responsePayload: response.payload)
        }
        return false
    }
    
    /// Make sure that we don't block messages or continue requesting messages for a client that can not be fetched
    fileprivate func clearMissingMessagesBecauseClientCanNotBeFeched(_ client: UserClient, selfClient: UserClient) {
        client.failedToEstablishSession = true
        cleanMessagesMissingRecipient(client)
        selfClient.removeMissingClient(client)
    }
    
    /**
     Creates session and update missing clients and messages that depend on those clients
     */
    fileprivate func establishSessionAndUpdateMissingClients(_ clientId: String,
                                                         prekeyString: String,
                                                         selfClient: UserClient,
                                                         missingClient: UserClient?) {
        guard let missingClient = missingClient else { return }
        
        let sessionCreated = selfClient.establishSessionWithClient(missingClient, usingPreKey: prekeyString)
        // If the session creation failed, the client probably has corrupted prekeys,
        // we mark the client in order to send him a bogus message and not block all requests
        missingClient.failedToEstablishSession = !sessionCreated
        
        cleanMessagesMissingRecipient(missingClient)
        selfClient.removeMissingClient(missingClient)
    }
    
    /// Process a client entry in a response to a missed clients (prekeys) request
    fileprivate func processPrekeyEntry(_ clientId: String, prekeyData: Any?, selfClient: UserClient, missingClient: UserClient) {
        if let prekeyDictionary = prekeyData as? [String : AnyObject],
            let prekeyString = prekeyDictionary["key"] as? String
        {
            establishSessionAndUpdateMissingClients(
                clientId,
                prekeyString: prekeyString,
                selfClient: selfClient,
                missingClient:missingClient)
        }
        else {
            clearMissingMessagesBecauseClientCanNotBeFeched(missingClient, selfClient: selfClient)
        }
    }
    
    /// - returns: a lookup table for missing client by remote client ID
    fileprivate func missingUserClientIdToUserClientMap(_ selfClient: UserClient) -> [String : UserClient] {
        var missedClientIdsToClientsMap = [String : UserClient]()
        guard let missingClients = selfClient.missingClients else {
            return missedClientIdsToClientsMap
        }
        
        missingClients.forEach {
            if let remoteIdentifier = $0.remoteIdentifier {
                missedClientIdsToClientsMap[remoteIdentifier] = $0
            }
        }
        return missedClientIdsToClientsMap
    }
    
    /**
     Processes a response to a request to fetch missing client
     The response will contain clientid and prekeys in the following format:
     {
        <userId> : {
            <clientId> : {
                        key : <index>,
                        id : <prekey>
                        },
            <clientId> : {
                        key : <index>,
                        id : <prekey>
                        },
            ...
        }
        <userId> : {
            <clientId> : null   // this will happen in case the
                                // client was deleted just before we requested it
        }
     }
    */
    fileprivate func processResponseForUpdatingMissingClients(
        _ managedObject: ZMManagedObject!,
        requestUserInfo: [AnyHashable: Any]!,
        responsePayload payload: ZMTransportData!) -> Bool {
        
        guard let dictionary = payload.asDictionary() as? [String : [String : AnyObject]],
            let selfClient = ZMUser.selfUser(in: managedObjectContext).selfClient()
            else {
                zmLog.error("Response payload for client-keys is not a valid [String : [String : AnyObject]]")
                return false
        }
        
        let missedClientLookupByRemoteIdentifier = missingUserClientIdToUserClientMap(selfClient)
        
        /// client IDs that are still remaining to download. Will be updated (removed) as we discover more clients in the payload
        var remainingClientsIds = Set((requestUserInfo[MissingClientsRequestUserInfoKeys.clients] as! [String]).filter {
            missedClientLookupByRemoteIdentifier[$0] != nil // I will not consider the clients that are not missing anymore
            // as still to download
            })
        let originalRemainingClientsCount = remainingClientsIds.count
        
        /// for each user ID
        for (userIdString, clients) in dictionary {
            guard let _ = UUID(uuidString: userIdString) else {
                zmLog.error("\(userIdString) is not a valid UUID")
                continue
            }
            
            /// for each client ID
            for (clientId, prekeyData) in clients {
                remainingClientsIds.remove(clientId)
                
                guard let missedClient = missedClientLookupByRemoteIdentifier[clientId] else {
                    /// If the client id is not missing (anymore), we should not do anything.
                    /// maybe a previous request solved it, or it was deleted by a push, or...
                    continue
                }
                processPrekeyEntry(clientId, prekeyData: prekeyData, selfClient: selfClient, missingClient: missedClient)
            }
        }
        
        // check if this request actually changed something. If not, it means that the requested client ids
        // are deleted on the BE side and we should ignore them
        
        let remainingClientsCountDidNotChange = (remainingClientsIds.count == originalRemainingClientsCount)
        if remainingClientsCountDidNotChange {
            remainingClientsIds.forEach {
                if let client = missedClientLookupByRemoteIdentifier[$0] {
                    clearMissingMessagesBecauseClientCanNotBeFeched(client, selfClient: selfClient)
                }
            }
        }
        
        
        return (selfClient.missingClients?.count ?? 0) > 0 // we are done
    }
    
    fileprivate func expireMessagesMissingRecipient(_ client: UserClient) {
        guard let messagesMissingRecipient = client.messagesMissingRecipient else { return }
        messagesMissingRecipient.forEach { $0.expire() }
    }
    
    fileprivate func cleanMessagesMissingRecipient(_ client: UserClient) {
        guard let messagesMissingRecipient = client.messagesMissingRecipient else { return }
        messagesMissingRecipient.forEach {
            if let message = $0 as? ZMOTRMessage {
                message.doesNotMissRecipient(client)
            }
            else {
                client.mutableSetValue(forKey: "messagesMissingRecipient").remove($0)
            }
        }
    }
    
    
    // MARK - Unused functions
    
    
    public func request(forInserting managedObject: ZMManagedObject, forKeys keys: Set<String>?) -> ZMUpstreamRequest? {
        return nil
    }
    
    
    
    public func updateInsertedObject(_ managedObject: ZMManagedObject, request upstreamRequest: ZMUpstreamRequest, response: ZMTransportResponse) {
        // no op
    }
    
    // Should return the objects that need to be refetched from the BE in case of upload error
    public func objectToRefetchForFailedUpdate(of managedObject: ZMManagedObject) -> ZMManagedObject? {
        return nil
    }
    
    public var isSlowSyncDone: Bool {
        return true
    }
    
    public func setNeedsSlowSync() {
        //no op
    }
    
    public func processEvents(_ events: [ZMUpdateEvent], liveEvents: Bool, prefetchResult: ZMFetchRequestBatchResult?) {
        //no op
    }
    
    public var requestGenerators: [ZMRequestGenerator] {
        return []
    }
}




