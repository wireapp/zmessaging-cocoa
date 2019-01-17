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

import UIKit

@objc open class BackgroundAPNSConfirmationStatus : NSObject, DeliveryConfirmationDelegate {
    
    /// Switch for sending delivery receipts
    public static let sendDeliveryReceipts : Bool = true
    static let backgroundNameBase : String = "Sending confirmation message with nonce"
    
    let backgroundTime : TimeInterval = 25
    fileprivate var tornDown = false
    fileprivate var messageNonces : [UUID : BackgroundActivity] = [:]
    private unowned var application : ZMApplication
    private unowned var managedObjectContext : NSManagedObjectContext

    open var needsToSyncMessages : Bool {
        return messageNonces.count > 0 && application.applicationState == .background
    }
    
    @objc public init(application: ZMApplication,
                      managedObjectContext: NSManagedObjectContext) {
        self.application = application
        self.managedObjectContext = managedObjectContext
        
        super.init()
    }

    deinit {
        assert(tornDown, "Needs to tear down BackgroundAPNSConfirmationStatus")
    }
    
    // Called after a confirmation message has been created from an event received via APNS
    public func needsToConfirmMessage(_ messageNonce: UUID) {
        let backgroundTask = BackgroundActivityFactory.shared.startBackgroundActivity(withName: "Confirming message with nonce: \(messageNonce.transportString())") { [weak self] in
            guard let strongSelf = self else { return }
            // The message failed to send in time. We won't continue trying.
            strongSelf.managedObjectContext.performGroupedBlock{
                strongSelf.messageNonces.removeValue(forKey: messageNonce)
            }
        }
        managedObjectContext.performGroupedBlock{
            self.messageNonces[messageNonce] = backgroundTask
        }
    }
    
    // Called after a confirmation message has made the round-trip to the backend and was successfully sent
    public func didConfirmMessage(_ messageNonce: UUID) {
        managedObjectContext.performGroupedBlock{
            guard let activity = self.messageNonces.removeValue(forKey: messageNonce) else { return }
            BackgroundActivityFactory.shared.endBackgroundActivity(activity)
        }
    }
}

extension BackgroundAPNSConfirmationStatus: TearDownCapable {
    public func tearDown(){
        messageNonces.values.forEach(BackgroundActivityFactory.shared.endBackgroundActivity)
        messageNonces.removeAll()
        tornDown = true
    }
}

