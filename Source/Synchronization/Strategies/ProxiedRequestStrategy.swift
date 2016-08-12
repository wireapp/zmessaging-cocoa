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


extension ProxiedRequestType {
    var basePath: String {
        switch self {
        case .Giphy:
            return "/giphy"
        case .Soundcloud:
            return "/soundcloud"
        }
    }
}

/// Perform requests to the Giphy search API
@objc public class ProxiedRequestStrategy : NSObject, RequestStrategy {
    
    static private let BasePath = "/proxy"
    
    /// The requests to fulfill
    private weak var requestsStatus : ProxiedRequestsStatus?
    
    /// The managed object context to operate on
    private let managedObjectContext : NSManagedObjectContext
    
    /// Requests fail after this interval if the network is unreachable
    private static let RequestExpirationTime : NSTimeInterval = 20
    
    public init(requestsStatus: ProxiedRequestsStatus, managedObjectContext: NSManagedObjectContext) {
        self.requestsStatus = requestsStatus
        self.managedObjectContext = managedObjectContext
    }
    
    public func nextRequest() -> ZMTransportRequest? {
        
        guard let status = self.requestsStatus else { return nil }
        
        if(status.pendingRequests.count > 0) {
            let (type, path, method, callback) = status.pendingRequests.removeAtIndex(0)
            let fullPath = ProxiedRequestStrategy.BasePath + type.basePath + path
            let request = ZMTransportRequest(path: fullPath, method: method, payload: nil)
            if type == .Soundcloud {
                request.doesNotFollowRedirects = true
            }
            request.expireAfterInterval(ProxiedRequestStrategy.RequestExpirationTime)
            request.addCompletionHandler(ZMCompletionHandler(onGroupQueue: self.managedObjectContext.zm_userInterfaceContext, block: {
                response in
                    callback?(response.rawData, response.rawResponse, response.transportSessionError)
            }))
            return request
        }
        
        return nil
    }
    
    /**
    Schedules a request to be sent to the backend.
    
    - parameter timeout: If it is not completed in the given interval, the request is completed with error
    */
    public func scheduleAuthenticatedRequestWithCompletionHandler(relativeUrl: NSURL, completionHandler: ((NSData!, NSURLResponse!, NSError!) -> Void), timeout: NSTimeInterval) {
        
    }
}
