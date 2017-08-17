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

public protocol UnauthenticatedSessionDelegate: class {
    func session(session: UnauthenticatedSession, updatedCredentials credentials: ZMCredentials)
    func session(session: UnauthenticatedSession, updatedProfileImage imageData: Data)
    func session(session: UnauthenticatedSession, createdAccount account: Account)
}

@objc public protocol UserInfoParser: class {
    @objc(parseUserInfoFromResponse:)
    func parseUserInfo(from response: ZMTransportResponse)
}

private let log = ZMSLog(tag: "UnauthenticatedSession")


@objc
public class UnauthenticatedSession: NSObject {
    
    public let groupQueue: DispatchGroupQueue
    let authenticationStatus: ZMAuthenticationStatus
    let reachability: ReachabilityProvider
    private(set) var operationLoop: UnauthenticatedOperationLoop!
    private let transportSession: UnauthenticatedTransportSessionProtocol
    private var tornDown = false

    weak var delegate: UnauthenticatedSessionDelegate?

    init(transportSession: UnauthenticatedTransportSessionProtocol, reachability: ReachabilityProvider, delegate: UnauthenticatedSessionDelegate?) {
        self.delegate = delegate
        self.groupQueue = DispatchGroupQueue(queue: .main)
        self.authenticationStatus = ZMAuthenticationStatus(groupQueue: groupQueue)
        self.transportSession = transportSession
        self.reachability = reachability
        super.init()

        self.operationLoop = UnauthenticatedOperationLoop(
            transportSession: transportSession,
            operationQueue: groupQueue,
            requestStrategies: [
                ZMLoginTranscoder(groupQueue: groupQueue, authenticationStatus: authenticationStatus, userInfoParser: self),
                ZMLoginCodeRequestTranscoder(groupQueue: groupQueue, authenticationStatus: authenticationStatus)!,
                ZMRegistrationTranscoder(groupQueue: groupQueue, authenticationStatus: authenticationStatus, userInfoParser: self)!,
                ZMPhoneNumberVerificationTranscoder(groupQueue: groupQueue, authenticationStatus: authenticationStatus)!
            ]
        )
    }

    deinit {
        precondition(tornDown, "Need to call tearDown before deinit")
    }

    func tearDown() {
        operationLoop.tearDown()
        tornDown = true
    }

}

// MARK: - UserInfoParser

extension UnauthenticatedSession: UserInfoParser {

    public func parseUserInfo(from response: ZMTransportResponse) {
        guard let info = response.extractUserInfo() else { return log.warn("Failed to parse UserInfo from response: \(response)") }
        log.debug("Parsed UserInfo from response: \(info)")
        let account = Account(userName: "", userIdentifier: info.identifier)
        let cookieStorage = account.cookieStorage()
        cookieStorage.authenticationCookieData = info.cookieData
        self.authenticationStatus.authenticationCookieData = info.cookieData
        self.delegate?.session(session: self, createdAccount: account)
    }

}
