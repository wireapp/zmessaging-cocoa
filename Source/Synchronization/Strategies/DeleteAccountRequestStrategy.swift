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
import ZMTransport

/// Requests the account deletion
@objc public final class DeleteAccountRequestStrategy: NSObject, RequestStrategy, ZMSingleRequestTranscoder {

    fileprivate static let path: String = "/self"
    public static let userDeletionInitiatedKey: String = "ZMUserDeletionInitiatedKey"
    
    fileprivate(set) var deleteSync: ZMSingleRequestSync! = nil
    /// The managed object context to operate on
    fileprivate let managedObjectContext: NSManagedObjectContext
    fileprivate let authStatus: ZMAuthenticationStatus
    
    public init(authStatus: ZMAuthenticationStatus, managedObjectContext: NSManagedObjectContext) {
        self.authStatus = authStatus
        self.managedObjectContext = managedObjectContext
        super.init()
        self.deleteSync = ZMSingleRequestSync(singleRequestTranscoder: self, managedObjectContext: self.managedObjectContext)
    }
    
    public func nextRequest() -> ZMTransportRequest? {
        guard let shouldBeDeleted : NSNumber = self.managedObjectContext.persistentStoreMetadata(forKey: DeleteAccountRequestStrategy.userDeletionInitiatedKey) as? NSNumber
            , shouldBeDeleted.boolValue
        else {
            return nil
        }
        
        self.deleteSync.readyForNextRequestIfNotBusy()
        return self.deleteSync.nextRequest()
    }
    
    // MARK: - ZMSingleRequestTranscoder
    
    public func request(for sync: ZMSingleRequestSync!) -> ZMTransportRequest! {
        let request = ZMTransportRequest(path: type(of: self).path, method: .methodDELETE, payload: ([:] as ZMTransportData), shouldCompress: true)
        return request
    }
    
    public func didReceive(_ response: ZMTransportResponse!, forSingleRequest sync: ZMSingleRequestSync!) {
        if response.result == .success || response.result == .permanentError {
            self.managedObjectContext.setPersistentStoreMetadata(NSNumber(value: false), key: DeleteAccountRequestStrategy.userDeletionInitiatedKey)
            ZMPersistentCookieStorage.deleteAllKeychainItems()
            OperationQueue.main.addOperation({ () -> Void in
                ZMUserSessionAuthenticationNotification.notifyAuthenticationDidFail(NSError.userSessionErrorWith(.accountDeleted, userInfo: .none))
            })
        }
    }
}
