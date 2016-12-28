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


extension NSManagedObjectContext {
    
    fileprivate static var lastAddressBookUploadDateKey: String { return "lastAddressBookUploadDate" }

    var lastAddressBookUploadDate: Date? {
        set { self.setPersistentStoreMetadata(newValue, key: NSManagedObjectContext.lastAddressBookUploadDateKey) }
        get { return self.persistentStoreMetadata(key: NSManagedObjectContext.lastAddressBookUploadDateKey) as? Date }
    }
}

protocol AddressBookTracker {
    
    /// Tracks the successfull upload of an AB batch
    func tagAddressBookUploadSuccess()
    
    /// Tracks the beginning of processing an AB batch
    func tagAddressBookUploadStarted(_ entireABsize: UInt)
}

final class AddressBookAnalytics: AddressBookTracker {
    
    let managedObjectContext : NSManagedObjectContext
    
    fileprivate enum Attribute: String {
        case Size = "size"
        case Interval = "interval"
    }
    
    fileprivate let startEventName = "connect.started_addressbook_search"
    fileprivate let endEventName = "connect.completed_addressbook_search"
    fileprivate let analytics: AnalyticsType?

    init(analytics: AnalyticsType?, managedObjectContext: NSManagedObjectContext) {
        self.analytics = analytics
        self.managedObjectContext = managedObjectContext
    }
    
    func tagAddressBookUploadStarted(_ entireABsize: UInt) {
        let attributes: [String: NSObject] = [
            Attribute.Size.rawValue: entireABsize as NSObject
        ]

        analytics?.tagEvent(startEventName, attributes: attributes)
    }
    
    func tagAddressBookUploadSuccess() {
        var attributes: [String: NSObject] = [:]
        if let interval = lastUploadInterval() {
            attributes[Attribute.Interval.rawValue] = interval as NSObject?
        }
        resetUploadInterval()
        analytics?.tagEvent(endEventName, attributes: attributes)
    }

    /// Returns the interval since the last address book upload in hours
    fileprivate func lastUploadInterval() -> UInt? {
        guard let lastDate = self.managedObjectContext.lastAddressBookUploadDate else { return nil }
        let seconds = -round(lastDate.timeIntervalSinceNow)
        guard !(seconds.sign == .minus) else { return nil }
        return UInt(seconds / 3600)
    }

    fileprivate func resetUploadInterval() {
        self.managedObjectContext.lastAddressBookUploadDate = Date()
    }

}
