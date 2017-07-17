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
    @objc optional func passwordUpdateRequestDidFail()
    
    /// Invoked when the email could not be set on the backend (duplicated?).
    /// The password might already have been set though - this is how BE is designed and there's nothing SE can do about it
    @objc optional func emailUpdateDidFail(_ error: Error!)
    
    /// Invoked when the email was sent to the backend
    @objc optional func didSentVerificationEmail()
    
    /// Invoked when requesting the phone number verification code failed
    @objc optional func phoneNumberVerificationCodeRequestDidFail(_ error: Error!)
    
    /// Invoken when requesting the phone number verification code succeeded
    @objc optional func phoneNumberVerificationCodeRequestDidSucceed()
    
    /// Invoked when the phone number could not be removed
    @objc optional func phoneNumberRemovalDidFail(_ error: Error!)
    
    /// Invoked when phone number was removed
    @objc optional func didRemovePhoneNumber()
    
    /// Invoked when the phone number code verification failed
    /// The opposite (phone number change success) will be notified
    /// by a change in the user phone number
    @objc optional func phoneNumberChangeDidFail(_ error: Error!)
    
    /// Invoked when the availability of a handle was determined
    @objc optional func didCheckAvailiabilityOfHandle(handle: String, available: Bool)
    
    /// Invoked when failed to check for availability of a handle
    @objc optional func didFailToCheckAvailabilityOfHandle(handle: String)
    
    /// Invoked when the handle is set
    @objc optional func didSetHandle()
    
    /// Invoked when failed to set the handle
    @objc optional func didFailToSetHandle()
    
    /// Invoked when failed to set the handle because already taken
    @objc optional func didFailToSetHandleBecauseExisting()
    
    /// Invoked when a good handle suggestion is found
    @objc optional func didFindHandleSuggestion(handle: String)
}



// MARK: - Notification
enum UserProfileUpdateNotificationType {
    case passwordUpdateDidFail
    case emailUpdateDidFail(error: Error)
    case emailDidSendVerification
    case didRemovePhoneNumber
    case phoneNumberVerificationCodeRequestDidFail(error: Error)
    case phoneNumberVerificationCodeRequestDidSucceed
    case phoneNumberChangeDidFail(error: Error)
    case phoneNumberRemovalDidFail(error: Error)
    case didCheckAvailabilityOfHandle(handle: String, available: Bool)
    case didFailToCheckAvailabilityOfHandle(handle: String)
    case didSetHandle
    case didFailToSetHandleBecauseExisting
    case didFailToSetHandle
    case didFindHandleSuggestion(handle: String)
}

struct UserProfileUpdateNotification {
    
    fileprivate static let notificationName = NSNotification.Name(rawValue: "UserProfileUpdateNotification")
    fileprivate static let userInfoKey = notificationName
    
    fileprivate let type : UserProfileUpdateNotificationType
    
    static func post(type: UserProfileUpdateNotificationType) {
        
        NotificationCenter.default.post(name: self.notificationName,
                                        object: nil,
                                        userInfo: [UserProfileUpdateNotification.userInfoKey : UserProfileUpdateNotification(type: type)])
    }
}

extension UserProfileUpdateStatus {
    
    @objc(addObserver:) public func add(observer: UserProfileUpdateObserver) -> AnyObject? {
        return NotificationCenter.default.addObserver(forName: UserProfileUpdateNotification.notificationName,
                                                      object: nil,
                                                      queue: OperationQueue.main)
        {
            [weak observer] (anynote: Notification) in
            guard let note = anynote.userInfo?[UserProfileUpdateNotification.userInfoKey] as? UserProfileUpdateNotification,
                  let observer = observer else {
                return
            }
            switch note.type {
            case .emailUpdateDidFail(let error):
                observer.emailUpdateDidFail?(error)
            case .phoneNumberRemovalDidFail(let error):
                observer.phoneNumberRemovalDidFail?(error)
            case .didRemovePhoneNumber:
                observer.didRemovePhoneNumber?()
            case .phoneNumberVerificationCodeRequestDidFail(let error):
                observer.phoneNumberVerificationCodeRequestDidFail?(error);
            case .phoneNumberChangeDidFail(let error):
                observer.phoneNumberChangeDidFail?(error)
            case .passwordUpdateDidFail:
                observer.passwordUpdateRequestDidFail?()
            case .phoneNumberVerificationCodeRequestDidSucceed:
                observer.phoneNumberVerificationCodeRequestDidSucceed?()
            case .emailDidSendVerification:
                observer.didSentVerificationEmail?()
            case .didCheckAvailabilityOfHandle(let handle, let available):
                observer.didCheckAvailiabilityOfHandle?(handle: handle, available: available)
            case .didFailToCheckAvailabilityOfHandle(let handle):
                observer.didFailToCheckAvailabilityOfHandle?(handle: handle)
            case .didSetHandle:
                observer.didSetHandle?()
            case .didFailToSetHandle:
                observer.didFailToSetHandle?()
            case .didFailToSetHandleBecauseExisting:
                observer.didFailToSetHandleBecauseExisting?()
            case .didFindHandleSuggestion(let handle):
                observer.didFindHandleSuggestion?(handle: handle)
            }
        }
    }
    
    @objc public func removeObserver(token: AnyObject) {
        NotificationCenter.default.removeObserver(token,
                                                  name: UserProfileUpdateNotification.notificationName,
                                                  object: nil)
    }
}
