//
// Wire
// Copyright (C) 2019 Wire Swiss GmbH
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

extension ZMConversation {

    public func updateRole(of participant: ZMUser, to newRole: Role, session: ZMUserSession, completion: @escaping (VoidResult) -> Void) {

        guard let request = ConversationRoleRequestFactory.requestForUpdatingParticipantRole(participant, role: newRole, in: self, completion: completion) else { return }
        session.transportSession.enqueueOneTime(request)
    }
}

struct ConversationRoleRequestFactory {

    enum ConversationRoleError: Int, Error {
        case unknown = 0
    }

    static func requestForUpdatingParticipantRole(_ participant: ZMUser,
                                                  role: Role,
                                                  in conversation: ZMConversation,
                                                  completion: ((VoidResult) -> Void)? = nil) -> ZMTransportRequest? {
        guard
            let roleName = role.name,
            let userId = participant.remoteIdentifier,
            let conversationId = conversation.remoteIdentifier
        else {
            completion?(.failure(ConversationRoleError.unknown))
            return nil
        }

        let path = "/conversations/\(conversationId.transportString())/members/\(userId.transportString())"
        let payload = ["conversation_role": roleName]

        let request = ZMTransportRequest(path: path, method: .methodPUT, payload: payload as ZMTransportData)

        request.add(ZMCompletionHandler(on: conversation.managedObjectContext!) { response in
            switch response.httpStatus {
            case 200..<300:
                conversation.addParticipantAndUpdateConversationState(user: participant, role: role)
                completion?(.success)
            default:
                completion?(.failure(ConversationRoleError.unknown))
            }
        })

        return request
    }
}
