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

/// BE onboarding endpoint
private let onboardingEndpoint = "/onboarding/v3"


/// This request sync generates request to upload the address book
/// It will upload only after `markAddressBookAsNeedingToBeUploaded` is called
@objc public final class SelfContactCardUploadStrategy: NSObject {
    
    /// Auth status to know whether we can make requests
    fileprivate let authenticationStatus : AuthenticationStatusProvider
    
    /// Client status to know whether we can make requests
    fileprivate let clientRegistrationStatus : ClientRegistrationDelegate
    
    /// Managed object context where to perform all operations
    fileprivate let managedObjectContext: NSManagedObjectContext
    
    /// Request sync to upload the address book
    fileprivate var requestSync : ZMSingleRequestSync!
    
    public init(authenticationStatus: AuthenticationStatusProvider,
         clientRegistrationStatus: ClientRegistrationDelegate,
         managedObjectContext: NSManagedObjectContext)
    {

        self.authenticationStatus = authenticationStatus
        self.clientRegistrationStatus = clientRegistrationStatus
        self.managedObjectContext = managedObjectContext
        super.init()
        self.requestSync = ZMSingleRequestSync(singleRequestTranscoder: self, managedObjectContext: managedObjectContext)
    }
}

// MARK: - Request generation logic
extension SelfContactCardUploadStrategy : RequestStrategy, ZMSingleRequestTranscoder {
    
    public func nextRequest() -> ZMTransportRequest? {
        guard self.authenticationStatus.currentPhase == .authenticated &&
            self.clientRegistrationStatus.clientIsReadyForRequests else {
                return nil
        }
        
        if self.managedObjectContext.selfContactCardNeedsToBeUploaded
            || !self.managedObjectContext.hasEverUploadedSelfCard {
            self.requestSync.readyForNextRequestIfNotBusy()
        }
        return self.requestSync.nextRequest()
    }
    
    public func request(for sync: ZMSingleRequestSync) -> ZMTransportRequest? {
        guard sync == self.requestSync else {
            return nil
        }
        let hashes = ZMUser.selfUser(in: self.managedObjectContext).contactHashes
        let payload : [String: Any] = ["cards" : [], "self" : hashes]
        return ZMTransportRequest(path: onboardingEndpoint, method: .methodPOST, payload: payload as ZMTransportData?, shouldCompress: true)
    }
    
    public func didReceive(_ response: ZMTransportResponse, forSingleRequest sync: ZMSingleRequestSync) {
        if response.result == .success {
            self.managedObjectContext.selfContactCardNeedsToBeUploaded = false
            self.managedObjectContext.hasEverUploadedSelfCard = true
        }
    }
}

// MARK: - Marking for upload

/// Whether the self card was ever uploaded from this client
private let hasEverUploadedCardKey = "ZMhasEverUploadedSelfCard"

/// Key to mark the address book as uploadable
private let selfContactCardNeedsToBeUploadedKey = "ZMselfContactCardNeedsToBeUploaded"

extension NSManagedObjectContext {
    
    public var selfContactCardNeedsToBeUploaded : Bool {
        get {
            guard let uploaded = self.persistentStoreMetadata(forKey: selfContactCardNeedsToBeUploadedKey) as? NSNumber else {
                return false
            }
            return uploaded.boolValue
        }
        set {
            self.setPersistentStoreMetadata(NSNumber(value: newValue), key: selfContactCardNeedsToBeUploadedKey)
        }
    }
    
    var hasEverUploadedSelfCard : Bool {
        get {
            guard let uploaded = self.persistentStoreMetadata(forKey: hasEverUploadedCardKey) as? NSNumber else {
                return false
            }
            return uploaded.boolValue
        }
        set {
            self.setPersistentStoreMetadata(NSNumber(value: newValue), key: hasEverUploadedCardKey)
        }
    }
    
}
