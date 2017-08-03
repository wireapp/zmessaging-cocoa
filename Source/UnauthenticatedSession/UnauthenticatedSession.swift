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
    func session(session: UnauthenticatedSession, createdAccount account: Account)
}


@objc
public class UnauthenticatedSession : NSObject {
    
    public let groupQueue: DispatchGroupQueue
    let authenticationStatus: ZMAuthenticationStatus
    let operationLoop: UnauthenticatedOperationLoop
    private let transportSession: UnauthenticatedTransportSessionProtocol & ReachabilityProvider
    private var tornDown = false

    weak var delegate: UnauthenticatedSessionDelegate?

    init(transportSession: UnauthenticatedTransportSessionProtocol & ReachabilityProvider, delegate: UnauthenticatedSessionDelegate?) {
        self.delegate = delegate
        self.groupQueue = DispatchGroupQueue(queue: .main)
        self.authenticationStatus = ZMAuthenticationStatus(groupQueue: groupQueue)
        self.transportSession = transportSession
        self.operationLoop = UnauthenticatedOperationLoop(
            transportSession: transportSession,
            operationQueue: groupQueue,
            requestStrategies: [
                ZMLoginTranscoder(groupQueue: groupQueue, authenticationStatus: authenticationStatus),
                ZMLoginCodeRequestTranscoder(groupQueue: groupQueue, authenticationStatus: authenticationStatus)!,
                ZMRegistrationTranscoder(groupQueue: groupQueue, authenticationStatus: authenticationStatus)!,
                ZMPhoneNumberVerificationTranscoder(groupQueue: groupQueue, authenticationStatus: authenticationStatus)!
            ]
        )

        super.init()
        transportSession.didReceiveUserInfo =  UserInfoAvailableClosure(queue: .main) { [weak self] info in
            guard let `self` = self else { return }
            let account = Account(userName: "", userIdentifier: info.identifier)
            let cookieStorage = account.cookieStorage()
            cookieStorage.authenticationCookieData = info.cookieData
            self.authenticationStatus.authenticationCookieData = info.cookieData
            self.delegate?.session(session: self, createdAccount: account)
        }
    }

    deinit {
        precondition(tornDown, "Need to call tearDown before deinit")
    }

    func tearDown() {
        operationLoop.tearDown()
        tornDown = true
    }
}
