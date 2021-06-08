//
//  ZMClientRegistrationStatus.swift
//  WireSyncEngine-ios
//
//  Created by Bill, Yiu Por Chan on 03.06.21.
//  Copyright © 2021 Zeta Project Gmbh. All rights reserved.
//

import Foundation

extension ZMClientRegistrationStatus {
    func didFail(toRegisterClient error: NSError?) {
        var error = error
        ///TODO:
//        ZMLogDebug("%@", NSStringFromSelector(#function))
        //we should not reset login state for client registration errors
        
        
        
        if let errorCode = error?.code,
           errorCode != ZMUserSessionErrorCode.needsPasswordToRegisterClient.rawValue && errorCode != ZMUserSessionErrorCode.needsToRegisterEmailToRegisterClient.rawValue && errorCode != ZMUserSessionErrorCode.canNotRegisterMoreClients.rawValue {
            emailCredentials = nil
        }

        if let errorCode = error?.code,
           errorCode == ZMUserSessionErrorCode.needsPasswordToRegisterClient.rawValue {
            // help the user by providing the email associated with this account
            error = NSError(domain: (error as NSError?)?.domain ?? "", code: errorCode, userInfo: ZMUser.selfUser(in: managedObjectContext).loginCredentials.dictionaryRepresentation)
        }

        if let errorCode = error?.code, errorCode == ZMUserSessionErrorCode.needsPasswordToRegisterClient.rawValue || errorCode == ZMUserSessionErrorCode.invalidCredentials.rawValue {
            // set this label to block additional requests while we are waiting for the user to (re-)enter the password
            needsToCheckCredentials = true
        }

        if let errorCode = error?.code, errorCode == ZMUserSessionErrorCode.canNotRegisterMoreClients.rawValue {
            // Wait and fetch the clients before sending the error
            isWaitingForUserClients = true
            RequestAvailableNotification.notifyNewRequestsAvailable(self)
        } else {
            registrationStatusDelegate.didFailToRegisterSelfUserClient(error: error)
        }
    }
    
    @objc
    public func invalidateCookieAndNotify() {
        emailCredentials = nil
        cookieStorage.deleteKeychainItems()

        let selfUser = ZMUser.selfUser(in: managedObjectContext)
        let outError = NSError.userSessionErrorWith(ZMUserSessionErrorCode.clientDeletedRemotely, userInfo: selfUser.loginCredentials.dictionaryRepresentation)
        registrationStatusDelegate.didDeleteSelfUserClient(error: outError)
    }
}
