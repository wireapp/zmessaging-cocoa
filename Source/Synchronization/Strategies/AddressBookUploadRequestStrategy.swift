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

// TODO MARCO: add tracking

/// BE onboarding endpoint
private let onboardingEndpoint = "/onboarding/v3"

/// Maximum entries in an address book chunk
let maxEntriesInAddressBookChunk : UInt = 1000

/// Key to mark the address book as uploadable
private let addressBookNeedsToBeUploadedKey = "ZMAddressBookTranscoderNeedsToBeUploaded"

/// Last contact index to be uploaded
private let addressBookLastUploadedIndex = "ZMAddressBookTranscoderLastIndexUploaded"

/// This request sync generates request to upload the address book
/// It will upload only after `markAddressBookAsNeedingToBeUploaded` is called
@objc class AddressBookUploadRequestStrategy: NSObject {
    
    /// Auth status to know whether we can make requests
    private let authenticationStatus : AuthenticationStatusProvider
    
    /// Client status to know whether we can make requests
    private let clientRegistrationStatus : ZMClientClientRegistrationStatusProvider
    
    /// Managed object context where to perform all operations
    private let managedObjectContext: NSManagedObjectContext
    
    /// Request sync to upload the address book
    private var requestSync : ZMSingleRequestSync!
    
    /// Encoded address book chunk
    private var encodedAddressBookChunk : EncodedAddressBookChunk? = nil
    
    /// Is the payload being generated? This is an async operation
    private var isGeneratingPayload : Bool = false
    
    /// Address book analytics events tracker
    private let tracker : AddressBookTracker
    
    /// Address book
    private let addressBookGenerator : ()->(AddressBookAccessor?)
    
    init(authenticationStatus: AuthenticationStatusProvider,
                clientRegistrationStatus: ZMClientClientRegistrationStatusProvider,
                managedObjectContext: NSManagedObjectContext,
                addressBookGenerator: ()->(AddressBookAccessor?) = { return AddressBook() },
                tracker: AddressBookTracker? = nil
                )
    {
        // notify of denied access
        if addressBookGenerator() == nil {
            NSNotificationCenter.defaultCenter().postNotificationName(failedToAccessAddressBookNotificationName, object: nil)
        }
        
        self.authenticationStatus = authenticationStatus
        self.clientRegistrationStatus = clientRegistrationStatus
        self.managedObjectContext = managedObjectContext
        self.addressBookGenerator = addressBookGenerator
        self.tracker = tracker ?? AddressBookTracker(analytics: managedObjectContext.analytics)
        super.init()
        self.requestSync = ZMSingleRequestSync(singleRequestTranscoder: self, managedObjectContext: managedObjectContext)
    }
}

// MARK: - Request generation logic
extension AddressBookUploadRequestStrategy : RequestStrategy, ZMSingleRequestTranscoder {
    
    func nextRequest() -> ZMTransportRequest? {
        guard self.authenticationStatus.currentPhase == .Authenticated &&
            self.clientRegistrationStatus.currentClientReadyToUse else {
                return nil
        }
        
        // already encoded? just send it
        if self.encodedAddressBookChunk != nil {
            return self.requestSync.nextRequest()
        }
        
        self.generateAddressBookPayloadIfNeeded()
        return nil
    }
    
    func requestForSingleRequestSync(sync: ZMSingleRequestSync!) -> ZMTransportRequest! {
        guard sync == self.requestSync, let encodedChunk = self.encodedAddressBookChunk else {
            return nil
        }
        let contactCards = encodedChunk.otherContactsHashes
            .enumerate()
            .map { (index, hashes) -> [String:AnyObject] in
                return [
                    "card_id" : "\(encodedChunk.includedContacts.startIndex + UInt(index))",
                    "contact" : hashes
                ]
        }
        let payload = ["cards" : contactCards]
        return ZMTransportRequest(path: onboardingEndpoint, method: .MethodPOST, payload: payload, shouldCompress: true)
    }
    
