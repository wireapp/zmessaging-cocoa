//
//  UserProfileUpdateRequestStrategy.swift
//  zmessaging-cocoa
//
//  Created by Marco Conti on 15/11/16.
//  Copyright © 2016 Zeta Project Gmbh. All rights reserved.
//

import Foundation

@objc public class UserProfileRequestStrategy : NSObject {
    
    let managedObjectContext : NSManagedObjectContext
    
    let userProfileUpdateStatus : UserProfileUpdateStatus
    
    let clientRegistrationStatus : ZMClientRegistrationStatus
    
    let authenticationStatus : AuthenticationStatusProvider
    
    public init(managedObjectContext: NSManagedObjectContext,
                userProfileUpdateStatus: UserProfileUpdateStatus,
                clientRegistrationStatus: ZMClientRegistrationStatus,
                authenticationStatus: AuthenticationStatusProvider) {
        self.managedObjectContext = managedObjectContext
        self.userProfileUpdateStatus = userProfileUpdateStatus
        self.authenticationStatus = authenticationStatus
        self.clientRegistrationStatus = clientRegistrationStatus
    }
}

extension UserProfileRequestStrategy : RequestStrategy {
    
    @objc public func nextRequest() -> ZMTransportRequest? {
        // TODO
        return nil
    }
}
