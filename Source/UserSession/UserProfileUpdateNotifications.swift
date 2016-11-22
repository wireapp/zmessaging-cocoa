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

// MARK: - Observer
@objc public protocol UserProfileUpdateObserver : NSObjectProtocol {
    
    /// Invoked when the password could not be set on the backend
    func passwordUpdateRequestDidFail()
    
    /// Invoked when the email could not be set on the backend (duplicated?).
    /// The password might already have been set though - this is how BE is designed and there's nothing SE can do about it
    func emailUpdateDidFail(_ error: Error!)
    
    /// Invoked when the email was sent to the backend
    func didSentVerificationEmail()
    
    /// Invoked when requesting the phone number verification code failed
    func phoneNumberVerificationCodeRequestDidFail(_ error: Error!)
    
    /// Invoken when requesting the phone number verification code succeeded
    func phoneNumberVerificationCodeRequestDidSucceed()
    
    /// Invoked when the phone number code verification failed
    /// The opposite (phone number change success) will be notified
    /// by a change in the user phone number
    func phoneNumberChangeDidFail(_ error: Error!)
    
    /// Invoked when the availability of a handle was determined
    func didCheckAvailiabilityOfHandle(handle: String, available: Bool)
    
    /// Invoked when failed to check for availability of a handle
    func didFailToCheckAvailabilityOfHandle(handle: String)
}



// MARK: - Notification
private enum UserProfileUpdateNotificationType {
    case passwordUpdateDidFail
    case emailUpdateDidFail(error: Error)
    case emailDidSendVerification
    case phoneNumberVerificationCodeRequestDidFail(error: Error)
    case phoneNumberVerificationCodeRequestDidSucceed
    case phoneNumberChangeDidFail(error: Error)
    case didCheckAvailabilityOfHandle(handle: String, available: Bool)
    case didFailToCheckAvailabilityOfHandle(handle: String)
}

struct UserProfileUpdateNotification {
    
    fileprivate static let notificationName = NSNotification.Name(rawValue: "UserProfileUpdateNotification")
    fileprivate static let userInfoKey = notificationName
    
    fileprivate let type : UserProfileUpdateNotificationType
    
    private func post() {
        NotificationCenter.default.post(name: type(of: self).notificationName, object: nil, userInfo: [UserProfileUpdateNotification.userInfoKey : self])
    }
    
    static func notifyPasswordUpdateDidFail() {
        UserProfileUpdateNotification(type: .passwordUpdateDidFail).post()
    }
    
    static func notifyEmailUpdateDidFail(error: Error) {
        UserProfileUpdateNotification(type: .emailUpdateDidFail(error: error)).post()
    }
    
    static func notifyPhoneNumberVerificationCodeRequestDidFailWithError(error: Error) {
        UserProfileUpdateNotification(type: .phoneNumberVerificationCodeRequestDidFail(error: error)).post()
    }
    
    static func notifyPhoneNumberVerificationCodeRequestDidSucceed() {
        UserProfileUpdateNotification(type: .phoneNumberVerificationCodeRequestDidSucceed).post()
    }
    
    static func notifyDidSendEmailVerification() {
        UserProfileUpdateNotification(type: .emailDidSendVerification).post()
    }
    
    static func notifyPhoneNumberChangeDidFail(error: Error) {
        UserProfileUpdateNotification(type: .phoneNumberChangeDidFail(error: error)).post()
    }

    static func notifyDidCheckAvailabilityOfHandle(handle: String, available: Bool) {
        UserProfileUpdateNotification(type: .didCheckAvailabilityOfHandle(handle: handle, available: available)).post()
    }
    
    static func notifyDidFailToCheckAvailabilityOfHandle(handle: String) {
        UserProfileUpdateNotification(type: .didFailToCheckAvailabilityOfHandle(handle: handle)).post()
    }
}

extension UserProfileUpdateStatus {
    
    @objc(addObserver:) public func add(observer: UserProfileUpdateObserver) -> AnyObject? {
        return NotificationCenter.default.addObserver(forName: UserProfileUpdateNotification.notificationName,
                                                      object: nil,
                                                      queue: OperationQueue.main)
        { (anynote: Notification) in
            guard let note = anynote.userInfo?[UserProfileUpdateNotification.userInfoKey] as? UserProfileUpdateNotification else {
                return
            }
            switch note.type {
            case .emailUpdateDidFail(let error):
                observer.emailUpdateDidFail(error)
            case .phoneNumberVerificationCodeRequestDidFail(let error):
                observer.phoneNumberVerificationCodeRequestDidFail(error);
            case .phoneNumberChangeDidFail(let error):
                observer.phoneNumberChangeDidFail(error)
            case .passwordUpdateDidFail:
                observer.passwordUpdateRequestDidFail()
            case .phoneNumberVerificationCodeRequestDidSucceed:
                observer.phoneNumberVerificationCodeRequestDidSucceed()
            case .emailDidSendVerification:
                observer.didSentVerificationEmail()
            case .didCheckAvailabilityOfHandle(let handle, let available):
                observer.didCheckAvailiabilityOfHandle(handle: handle, available: available)
            case .didFailToCheckAvailabilityOfHandle(let handle):
                observer.didFailToCheckAvailabilityOfHandle(handle: handle)
            }
        }
    }
    
    @objc public func removeObserver(token: AnyObject) {
        NotificationCenter.default.removeObserver(token,
                                                  name: UserProfileUpdateNotification.notificationName,
                                                  object: nil)
    }
}
