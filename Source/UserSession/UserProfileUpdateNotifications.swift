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
}



// MARK: - Notification

@objc public enum UserProfileUpdateNotificationType : Int {
    case passwordUpdateDidFail
    case emailUpdateDidFail
    case emailDidSendVerification
    case phoneNumberVerificationCodeRequestDidFail
    case phoneNumberVerificationCodeRequestDidSucceed
    case phoneNumberChangeDidFail
}

struct UserProfileUpdateNotification {
    
    fileprivate static let notificationName = NSNotification.Name(rawValue: "UserProfileUpdateNotification")
    fileprivate static let userInfoKey = notificationName
    
    let type : UserProfileUpdateNotificationType
    let error : Error?
    
    private func post() {
        NotificationCenter.default.post(name: type(of: self).notificationName, object: nil, userInfo: [UserProfileUpdateNotification.userInfoKey : self])
    }
    
    public static func notifyPasswordUpdateDidFail() {
        UserProfileUpdateNotification(type: .passwordUpdateDidFail, error: nil).post()
    }
    
    public static func notifyEmailUpdateDidFail(error: Error) {
        UserProfileUpdateNotification(type: .emailUpdateDidFail, error: error).post()
    }
    
    public static func notifyPhoneNumberVerificationCodeRequestDidFailWithError(error: Error) {
        UserProfileUpdateNotification(type: .phoneNumberVerificationCodeRequestDidFail, error: error).post()
    }
    
    public static func notifyPhoneNumberVerificationCodeRequestDidSucceed() {
        UserProfileUpdateNotification(type: .phoneNumberVerificationCodeRequestDidSucceed, error: nil).post()
    }
    
    public static func notifyDidSendEmailVerification() {
        UserProfileUpdateNotification(type: .emailDidSendVerification, error: nil).post()
    }
    
    public static func notifyPhoneNumberChangeDidFail(error: Error) {
        UserProfileUpdateNotification(type: .phoneNumberChangeDidFail, error: error).post()
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
            case .emailUpdateDidFail:
                observer.emailUpdateDidFail(note.error)
            case .phoneNumberVerificationCodeRequestDidFail:
                observer.phoneNumberVerificationCodeRequestDidFail(note.error);
            case .phoneNumberChangeDidFail:
                observer.phoneNumberChangeDidFail(note.error)
            case .passwordUpdateDidFail:
                observer.passwordUpdateRequestDidFail()
            case .phoneNumberVerificationCodeRequestDidSucceed:
                observer.phoneNumberVerificationCodeRequestDidSucceed()
            case .emailDidSendVerification:
                observer.didSentVerificationEmail()
            }
        }
    }
    
    @objc public func removeObserver(token: AnyObject) {
        NotificationCenter.default.removeObserver(token,
                                                  name: UserProfileUpdateNotification.notificationName,
                                                  object: nil)
    }
}
