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

let VoIPIdentifierSuffix = "-voip"
let TokenKey = "token"
let PushTokenPath = "/push/tokens"
private let zmLog = ZMSLog(tag: "Push")


extension ZMSingleRequestSync : ZMRequestGenerator {}

public class PushTokenStrategy : AbstractRequestStrategy, ZMSingleRequestTranscoder {
    
    fileprivate var pushKitTokenSync : ZMSingleRequestSync!
    fileprivate var pushKitTokenDeletionSync : ZMSingleRequestSync!
    
    var allRequestGenerators : [ZMRequestGenerator] {
        return [pushKitTokenSync, pushKitTokenDeletionSync]
    }

    public override init(withManagedObjectContext managedObjectContext: NSManagedObjectContext, applicationStatus: ApplicationStatus) {
        super.init(withManagedObjectContext: managedObjectContext, applicationStatus: applicationStatus)
        self.pushKitTokenSync = ZMSingleRequestSync(singleRequestTranscoder: self, groupQueue: managedObjectContext)
        self.pushKitTokenDeletionSync = ZMSingleRequestSync(singleRequestTranscoder: self, groupQueue: managedObjectContext)
    }
    
    func pushToken(forSingleRequestSync sync:ZMSingleRequestSync) -> ZMPushToken? {
        if (sync == pushKitTokenSync || sync == pushKitTokenDeletionSync) {
            return managedObjectContext.pushKitToken
        }
        preconditionFailure("Unknown sync")
    }
    
    func storePushToken(token: ZMPushToken?, forSingleRequestSync sync:ZMSingleRequestSync) {
        if (sync == pushKitTokenSync || sync == pushKitTokenDeletionSync) {
            managedObjectContext.pushKitToken = token;
        } else {
            preconditionFailure("Unknown sync")
        }
    }

    public override func nextRequestIfAllowed() -> ZMTransportRequest? {
        for generator in allRequestGenerators {
            if let request = generator.nextRequest() {
                return request
            }
        }
        return nil
    }
    
    public func request(for sync: ZMSingleRequestSync) -> ZMTransportRequest? {
        guard let token = pushToken(forSingleRequestSync: sync) else { return nil }
        
        if (token.isRegistered && !token.isMarkedForDeletion) {
            sync.resetCompletionState()
            return nil
        }
        
        // hex encode the token:
        let encodedToken = token.deviceToken.reduce(""){$0 + String(format: "%02hhx", $1)}
        if encodedToken.isEmpty {
            return nil
        }
        
        if (token.isMarkedForDeletion) {
            if (sync == pushKitTokenDeletionSync) {
                let path = PushTokenPath+"/"+encodedToken
                return ZMTransportRequest(path:path, method:.methodDELETE, payload:nil)
            }
        } else {
            var payload = [String: Any]()
            payload["token"] = encodedToken
            payload["app"] = token.appIdentifier
            payload["transport"] = token.transportType
            
            let selfUser = ZMUser.selfUser(in: managedObjectContext)
            if let userClientID = selfUser.selfClient()?.remoteIdentifier {
                payload["client"] = userClientID;
            }
            return ZMTransportRequest(path:PushTokenPath, method:.methodPOST, payload:payload as ZMTransportData?)
        }
        
        return nil;
    }
        
    public func didReceive(_ response: ZMTransportResponse, forSingleRequest sync: ZMSingleRequestSync) {
        if (sync == pushKitTokenDeletionSync) {
            finishDeletion(with: response, sync: sync)
        } else {
            finishUpdate(with: response, sync: sync)
        }
        // Need to call -save: to force a save, since nothing in the context will change:
        if !managedObjectContext.forceSaveOrRollback() {
            zmLog.error("Failed to save push token")
        }
        sync.resetCompletionState()
    }
    
    func finishDeletion(with response: ZMTransportResponse, sync: ZMSingleRequestSync) {
        if response.result == .success {
            if let token = pushToken(forSingleRequestSync:sync), token.isMarkedForDeletion {
                storePushToken(token:nil, forSingleRequestSync:sync)
            }
        } else if response.result == .permanentError {
            storePushToken(token:nil, forSingleRequestSync:sync)
        }
    }
    
    func finishUpdate(with response: ZMTransportResponse, sync: ZMSingleRequestSync) {
        let token = (response.result == .success) ? pushToken(with:response) : nil
        storePushToken(token:token, forSingleRequestSync:sync)
    }
    
    func pushToken(with response:ZMTransportResponse) -> ZMPushToken? {
        guard let payloadDictionary = response.payload as? [String: Any],
              let encodedToken = payloadDictionary["token"] as? String,
              let deviceToken = encodedToken.zmDeviceTokenData(),
              let identifier = payloadDictionary["app"] as? String,
              let transportType = payloadDictionary["transport"] as? String
        else { return nil }
        
        return ZMPushToken(deviceToken:deviceToken, identifier:identifier, transportType:transportType, isRegistered:true)
    }
}

extension PushTokenStrategy : ZMContextChangeTracker, ZMContextChangeTrackerSource {
    
    public var contextChangeTrackers: [ZMContextChangeTracker] {
        return [self]
    }
    
    public func objectsDidChange(_ object: Set<NSManagedObject>) {
        if let token = managedObjectContext.pushKitToken {
            if (token.isMarkedForDeletion){
                prepareNextRequestIfNeeded(for: pushKitTokenDeletionSync)
            } else if !token.isRegistered {
                prepareNextRequestIfNeeded(for: pushKitTokenSync)
            }
        }
    }
    
    func prepareNextRequestIfNeeded(for sync: ZMSingleRequestSync) {
        if (sync.status != .inProgress) {
            sync.readyForNextRequest()
            RequestAvailableNotification.notifyNewRequestsAvailable(self)
        }
    }
    
    public func fetchRequestForTrackedObjects() -> NSFetchRequest<NSFetchRequestResult>? {
        return nil
    }
    
    public func addTrackedObjects(_ objects: Set<NSManagedObject>) {
        // no-op
    }
    
}

extension PushTokenStrategy : ZMEventConsumer {
    
    public func processEvents(_ events: [ZMUpdateEvent], liveEvents: Bool, prefetchResult: ZMFetchRequestBatchResult?) {
        guard liveEvents else { return }
        
        events.forEach{process(updateEvent:$0)}
    }
    
    func process(updateEvent event: ZMUpdateEvent) {
        if event.type != .userPushRemove {
            return
        }
        // expected payload:
        // { "type: "user.push-remove",
        //   "token":
        //    { "transport": "APNS",
        //            "app": "name of the app",
        //          "token": "the token you get from apple"
        //    }
        // }
        // we ignore the payload and reregister both tokens whenever we receive a user.push-remove event
        managedObjectContext.pushKitToken = managedObjectContext.pushKitToken?.unregisteredCopy()
    }
}

