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
import WireDataModel

let VoIPIdentifierSuffix = "-voip"
let TokenKey = "token"
let PushTokenPath = "/push/tokens"
private let zmLog = ZMSLog(tag: "Push")


extension ZMSingleRequestSync : ZMRequestGenerator {}

public class PushTokenStrategy : AbstractRequestStrategy {

    enum Keys {
        static let UserClientPushTokenKey = "pushToken"
        static let RequestTypeKey = "requestType"
    }

    enum RequestType: String {
        case getToken
        case postToken
        case deleteToken
    }


    fileprivate var pushKitTokenSync : ZMUpstreamModifiedObjectSync!

    var allRequestGenerators : [ZMRequestGenerator] {
        return [pushKitTokenSync]
    }

    private func modifiedPredicate() -> NSPredicate {
        return UserClient.predicateForObjectsThatNeedToBeUpdatedUpstream()
    }

    public override init(withManagedObjectContext managedObjectContext: NSManagedObjectContext, applicationStatus: ApplicationStatus) {
        super.init(withManagedObjectContext: managedObjectContext, applicationStatus: applicationStatus)
        self.pushKitTokenSync = ZMUpstreamModifiedObjectSync(transcoder: self, entityName: UserClient.entityName(), update: modifiedPredicate(), filter: nil, keysToSync: [Keys.UserClientPushTokenKey], managedObjectContext: managedObjectContext)
    }
    
//    func pushToken(forSingleRequestSync sync: ZMSingleRequestSync) -> ZMPushToken? {
//        if (sync == pushKitTokenSync || sync == pushKitTokenDeletionSync) {
//            return managedObjectContext.pushKitToken
//        }
//        preconditionFailure("Unknown sync")
//    }

//    func storePushToken(token: ZMPushToken?, forSingleRequestSync sync: ZMSingleRequestSync) {
//        if (sync == pushKitTokenSync || sync == pushKitTokenDeletionSync) {
//            managedObjectContext.pushKitToken = token;
//        } else {
//            preconditionFailure("Unknown sync")
//        }
//    }

    public override func nextRequestIfAllowed() -> ZMTransportRequest? {
        return pushKitTokenSync.nextRequest()
    }

//    public func request(forUpdating managedObject: ZMManagedObject, forKeys keys: Set<String>) -> ZMUpstreamRequest? {
//        guard let client = managedObject as? UserClient else { return nil }
//        guard client.isSelfClient() else { return nil }
//        guard let pushToken = client.pushToken else { return nil }
//
//        if pushToken.isMarkedForDeletion {
//            let request = ZMTransportRequest(path: "\(PushTokenPath)/\(pushToken.transportString)", method: .methodDELETE, payload: nil)
//            return ZMUpstreamRequest(transportRequest: request)
//        }
//
//    }

    public func request(for sync: ZMSingleRequestSync) -> ZMTransportRequest? {
//        if sync === pushKitTokensDownloadSync {
//            return ZMTransportRequest(path:PushTokenPath, method:.methodGET, payload:nil)
//        }
//
//        guard let token = pushToken(forSingleRequestSync: sync) else { return nil }
//
//        if (token.isRegistered && !token.isMarkedForDeletion) {
//            sync.resetCompletionState()
//            return nil
//        }
//
//        // hex encode the token:
//        let encodedToken = token.deviceToken.reduce(""){$0 + String(format: "%02hhx", $1)}
//        if encodedToken.isEmpty {
//            return nil
//        }
//
//        if (token.isMarkedForDeletion) {
//            if (sync == pushKitTokenDeletionSync) {
//                let path = PushTokenPath+"/"+encodedToken
//                return ZMTransportRequest(path:path, method:.methodDELETE, payload:nil)
//            }
//        } else {
//            var payload = [String: Any]()
//            payload["token"] = encodedToken
//            payload["app"] = token.appIdentifier
//            payload["transport"] = token.transportType
//
//            let selfUser = ZMUser.selfUser(in: managedObjectContext)
//            if let userClientID = selfUser.selfClient()?.remoteIdentifier {
//                payload["client"] = userClientID;
//            }
//            return ZMTransportRequest(path:PushTokenPath, method:.methodPOST, payload:payload as ZMTransportData?)
//        }

        return nil;
    }
        
//    public func didReceive(_ response: ZMTransportResponse, forSingleRequest sync: ZMSingleRequestSync) {
//        if (sync == pushKitTokensDownloadSync) {
//
//        } else if (sync == pushKitTokenDeletionSync) {
//            finishDeletion(with: response, sync: sync)
//        } else {
//            finishUpdate(with: response, sync: sync)
//        }
//        // Need to call -save: to force a save, since nothing in the context will change:
//        if !managedObjectContext.forceSaveOrRollback() {
//            zmLog.error("Failed to save push token")
//        }
//        sync.resetCompletionState()
//    }
//
//    func finishDeletion(with response: ZMTransportResponse, sync: ZMSingleRequestSync) {
//        if response.result == .success {
//            if let token = pushToken(forSingleRequestSync:sync), token.isMarkedForDeletion {
//                storePushToken(token:nil, forSingleRequestSync:sync)
//            }
//        } else if response.result == .permanentError {
//            storePushToken(token:nil, forSingleRequestSync:sync)
//        }
//    }
//
//    func finishUpdate(with response: ZMTransportResponse, sync: ZMSingleRequestSync) {
//        let token = (response.result == .success) ? pushToken(with:response) : nil
//        storePushToken(token:token, forSingleRequestSync:sync)
//    }
//
//    func pushToken(with response:ZMTransportResponse) -> ZMPushToken? {
//        guard let payloadDictionary = response.payload as? [String: Any],
//              let encodedToken = payloadDictionary["token"] as? String,
//              let deviceToken = encodedToken.zmDeviceTokenData(),
//              let identifier = payloadDictionary["app"] as? String,
//              let transportType = payloadDictionary["transport"] as? String
//        else { return nil }
//
//        return ZMPushToken(deviceToken:deviceToken, identifier:identifier, transportType:transportType, isRegistered:true)
//    }
}

