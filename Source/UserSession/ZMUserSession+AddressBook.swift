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

private let log = ZMSLog(tag: "AddressBook")

// MARK: - Upload observer
let failedToAccessAddressBookNotificationName = "ZMUserSessionFailedToAccessAddressBook"

@objc public protocol AddressBookUploadObserver {
    
    /// This method will get called when the app tries to upload the address book, but does not have access to it.
    func failedToAccessAddressBook(_ note: Notification)
}

extension ZMUserSession {
    
    /// Adds and observer for address book upload. Returns the token that need to be used
    /// to unregister the observer
    public static func addAddressBookUploadObserver(_ observer: AddressBookUploadObserver) -> NSObjectProtocol {
        return NotificationCenter.default
            .addObserver(forName: NSNotification.Name(rawValue: failedToAccessAddressBookNotificationName),
                                object: nil,
                                queue: OperationQueue.main) {
                                    observer.failedToAccessAddressBook($0)
        }
    }
    
    /// Removes and address book upload observer using the token returned from `addAddressBookUploadObserver`
    public static func removeAddressBookUploadObserverToken(_ token: NSObjectProtocol) {
        NotificationCenter.default.removeObserver(token)
    }
}

// MARK: - Address book upload
extension ZMUserSession {

    /// Asynchronously uploads the next chunk of the address book unless the user is in a team
    public func uploadAddressBookIfAllowed() {
        if ZMUser.selfUser(inUserSession: self).hasTeam {
            log.error("Uploading contacts for an account with team is a forbidden operation")
        } else {
            uploadAddressBook()
        }
    }

    /// Asynchronously uploads the next chunk of the address book
    private func uploadAddressBook() {
        AddressBook.markAddressBookAsNeedingToBeUploaded(self.managedObjectContext)
        self.managedObjectContext.forceSaveOrRollback()
    }

}
