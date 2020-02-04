//
// Wire
// Copyright (C) 2020 Wire Swiss GmbH
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

public protocol UserSessionVerifyPasswordInterface {
    func verify(password: String, completion: @escaping (VerifyPasswordResult?) -> Void)
}

extension ZMUserSession: UserSessionVerifyPasswordInterface {
    static let failedPasswordCountKey: String = "failedPasswordCount"
    
    public func verify(password: String, completion: @escaping (VerifyPasswordResult?) -> Void) {
        VerifyPasswordRequestStrategy.triggerPasswordVerification(
            with: password,
            completion: { [weak self] result in
                guard let `self` = self else { return }
                completion(result)
                if case .denied? = result {
                    self.failedPasswordCount += 1
                    self.sessionManager?.passwordVerificationDidFail(with: self.failedPasswordCount)
                } else if case .validated? = result {
                    self.failedPasswordCount = 0
                }
            },
            context: self.syncManagedObjectContext)
    }
    
    private var failedPasswordCount: Int {
        get {
            let count = self.managedObjectContext.persistentStoreMetadata(forKey: ZMUserSession.failedPasswordCountKey) as? Int
            return count ?? 0
        } set {
            self.managedObjectContext.setPersistentStoreMetadata(newValue, key: ZMUserSession.failedPasswordCountKey)
            self.managedObjectContext.saveOrRollback()
        }
    }
}