extension PushTokenStrategy : ZMUpstreamTranscoder {

    public func request(forUpdating managedObject: ZMManagedObject, forKeys keys: Set<String>) -> ZMUpstreamRequest? {
        guard let client = managedObject as? UserClient else { return nil }
        guard client.isSelfClient() else { return nil }
        guard let clientIdentifier = client.remoteIdentifier else { return nil }
        guard let pushToken = client.pushToken else { return nil }

        let request: ZMTransportRequest
        let requestType: RequestType

        if pushToken.isMarkedForDeletion {
            request = ZMTransportRequest(path: "\(PushTokenPath)/\(pushToken.deviceTokenString)", method: .methodDELETE, payload: nil)
            requestType = .deleteToken
        } else if pushToken.isMarkedForDownload {
            request = ZMTransportRequest(path: "\(PushTokenPath)", method: .methodGET, payload: nil)
            requestType = .getToken
        } else if !pushToken.isRegistered {
            let tokenPayload = PushTokenPayload(pushToken: pushToken, clientIdentifier: clientIdentifier)
            let payload = try! JSONEncoder().encode(tokenPayload)
            let payloadString = String(data: payload, encoding: .utf8) as NSString?
            request = ZMTransportRequest(path: "\(PushTokenPath)", method: .methodPOST, payload: payloadString)
            requestType = .postToken
        } else {
            return nil
        }

        return ZMUpstreamRequest(keys: [Keys.UserClientPushTokenKey], transportRequest: request, userInfo: [Keys.RequestTypeKey : requestType.rawValue])
    }

    public func request(forInserting managedObject: ZMManagedObject, forKeys keys: Set<String>?) -> ZMUpstreamRequest? {
        return nil
    }

    public func updateInsertedObject(_ managedObject: ZMManagedObject, request upstreamRequest: ZMUpstreamRequest, response: ZMTransportResponse) {

    }

    public func updateUpdatedObject(_ managedObject: ZMManagedObject, requestUserInfo: [AnyHashable : Any]? = nil, response: ZMTransportResponse, keysToParse: Set<String>) -> Bool {
        guard let client = managedObject as? UserClient else { return false }
        guard client.isSelfClient() else { return false }
        guard let pushToken = client.pushToken else { return false }
        guard let userInfo = requestUserInfo as? [String : String] else { return false }
        guard let requestTypeValue = userInfo[Keys.RequestTypeKey], let requestType = RequestType(rawValue: requestTypeValue) else { return false }

        switch requestType {
        case .postToken:
            var token = pushToken.resetFlags()
            token.isRegistered = true
            client.pushToken = token
            return false
        case .deleteToken:
            // The token might have changed in the meantime, check if it's still up for deletion"xeJOQeTUMpA3koRJNJSHVH7xTxYsd67jqo4So5yNsdU=
            if let token = client.pushToken, token.isMarkedForDeletion {
                client.pushToken = nil
            }
            return false
        case .getToken:
            guard let responseData = response.rawData else { return false }
            guard let tokens = try? JSONDecoder().decode([PushTokenPayload].self, from: responseData) else { return false }

            // Find tokens belonging to self client
            let current = tokens.filter { $0.client == client.remoteIdentifier }

            if current.count == 1 && // We found one token
                current[0].token == pushToken.deviceTokenString // It matches what we have locally
            {
                // Clear the flags and we are done
                client.pushToken = pushToken.resetFlags()
                return false
            } else {
                // There is something wrong, delete the current token and sync it up
                var token = pushToken.resetFlags()
                token.isMarkedForDeletion = true
                client.pushToken = token
                return true
            }
        }
    }

    func resetTokenFetching(_ pushToken: PushToken) -> PushToken {
        var token = pushToken
        token.isMarkedForDeletion = false
        token.isMarkedForDownload = false
        return token
    }

    public func objectToRefetchForFailedUpdate(of managedObject: ZMManagedObject) -> ZMManagedObject? {
        return nil
    }

    public var requestGenerators: [ZMRequestGenerator] {
        return []
    }

    public var contextChangeTrackers: [ZMContextChangeTracker] {
        return [self.pushKitTokenSync]
    }

    public func shouldProcessUpdatesBeforeInserts() -> Bool {
        return false
    }

}

fileprivate struct PushTokenPayload: Codable {

    init(pushToken: PushToken, clientIdentifier: String) {
        token = pushToken.deviceTokenString
        app = pushToken.appIdentifier
        transport = pushToken.transportType
        client = clientIdentifier
    }

    let token: String
    let app: String
    let transport: String
    let client: String
}

extension PushTokenStrategy : ZMEventConsumer {

    public func processEvents(_ events: [ZMUpdateEvent], liveEvents: Bool, prefetchResult: ZMFetchRequestBatchResult?) {
        guard liveEvents else { return }

        events.forEach{ process(updateEvent:$0) }
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
        // we ignore the payload and remove the locally saved copy
        let client = ZMUser.selfUser(in: self.managedObjectContext).selfClient()
        client?.pushToken = nil
    }
}

