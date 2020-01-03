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

private let passwordEndpoint = "/self/password"
private let passwordKey = "passwordKey"

private extension NSNotification.Name {
    static let verifyPassword = NSNotification.Name(rawValue: "VerifyPasswordNotification")
    static let passwordVerified = NSNotification.Name(rawValue: "PasswordVerifiedNotification")
}

public enum VerifyPasswordResult {
    case validated
    case denied
    case timeout
    case unknown
}

public final class VerifyPasswordRequestStrategy: AbstractRequestStrategy {
    
    /// Request sync
    private var requestSync: ZMSingleRequestSync!
    private var password: String?
    private let moc: NSManagedObjectContext
    private var observerToken: Any?

    @objc public override init(withManagedObjectContext moc: NSManagedObjectContext, applicationStatus: ApplicationStatus) {
        self.moc = moc
        super.init(withManagedObjectContext: moc, applicationStatus: applicationStatus)
        self.requestSync = ZMSingleRequestSync(singleRequestTranscoder: self, groupQueue: moc)
        
        observerToken = NotificationInContext.addObserver(
            name: .verifyPassword,
            context: moc.notificationContext,
            using: { [weak self] notification in
                self?.preparePasswordVerification(notification)
            })
    }
    
    private func preparePasswordVerification(_ notification: NotificationInContext) {
        self.password = notification.userInfo[passwordKey] as? String
        self.requestSync.readyForNextRequestIfNotBusy()
        RequestAvailableNotification.notifyNewRequestsAvailable(self)
    }
    
    public override func nextRequestIfAllowed() -> ZMTransportRequest? {
        guard password != nil else {
            return nil
        }
        return self.requestSync.nextRequest()
    }
    
    static func triggerPasswordVerification(with password: String, completion: @escaping (VerifyPasswordResult?) -> Void, context moc: NSManagedObjectContext) {
        var observerToken: Any?
        observerToken = NotificationInContext.addObserver(
            name: .passwordVerified,
            context: moc.notificationContext,
            queue: .main,
            using: { notification in
                let result = notification.userInfo[VerifyPasswordRequestStrategy.verificationResultKey] as? VerifyPasswordResult
                completion(result)
                _ = observerToken
                observerToken = nil
            })
        NotificationInContext(name: .verifyPassword, context: moc.notificationContext, userInfo: [passwordKey: password]).post()
    }
    
    private static func notifyPasswordVerified(with result: VerifyPasswordResult, context moc: NSManagedObjectContext) {
        NotificationInContext(name: .passwordVerified, context: moc.notificationContext, userInfo: [VerifyPasswordRequestStrategy.verificationResultKey: result]).post()
    }
    
    private static let verificationResultKey = "verificationResultKey"
}

// MARK: - Request generation logic
extension VerifyPasswordRequestStrategy: ZMSingleRequestTranscoder {
    
    public func request(for sync: ZMSingleRequestSync) -> ZMTransportRequest? {
        guard sync == self.requestSync, let password = self.password else {
            return nil
        }
        
        let payload : [String: Any] = [
            "new_password": password,
            "old_password": password
        ]
        let request = ZMTransportRequest(path: passwordEndpoint, method: .methodPUT, payload: payload as ZMTransportData?, shouldCompress: true)
        return request
    }
    
    public func didReceive(_ response: ZMTransportResponse, forSingleRequest sync: ZMSingleRequestSync) {
        password = nil
        let result: VerifyPasswordResult
        switch response.httpStatus {
        case 403: // Invalid credentials
            result = .denied
        case 409: // Correct credentials
            result = .validated
        case 408:
            result = .timeout
        default:
            result = .unknown
        }
        VerifyPasswordRequestStrategy.notifyPasswordVerified(with: result, context: moc)
        self.requestSync.resetCompletionState()
    }
}
