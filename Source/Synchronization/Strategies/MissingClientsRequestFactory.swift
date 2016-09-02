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


public class MissingClientsRequestFactory {
    
    let pageSize : Int
    public init(pageSize: Int = 128) {
        self.pageSize = pageSize
    }
    
    public func fetchMissingClientKeysRequest(missingClients: Set<UserClient>) -> ZMUpstreamRequest! {
        let map = MissingClientsMap(Array(missingClients), pageSize: pageSize)
        let request = ZMTransportRequest(path: "/users/prekeys", method: ZMTransportRequestMethod.MethodPOST, payload: map.payload)
        return ZMUpstreamRequest(keys: Set(arrayLiteral: ZMUserClientMissingKey), transportRequest: request, userInfo: map.userInfo)
    }
    
}

public struct MissingClientsMap {
    
    /// The mapping from user-id's to an array of missing clients for that user `{ <user-id>: [<client-id>] }`
    let payload: [String: [String]]
    /// The `MissingClientsRequestUserInfoKeys.clients` key holds all missing clients
    let userInfo: [String: [String]]
    
    public init(_ missingClients: [UserClient], pageSize: Int) {
        
        let addClientIdToMap = { (clientsMap: [String : [String]], missingClient: UserClient) -> [String:[String]] in
            var clientsMap = clientsMap
            let missingUserId = missingClient.user!.remoteIdentifier!.transportString()
            clientsMap[missingUserId] = (clientsMap[missingUserId] ?? []) + [missingClient.remoteIdentifier]
            return clientsMap
        }
        
        var users = Set<ZMUser>()
        let missing = missingClients.filter {
            guard let user = $0.user else { return false }
            users.insert(user)
            return users.count <= pageSize
        }
        
        payload = missing.filter { $0.user?.remoteIdentifier != nil } .reduce([String:[String]](), combine: addClientIdToMap)
        userInfo = [MissingClientsRequestUserInfoKeys.clients: missing.map { $0.remoteIdentifier }]
    }
}
