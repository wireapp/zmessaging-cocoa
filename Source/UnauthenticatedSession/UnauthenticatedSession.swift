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
    func session(session: UnauthenticatedSession, createdAccount account: Account)
}



@objc
public class UnauthenticatedSession : NSObject {
    
    let moc: NSManagedObjectContext
    let authenticationStatus: ZMAuthenticationStatus
    private let operationLoop: UnauthenticatedOperationLoop
    private let transportSession: UnauthenticatedTransportSessionProtocol

    weak var delegate: UnauthenticatedSessionDelegate?
    
    convenience init(backendURL: URL, delegate: UnauthenticatedSessionDelegate? = nil) throws {
        let model = NSManagedObjectModel()
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        try coordinator.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil, options: nil)
        let moc = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        moc.createDispatchGroups()
        moc.persistentStoreCoordinator = coordinator
        let authenticationStatus = ZMAuthenticationStatus(cookieStorage: nil, managedObjectContext: moc)
        let transportSession = UnauthenticatedTransportSession(baseURL: backendURL)
        self.init(moc: moc, authenticationStatus: authenticationStatus!, transportSession: transportSession, delegate: delegate)
    }
    
    init(moc: NSManagedObjectContext, authenticationStatus: ZMAuthenticationStatus, transportSession: UnauthenticatedTransportSessionProtocol, delegate: UnauthenticatedSessionDelegate?) {
        self.delegate = delegate
        self.moc = moc
        self.authenticationStatus = authenticationStatus
        self.transportSession = transportSession
        self.operationLoop = UnauthenticatedOperationLoop(transportSession: transportSession, operationQueue: moc, requestStrategies: [
                ZMLoginTranscoder(managedObjectContext: moc, authenticationStatus: authenticationStatus),
                ZMLoginCodeRequestTranscoder(managedObjectContext: moc, authenticationStatus: authenticationStatus)!,
                ZMRegistrationTranscoder(managedObjectContext: moc, authenticationStatus: authenticationStatus)!,
                ZMPhoneNumberVerificationTranscoder(managedObjectContext: moc, authenticationStatus: authenticationStatus)!
        ])

        super.init()
        transportSession.delegate = self
    }
}

// MARK: - UnauthenticatedTransportSessionDelegate

extension UnauthenticatedSession: UnauthenticatedTransportSessionDelegate {
    
    public func session(_ session: UnauthenticatedTransportSession, didReceiveUserInfo userInfo: UserInfo) {
        let account = Account(userName: "", userIdentifier: userInfo.identifier)
        delegate?.session(session: self, createdAccount: account)
    }
    
}
