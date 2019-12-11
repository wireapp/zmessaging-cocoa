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

struct RoleUpdate: Codable, Equatable {
//    let id: UUID
//    let type: Int16
    let name: String?
//    let conversations: [UUID] ///TODO: PR?
    
    init(//id: UUID,
//         type: Int16,
         name: String?//,
//         conversations: [UUID]
        ) {
        //self.id = id
//        self.type = type
        self.name = name
//        self.conversations = conversations
    }
    
    init?(_ role: Role) {
//        guard let remoteIdentifier = role.remoteIdentifier else { return nil }
        
        self = .init(//id: remoteIdentifier,
//                     type: role.kind.rawValue,
                     name: role.name//,
//                     conversations: role.conversations.compactMap(\.remoteIdentifier)
        )
    }
}


struct RolePayload: Codable, Equatable {
    var roles: [RoleUpdate]
}

@objc
public final class RoleDownstreamRequestStrategy: AbstractRequestStrategy {
    fileprivate let syncStatus: SyncStatus
    fileprivate var slowSync: ZMSingleRequestSync!
    fileprivate let jsonDecoder = JSONDecoder()
    
    @objc
    public init(with managedObjectContext: NSManagedObjectContext,
                applicationStatus: ApplicationStatus,
                syncStatus: SyncStatus) {
        self.syncStatus = syncStatus
        
        super.init(withManagedObjectContext: managedObjectContext, applicationStatus: applicationStatus)
        
        self.configuration = [.allowsRequestsDuringSync]
        self.slowSync = ZMSingleRequestSync(singleRequestTranscoder: self, groupQueue: managedObjectContext)
    }
    
    override public func nextRequestIfAllowed() -> ZMTransportRequest? {
        guard syncStatus.currentSyncPhase == .fetchingRoles else { return nil }
        
        slowSync.readyForNextRequestIfNotBusy()
        
        return slowSync.nextRequest()
    }

    func update(with transportData: Data) {
        guard let response = try? jsonDecoder.decode(RolePayload.self, from: transportData) else {
            Logging.eventProcessing.error("Can't apply role update due to malformed JSON")
            return
        }
        
        update(with: response)
    }
    
    func update(with response: RolePayload) {
        updateRoles(with: response)
    }

    fileprivate func updateRoles(with response: RolePayload) {
        ///TODO:
    }
}

extension RoleDownstreamRequestStrategy: ZMSingleRequestTranscoder {
    
    static let requestPath = "conversation_role"  ///TODO: how about team role?
    
    public func request(for sync: ZMSingleRequestSync) -> ZMTransportRequest? {
        return ZMTransportRequest(getFromPath: RoleDownstreamRequestStrategy.requestPath)
    }
    
    public func didReceive(_ response: ZMTransportResponse,
                           forSingleRequest sync: ZMSingleRequestSync) {
        guard response.result == .permanentError ||
              response.result == .success else {
            return
        }
        
        if response.result == .success,
           let rawData = response.rawData {
            update(with: rawData)
        }
        
        if syncStatus.currentSyncPhase == .fetchingRoles {
            syncStatus.finishCurrentSyncPhase(phase: .fetchingRoles)
        }
    }
    
}
