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

@objc public class RequestLoopAnalyticsTracker : NSObject {
    
    weak var analytic : AnalyticsType?
    
    @objc(initWithAnalytics:)
    public init(with : AnalyticsType) {
        analytic = with
    }

    @objc(tagWithPath:)
    public func tag(with: String) -> Void {
        if let analytic = analytic {
            analytic.tagEvent("request.loop", attributes: ["path": with as NSObject])
        }
    }
}
