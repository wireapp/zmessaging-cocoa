//
// Wire
// Copyright (C) 2021 Wire Swiss GmbH
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

public enum ConversationJoinError: Error {
    case unknown, tooManyMembers, invalidCode

    init?(response: ZMTransportResponse) {
        switch (response.httpStatus, response.payloadLabel()) {
        case (403, "too-many-members"?): self = .tooManyMembers
        case (404, "no-conversation-code"?): self = .invalidCode
        case (400..<499, _): self = .unknown
        default: return nil
        }
    }
}

extension ZMConversation {

    /// Join a conversation using a reusable code
    /// - Parameters:
    ///   - key: stable conversation identifier
    ///   - code: conversation code
    ///   - userSession: user session
    ///   - completion: called when the user joines the conversation or when it fails
    public static func join(key: String,
                            code: String,
                            userSession: ZMUserSession,
                            managedObjectContext: NSManagedObjectContext,
                            completion: @escaping (VoidResult) -> Void) {
        self.join(key: key,
                  code: code,
                  transportSession: userSession.transportSession,
                  eventProcessor: userSession.updateEventProcessor,
                  contextProvider: userSession.coreDataStack,
                  moc: managedObjectContext,
                  completion: completion)
    }

    static func join(key: String,
                     code: String,
                     transportSession: TransportSessionType,
                     eventProcessor: UpdateEventProcessor?,
                     contextProvider: ContextProvider?,
                     moc: NSManagedObjectContext,
                     completion: @escaping (VoidResult) -> Void) {

        let request = ConversationJoinRequestFactory.requestForJoinConversation(key: key, code: code)

        request.add(ZMCompletionHandler(on: moc, block: { response in
            switch response.httpStatus {
            case 200:
                guard let payload = response.payload,
                      let event = ZMUpdateEvent(fromEventStreamPayload: payload, uuid: nil),
                      let syncMOC = contextProvider?.syncContext, let eventProcessor = eventProcessor else {
                    return  completion(.failure(ConversationJoinError.unknown))
                }
                
                syncMOC.performGroupedBlock {
                    eventProcessor.storeAndProcessUpdateEvents([event], ignoreBuffer: true)
                }
                completion(.success)

            /// The user is already a participant in the conversation
            case 204:
                completion(.success)
                
            default:
                let error = ConversationJoinError(response: response) ?? .unknown
                Logging.network.debug("Error joining conversation: \(error)")
                completion(.failure(error))
            }
        }))
        transportSession.enqueueOneTime(request)
    }

}

internal struct ConversationJoinRequestFactory {

    static func requestForJoinConversation(key: String, code: String) -> ZMTransportRequest {
        let path = "/conversations/join"
        let payload: [String: Any] = [
            "key": key,
            "code": code
        ]

        return ZMTransportRequest(path: path, method: .methodPOST, payload: payload as ZMTransportData)
    }

}
