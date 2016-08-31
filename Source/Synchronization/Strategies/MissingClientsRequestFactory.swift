//
//  MissingClientsRequestFactory.swift
//  zmessaging-cocoa
//
//  Created by Sabine Geithner on 30/08/16.
//  Copyright © 2016 Zeta Project Gmbh. All rights reserved.
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
