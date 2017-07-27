//
// Wire
// Copyright (C) 2017 Wire Swiss GmbH
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
import WireTransport
import WireMessageStrategy

class UnauthenticatedOperationLoop: NSObject {
    
    let transportSession: TransportSession
    let requestStrategies: [RequestStrategy]
    let operationQueue : ZMSGroupQueue
    
    init(transportSession: TransportSession, operationQueue: ZMSGroupQueue, requestStrategies: [RequestStrategy]) {
        self.transportSession = transportSession
        self.requestStrategies = requestStrategies
        self.operationQueue = operationQueue
        super.init()
        RequestAvailableNotification.addObserver(self)
    }
    
    deinit {
        requestStrategies.forEach({ ($0 as? TearDownCapable)?.tearDown() })
    }
}

extension UnauthenticatedOperationLoop: RequestAvailableObserver {
    func newRequestsAvailable() {
        self.transportSession.attemptToEnqueueSyncRequestWithGenerator { () -> ZMTransportRequest? in
            let request = (self.requestStrategies as NSArray).nextRequest()
            
            request?.add(ZMCompletionHandler(on: self.operationQueue, block: {_ in
                self.operationQueue.performGroupedBlock { [weak self] in
                    self?.newRequestsAvailable()
                }
            }))
            
            return request
        }
    }
}
