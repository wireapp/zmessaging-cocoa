//
// Wire
// Copyright (C) 2018 Wire Swiss GmbH
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

/// CallEventStatus keep track of call events which are waiting to be processed. this is important to know when
/// the app is launched via push notification since then we need keep the app running until we've processed all
/// call events.
@objcMembers
public class CallEventStatus: NSObject {
    
    var eventProcessingTimoutInterval: TimeInterval = 2
    
    fileprivate var observers: [() -> Void] = []
    fileprivate var eventProcessingTimer: Timer? = nil
    fileprivate var callEventsWaitingToBeProcessed: Int = 0 {
        didSet {
            if callEventsWaitingToBeProcessed == 0 {
                eventProcessingTimer = Timer.scheduledTimer(withTimeInterval: eventProcessingTimoutInterval, repeats: false) { [weak self] (timer) in
                    self?.observers.forEach({ $0() })
                    self?.observers = []
                }
            }
        }
    }
    
    deinit {
        eventProcessingTimer?.invalidate()
        eventProcessingTimer = nil
    }
    
    /// Wait for all calling events to be processed and then calls the completion handler.
    ///
    /// NOTE it is not guranteed that completion handler is called on the same thread as the caller.
    ///
    /// Returns: true if there's was any unprocessed calling events.
    @discardableResult
    public func waitForCallEventProcessingToComplete(_ completionHandler: @escaping () -> Void) -> Bool {
        guard callEventsWaitingToBeProcessed != 0 || eventProcessingTimer != nil else {
            completionHandler()
            return false
        }
        
        observers.append(completionHandler)
        return true
    }
    
    public func scheduledCallEventForProcessing() {
        callEventsWaitingToBeProcessed += 1
    }
    
    public func finishedProcessingCallEvent() {
        callEventsWaitingToBeProcessed -= 1
    }
    
}
