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

fileprivate extension ZMConversation {
    struct TransportKey {
        static let data = "data"
        static let uri = "uri"
    }
}

public enum WirelessLinkError: Error {
    case noCode
    case invalidOperation
    case unknown
    
    init?(response: ZMTransportResponse) {
        switch (response.httpStatus, response.payloadLabel()) {
        case (403, "invalid-op"?): self = .invalidOperation
        case (404, "no-conversation-code"?): self = .noCode
        case (400..<499, _): self = .unknown
        default: return nil
        }
    }
}

extension ZMConversation {
    func fetchWirelessLink(in userSession: ZMUserSession, _ completion: @escaping (Result<String>) -> Void) {
        let request = WirelessRequestFactory.fetchLinkRequest(for: self)
        request.add(ZMCompletionHandler(on: managedObjectContext!) { [weak self] response in
            if response.httpStatus == 200, let uri = response.payload?.asDictionary()?[ZMConversation.TransportKey.uri] as? String {
//                self?.conversationLink = uri
                zmLog.error("Did fetch existing wireless link: \(uri)")
                completion(.success(uri))
            } else {
                let error = WirelessLinkError(response: response) ?? .unknown
                zmLog.error("Error fetching wireless link: \(error)")
                completion(.failure(error))
            }
        })
        
        userSession.transportSession.enqueueOneTime(request)
    }
    
    func createWirelessLink(in userSession: ZMUserSession, _ completion: @escaping (Result<String>) -> Void) {
        let request = WirelessRequestFactory.createLinkRequest(for: self)
        request.add(ZMCompletionHandler(on: managedObjectContext!) { response in
            if response.httpStatus == 200, let payload = response.payload,
                let event = ZMUpdateEvent(fromEventStreamPayload: payload, uuid: nil),
                let data = payload.asDictionary()?[ZMConversation.TransportKey.data] as? [String: Any],
                let uri = data[ZMConversation.TransportKey.uri] as? String {
                zmLog.error("Did create wireless link: \(uri)")
                completion(.success(uri))

                // Process `conversation.code-update` event
                userSession.syncManagedObjectContext.performGroupedBlock {
                    userSession.operationLoop.syncStrategy.processUpdateEvents([event], ignoreBuffer: true)
                }
            } else {
                let error = WirelessLinkError(response: response) ?? .unknown
                zmLog.error("Error creating wireless link: \(error)")
                completion(.failure(error))
            }
        })
        
        userSession.transportSession.enqueueOneTime(request)
    }
    
    func setMode(_ mode: ConversationAccessMode, in userSession: ZMUserSession, _ completion: @escaping (VoidResult) -> Void) {
        guard accessMode != mode else { return completion(.success) }
        let request = WirelessRequestFactory.setMode(for: self, mode: mode)
        request.add(ZMCompletionHandler(on: managedObjectContext!) { response in
            if let payload = response.payload,
                let event = ZMUpdateEvent(fromEventStreamPayload: payload, uuid: nil) {
                // Process `conversation.access-update` event
                userSession.syncManagedObjectContext.performGroupedBlock {
                    userSession.operationLoop.syncStrategy.processUpdateEvents([event], ignoreBuffer: true)
                }
                completion(.success)
            } else {
                let error = WirelessLinkError(response: response) ?? .unknown
                zmLog.error("Error creating wireless link: \(error)")
                completion(.failure(error))
            }
        })
        
        userSession.transportSession.enqueueOneTime(request)
    }
}

fileprivate struct WirelessRequestFactory {
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
    
    static func setMode(for conversation: ZMConversation, mode: ConversationAccessMode) -> ZMTransportRequest {
        guard let identifier = conversation.remoteIdentifier?.transportString() else {
            fatal("conversation is not yet inserted on the backend")
        }
        let payload = [ "access": mode.stringValue ]
        return .init(path: "/conversations/\(identifier)/access", method: .methodPUT, payload: payload as ZMTransportData)
    }
}