    func didReceiveResponse(response: ZMTransportResponse!, forSingleRequest sync: ZMSingleRequestSync!) {
        if response.result == .Success {
            // TODO MARCO: suggested users
            self.managedObjectContext.suggestedUsersForUser = NSOrderedSet()
            self.managedObjectContext.commonConnectionsForUsers = [:]
            self.addressBookNeedsToBeUploaded = false
            self.encodedAddressBookChunk = nil
        }
    }
    
    /// Checks if it needs to generate address book payload. If it does,
    /// it will start generating it asynchronously
    private func generateAddressBookPayloadIfNeeded() {
        
        guard self.addressBookNeedsToBeUploaded &&
            !self.isGeneratingPayload,
            let addressBook = self.addressBookGenerator() else {
                return
        }
        
        self.isGeneratingPayload = true
        let startIndex = self.lastUploadedCardIndex
        addressBook.encodeWithCompletionHandler(self.managedObjectContext,
                                                startingContactIndex: startIndex,
                                                maxNumberOfContacts: maxEntriesInAddressBookChunk)
        {
            [weak self] encodedChunk in
            guard let strongSelf = self else {
                return
            }
            strongSelf.isGeneratingPayload = false
            if let encodedChunk = encodedChunk {
                let lastIndex = encodedChunk.includedContacts.endIndex
                let isEndOfCards = lastIndex >= encodedChunk.numberOfTotalContacts - 1
                // is this the last card? if it is, reset to 0 so it will restart
                strongSelf.lastUploadedCardIndex = isEndOfCards ? 0 : lastIndex
                strongSelf.encodedAddressBookChunk = encodedChunk
                strongSelf.requestSync.readyForNextRequest()
                ZMOperationLoop.notifyNewRequestsAvailable(strongSelf)
            }
        }
    }
}

// MARK: - Marking for upload
extension AddressBook {
    /// Sets the address book as needing to be uploaded
    static func markAddressBookAsNeedingToBeUploaded(moc: NSManagedObjectContext) {
        self.markAddressBook(moc, needsToBeUploaded: true)
    }
    
    /// Sets whether the address book needs to be uploaded
    private static func markAddressBook(moc: NSManagedObjectContext, needsToBeUploaded: Bool) {
        moc.setPersistentStoreMetadata(NSNumber(bool: needsToBeUploaded), forKey: addressBookNeedsToBeUploadedKey)
    }
    
    /// Whether the address book needs to be uploaded
    private static func addressBookNeedsToBeUploaded(moc: NSManagedObjectContext) -> Bool {
        return (moc.persistentStoreMetadataForKey(addressBookNeedsToBeUploadedKey) as? NSNumber)?.boolValue == true
    }
}

extension AddressBookUploadRequestStrategy {
    
    /// Whether the address book needs to be uploaded
    private var addressBookNeedsToBeUploaded : Bool {
        get {
            return AddressBook.addressBookNeedsToBeUploaded(self.managedObjectContext)
        }
        set {
            AddressBook.markAddressBook(self.managedObjectContext, needsToBeUploaded: newValue)
        }
    }
    
    /// Index of last uploaded contact card
    /// - note: This value does not offers any guarantee on which cards
    /// where uploaded, just on the index on the card uploaded. Cards might have
    /// changed since last time and the index might be pointing to a different card.
    /// However, since we want to upload all cards and then restart from the first, we
    /// uploaded the same cards over and over anyway and will eventually go through the
    /// entire AB.
    private var lastUploadedCardIndex : UInt {
        get {
            return UInt((self.managedObjectContext
                .persistentStoreMetadataForKey(addressBookLastUploadedIndex) as? NSNumber)?.integerValue ?? 0)
        }
        set {
            self.managedObjectContext
                .setPersistentStoreMetadata(NSNumber(integer: Int(newValue)), forKey: addressBookLastUploadedIndex)
        }
    }
}