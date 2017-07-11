//
// Wire
// Copyright (C) 2017 Wire Swiss GmbH
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

protocol UnauthenticatedSessionDelegate: class {
    func session(session: UnauthenticatedSession, updatedCredentials credentials: ZMCredentials)
    func session(session: UnauthenticatedSession, updatedProfileImage imageData: Data)
}

@objc
public class UnauthenticatedSession : NSObject {
    
    let moc: NSManagedObjectContext
    let authenticationStatus: ZMAuthenticationStatus
    let operationLoop: UnauthenticatedOperationLoop
    weak var delegate: UnauthenticatedSessionDelegate?
    
    convenience init(transportSession: ZMTransportSession, delegate: UnauthenticatedSessionDelegate? = nil) throws {
        let model = NSManagedObjectModel()
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        try coordinator.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil, options: nil)
        let moc = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        moc.createDispatchGroups()
        moc.persistentStoreCoordinator = coordinator
        let authenticationStatus = ZMAuthenticationStatus(cookieStorage: transportSession.cookieStorage, managedObjectContext: moc)
        
        self.init(moc: moc, authenticationStatus: authenticationStatus!, transportSession: transportSession, delegate: delegate)
    }
    
    init(moc: NSManagedObjectContext, authenticationStatus: ZMAuthenticationStatus, transportSession: ZMTransportSession, delegate: UnauthenticatedSessionDelegate?) {
        self.delegate = delegate
        self.moc = moc
        self.authenticationStatus = authenticationStatus
        
        let loginRequestStrategy = ZMLoginTranscoder(managedObjectContext: moc, authenticationStatus: authenticationStatus)
        let loginCodeRequestStrategy = ZMLoginCodeRequestTranscoder(managedObjectContext: moc, authenticationStatus: authenticationStatus)!
        let registrationRequestStrategy = ZMRegistrationTranscoder(managedObjectContext: moc, authenticationStatus: authenticationStatus)!
        let phoneNumberVerificationRequestStrategy = ZMPhoneNumberVerificationTranscoder(managedObjectContext: moc, authenticationStatus: authenticationStatus)!
        
        self.operationLoop = UnauthenticatedOperationLoop(transportSession: transportSession, operationQueue: moc, requestStrategies: [
                loginRequestStrategy,
                loginCodeRequestStrategy,
                registrationRequestStrategy,
                phoneNumberVerificationRequestStrategy
             ])
    }    
}
