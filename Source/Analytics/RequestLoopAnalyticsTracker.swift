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


final class RequestLoopAnalyticsTracker {

    private let ignoredSuffixes = [
        "/typing"
    ]
    
    weak var analytics: AnalyticsType?
    
    @objc(initWithAnalytics:)
    public init(with analytics : AnalyticsType?) {
        self.analytics = analytics
    }

    /// Track a loop at the given path.
    /// The path will be sanitized (UUIDs will be removed).
    /// - parameter path: The path to track a request loop for.
    /// - returns: `true` in case the tracking has been performed, `false` otherwise (e.g. when the path was in the ignored paths list).
    public func tag(with path: String) -> Bool {
        guard nil == ignoredSuffixes.first(where: path.hasSuffix) else { return false }
        if let analytics = analytics {
            analytics.tagEvent("request.loop", attributes: ["path": path.sanitizePath() as NSObject])
            return true
        } else {
            return false
        }
    }
}


extension String {

    static var uuidRegexp: NSRegularExpression? = {
        return try? NSRegularExpression(
            pattern: "[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{3,12}",
            options: .caseInsensitive
        )
    }()

    static var clientIdRegexp: NSRegularExpression? = {
        return try? NSRegularExpression(
            pattern: "[a-f0-9]{15,16}",
            options: .caseInsensitive
        )
    }()

    func sanitizePath()-> String {
        guard let uuidRegexp = String.uuidRegexp, let clientIdRegexp = String.clientIdRegexp else { return self }
        let mutableString = NSMutableString(string: self)
        let template = "{id}"
        uuidRegexp.replaceMatches(in: mutableString, options: [], range: NSMakeRange(0, mutableString.length), withTemplate: template)
        clientIdRegexp.replaceMatches(in: mutableString, options: [], range: NSMakeRange(0, mutableString.length), withTemplate: template)
        let swiftString = (mutableString as String).replacingOccurrences(of: ",\(template)", with: "")
        return swiftString
    }
}
