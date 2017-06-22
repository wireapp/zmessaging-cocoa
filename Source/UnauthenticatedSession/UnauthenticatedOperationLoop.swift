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

class UnauthenticatedOperationLoop: NSObject {
    
    let transportSession: ZMTransportSession
    let requestStrategies: [RequestStrategy]
    
    init(transportSession: ZMTransportSession, requestStrategies: [RequestStrategy]) {
        self.transportSession = transportSession
        self.requestStrategies = requestStrategies
        super.init()
        RequestAvailableNotification.addObserver(self)
    }
}

extension UnauthenticatedOperationLoop: RequestAvailableObserver {
    func newRequestsAvailable() {
        self.transportSession.attemptToEnqueueSyncRequest { () -> ZMTransportRequest? in
            return (self.requestStrategies as NSArray).nextRequest()
        }
    }
}
