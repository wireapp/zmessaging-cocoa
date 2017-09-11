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
import WireTransport

let PushChannelUserIDKey = "user"
let PushChannelDataKey = "data"

private let log = ZMSLog(tag: "Push")

extension Dictionary where Key: Hashable, Value: Any {
    internal func isPayload(for user: ZMUser) -> Bool {
        guard let userInfoData = self[PushChannelDataKey as! Key] as? [String: Any] else {
            log.debug("No data dictionary in notification userInfo payload");
            return true // Old-style push might not contain the user id
        }
        
        guard let user_id = userInfoData[PushChannelUserIDKey] as? String else {
            // Old-style push might not contain the user id
            return true
        }
        
        return user.remoteIdentifier == UUID(uuidString: user_id)
    }
}

extension NSDictionary {
    @objc(isPayloadForUser:)
    public func isPayload(for user: ZMUser) -> Bool {
        return (self as Dictionary).isPayload(for: user)
    }
}

extension ZMUserSession: PushDispatcherOptionalClient {
    
    
    func updatedPushToken(to newToken: PushToken) {
        
        guard let managedObjectContext = self.managedObjectContext else {
            return
        }
        
        switch newToken {
        case .alert(let tokenData):
            if let data = tokenData {
                managedObjectContext.performGroupedBlock {
                    let oldToken = self.managedObjectContext.pushToken?.deviceToken
                    if oldToken == nil || oldToken != data {
                        managedObjectContext.pushToken = nil
                        self.setPushToken(data)
                        managedObjectContext.forceSaveOrRollback()
                    }
                }
            }
        case .voip(let tokenData):
            if let data = tokenData {
                managedObjectContext.performGroupedBlock {
                    managedObjectContext.pushKitToken = nil
                    self.setPushKitToken(data)
                    managedObjectContext.forceSaveOrRollback()
                }
            }
            else {
                managedObjectContext.performGroupedBlock {
                    self.deletePushKitToken()
                    managedObjectContext.forceSaveOrRollback()
                }
            }
        }
    }

    func canHandle(payload: [AnyHashable: Any]) -> Bool {
        return payload.isPayload(for: ZMUser.selfUser(in: self.managedObjectContext))
    }
    
    func receivedPushNotification(with payload: [AnyHashable: Any], from source: ZMPushNotficationType, completion: @escaping ZMPushNotificationCompletionHandler) {
        self.syncManagedObjectContext.performGroupedBlock {
            let isNotInBackground = self.isNotInBackground()
            let notAuthenticated = self.isAuthenticated()
            
            if notAuthenticated || isNotInBackground {
                if (isNotInBackground) {
                    log.debug("Not displaying notification because app is not authenticated")
                }
                completion(.success)
                return
            }
            
            self.operationLoop.saveEventsAndSendNotification(forPayload: payload, fetchCompletionHandler: completion, source: source)
        }
    }
}

