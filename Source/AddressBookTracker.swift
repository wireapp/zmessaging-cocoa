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


extension NSUserDefaults {
    private var lastAddressBookUploadDateKey: String { return "lastAddressBookUploadDate" }

    var lastAddressBookUploadDate: NSDate? {
        set { setObject(newValue, forKey: lastAddressBookUploadDateKey) }
        get { return objectForKey(lastAddressBookUploadDateKey) as? NSDate }
    }
}


@objc final public class AddressBookTracker: NSObject {
    
    private enum Attribute: String {
        case Outcome = "outcome"
        case Size = "size"
        case Interval = "interval"
    }
    
    private let eventName = "connect.checked_for_address_book_changes"
    private let analytics: AnalyticsType?

    public init(analytics: AnalyticsType?) {
        self.analytics = analytics
        super.init()
    }
    
    /// Tracks the size, interval and if there have been changes to the address book
    /// - param changed if the address book content changed since the last upload (it will not be uploaded if not)
    /// - param size the size of the addressbook (max 1000)
    public func tagAddressBookUpload(changed: Bool, size: UInt) {
        var attributes: [String: NSObject] = [
            Attribute.Outcome.rawValue: changed ? "changed" : "no_changes",
            Attribute.Size.rawValue: size
        ]

        if let interval = lastUploadInterval() {
            attributes[Attribute.Interval.rawValue] = interval
            resetUploadInterval()
        }

        analytics?.tagEvent(eventName, attributes: attributes)
    }

    /// Returns the interval since the last address book upload in hours
    private func lastUploadInterval() -> UInt? {
        guard let lastDate = NSUserDefaults.standardUserDefaults().lastAddressBookUploadDate else { return nil }
        let seconds = -round(lastDate.timeIntervalSinceNow)
        guard !seconds.isSignMinus else { return nil }
        return UInt(seconds / 3600)
    }

    private func resetUploadInterval() {
        NSUserDefaults.standardUserDefaults().lastAddressBookUploadDate = NSDate()
    }

}
