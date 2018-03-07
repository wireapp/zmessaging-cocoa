//
// Wire
// Copyright (C) 2018 Wire Swiss GmbH
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

private let zmLog = ZMSLog(tag: "ConversationLink")

public enum SetAllowGuestsError: Error {
    case unknown
}

extension ZMConversation {
    public func setAllowGuests(_ allowGuests: Bool, in userSession: ZMUserSession, _ completion: @escaping (VoidResult) -> Void) {
        let request = WirelessRequestFactory.set(allowGuests: allowGuests, for: self)
        request.add(ZMCompletionHandler(on: managedObjectContext!) { response in
            if let payload = response.payload,
                let event = ZMUpdateEvent(fromEventStreamPayload: payload, uuid: nil) {
                self.allowGuests = allowGuests
                // Process `conversation.access-update` event
                userSession.syncManagedObjectContext.performGroupedBlock {
                    userSession.operationLoop.syncStrategy.processUpdateEvents([event], ignoreBuffer: true)
                }
                completion(.success)
            } else {
                zmLog.error("Error creating wireless link: \(response)")
                completion(.failure(SetAllowGuestsError.unknown))
            }
        })
        
        userSession.transportSession.enqueueOneTime(request)
    }
    
    public var canManageAccess: Bool {
        // Check conversation
        guard self.conversationType == .group,
            let moc = self.managedObjectContext,
            let _ = self.teamRemoteIdentifier,
            let _ = self.remoteIdentifier?.transportString() else {
                return false
        }
        
        // Check user
        let selfUser = ZMUser.selfUser(in: moc)
        guard selfUser.isTeamMember,
             !selfUser.isGuest(in: self),
             selfUser.team == self.team else {
            return false
        }
        
        return true
    }
}

internal struct WirelessRequestFactory {
    static func fetchLinkRequest(for conversation: ZMConversation) -> ZMTransportRequest {
        guard let identifier = conversation.remoteIdentifier?.transportString() else {
            fatal("conversation is not yet inserted on the backend")
        }
        return .init(getFromPath: "/conversations/\(identifier)/code")
    }
    
    static func createLinkRequest(for conversation: ZMConversation) -> ZMTransportRequest {
        guard let identifier = conversation.remoteIdentifier?.transportString() else {
            fatal("conversation is not yet inserted on the backend")
        }
        return .init(path: "/conversations/\(identifier)/code", method: .methodPOST, payload: nil)
    }
    
    static func set(allowGuests: Bool, for conversation: ZMConversation) -> ZMTransportRequest {
        guard conversation.canManageAccess else {
            fatal("conversation cannot be managed")
        }
        guard let identifier = conversation.remoteIdentifier?.transportString() else {
            fatal("conversation is not yet inserted on the backend")
        }
        let payload = [ "access": ConversationAccessMode.value(forAllowGuests: allowGuests).stringValue as Any,
                        "access_role": ConversationAccessRole.value(forAllowGuests: allowGuests).rawValue]
        return .init(path: "/conversations/\(identifier)/access", method: .methodPUT, payload: payload as ZMTransportData)
    }
}
