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

protocol AddressBookTracker {
    
    /// Tracks the successfull upload of an AB batch
    func tagAddressBookUploadSuccess()
    
    /// Tracks the beginning of processing an AB batch
    func tagAddressBookUploadStarted(entireABsize: UInt)
}

final class AddressBookAnalytics: AddressBookTracker {
    
    private enum Attribute: String {
        case Size = "size"
        case Interval = "interval"
    }
    
    private let startEventName = "connect.started_addressbook_search"
    private let endEventName = "connect.completed_addressbook_search"
    private let analytics: AnalyticsType?

    init(analytics: AnalyticsType?) {
        self.analytics = analytics
    }
    
    func tagAddressBookUploadStarted(entireABsize: UInt) {
        let attributes: [String: NSObject] = [
            Attribute.Size.rawValue: entireABsize
        ]

        analytics?.tagEvent(startEventName, attributes: attributes)
    }
    
    func tagAddressBookUploadSuccess() {
        var attributes: [String: NSObject] = [:]
        if let interval = lastUploadInterval() {
            attributes[Attribute.Interval.rawValue] = interval
            resetUploadInterval()
        }
        
        analytics?.tagEvent(endEventName, attributes: attributes)
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
