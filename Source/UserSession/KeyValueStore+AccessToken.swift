//
//  KeyValueStore+AccessToken.swift
//  zmessaging-cocoa
//
//  Created by Marco Conti on 21/12/2016.
//  Copyright © 2016 Zeta Project Gmbh. All rights reserved.
//

import Foundation

private let lastAccessTokenKey = "ZMLastAccessToken";
private let lastAccessTokenTypeKey = "ZMLastAccessTokenType";

extension NSManagedObjectContext {
    
    public var accessToken : ZMAccessToken? {
        get {
            guard let token = self.storedValue(key: lastAccessTokenKey) as? String,
                let type = self.storedValue(key: lastAccessTokenTypeKey) as? String else {
                    return nil
            }
            return ZMAccessToken(token: token, type: type, expiresInSeconds: 0)
        }
        
        set {
            self.store(value: newValue?.token, key: lastAccessTokenKey)
            self.store(value: newValue?.type, key: lastAccessTokenTypeKey)
        }
    }
}
