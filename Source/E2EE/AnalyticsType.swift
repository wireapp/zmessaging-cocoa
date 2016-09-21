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

@objc public protocol AnalyticsType: NSObjectProtocol {
    
    func tagEvent(_ event: String)
    func tagEvent(_ event: String, attributes: [String: NSObject])
    func upload()
    
}

// Used for debugging only
@objc public final class DebugAnalytics: NSObject, AnalyticsType {
    
    public func tagEvent(_ event: String) {
        print(Date(), "[ANALYTICS]", #function, event)
    }
    
    public func tagEvent(_ event: String, attributes: [String : NSObject]) {
        print(Date(), "[ANALYTICS]", #function, event, attributes)
    }
    
    public func upload() {
        print(Date(), "[ANALYTICS]", #function)
    }
}
