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
import WireUtilities

protocol UnauthenticatedSessionDelegate: class {
    func session(session: UnauthenticatedSession, updatedCredentials credentials: ZMCredentials)
    func session(session: UnauthenticatedSession, updatedProfileImage imageData: Data)
}

public protocol ReachabilityProvider {
    var mayBeReachable: Bool { get }
}

extension ZMReachability: ReachabilityProvider {}

public protocol TransportSession {
    var cookieStorage: ZMPersistentCookieStorage { get }
    var reachabilityProvider: ReachabilityProvider { get }
    @discardableResult func attemptToEnqueueSyncRequestWithGenerator(_ generator: @escaping ZMTransportRequestGenerator) -> ZMTransportEnqueueResult
}

extension ZMTransportSession: TransportSession {
    public var reachabilityProvider: ReachabilityProvider {
        return self.reachability
    }
}

@objc
public class UnauthenticatedSession : NSObject {
    
    public let groupQueue: DispatchGroupQueue
    let authenticationStatus: ZMAuthenticationStatus
    let operationLoop: UnauthenticatedOperationLoop
    weak var delegate: UnauthenticatedSessionDelegate?
        
    init(transportSession: TransportSession, delegate: UnauthenticatedSessionDelegate?) {
        self.delegate = delegate
        self.groupQueue = DispatchGroupQueue(queue: DispatchQueue.main)
        self.authenticationStatus = ZMAuthenticationStatus(cookieStorage: transportSession.cookieStorage, groupQueue: groupQueue)
        
        let loginRequestStrategy = ZMLoginTranscoder(groupQueue: groupQueue, authenticationStatus: authenticationStatus)
        let loginCodeRequestStrategy = ZMLoginCodeRequestTranscoder(groupQueue: groupQueue, authenticationStatus: authenticationStatus)!
        let registrationRequestStrategy = ZMRegistrationTranscoder(groupQueue: groupQueue, authenticationStatus: authenticationStatus)!
        let phoneNumberVerificationRequestStrategy = ZMPhoneNumberVerificationTranscoder(groupQueue: groupQueue, authenticationStatus: authenticationStatus)!
        
        self.operationLoop = UnauthenticatedOperationLoop(transportSession: transportSession, operationQueue: groupQueue, requestStrategies: [
                loginRequestStrategy,
                loginCodeRequestStrategy,
                registrationRequestStrategy,
                phoneNumberVerificationRequestStrategy
             ])
    }
    
}
