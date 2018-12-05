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

@objc public enum SyncPhase : Int, CustomStringConvertible {
    case fetchingLastUpdateEventID
    case fetchingTeams
    case fetchingConnections
    case fetchingConversations
    case fetchingUsers
    case fetchingSelfUser
    case fetchingMissedEvents
    case done
    
    var isLastSlowSyncPhase : Bool {
        return self == .fetchingSelfUser
    }
    
    var isSyncing : Bool {
        switch self {
        case .fetchingMissedEvents,
             .fetchingLastUpdateEventID,
             .fetchingConnections,
             .fetchingTeams,
             .fetchingUsers,
             .fetchingConversations,
             .fetchingSelfUser:
            return true
        case .done:
            return false
        }
    }

    var nextPhase: SyncPhase? {
        return SyncPhase(rawValue: rawValue + 1)
    }
    
    public var description: String {
        switch self {
        case .fetchingLastUpdateEventID:
            return "fetchingLastUpdateEventID"
        case .fetchingConnections:
            return "fetchingConnections"
        case .fetchingConversations:
            return "fetchingConversations"
        case .fetchingTeams:
            return "fetchingTeams"
        case .fetchingUsers:
            return "fetchingUsers"
        case .fetchingSelfUser:
            return "fetchingSelfUser"
        case .fetchingMissedEvents:
            return "fetchingMissedEvents"
        case .done:
            return "done"
        }
    }
}

private let zmLog = ZMSLog(tag: "SyncStatus")


extension Notification.Name {

    public static let ForceSlowSync = Notification.Name("restartSlowSyncNotificationName")
    
}


@objcMembers public class SyncStatus : NSObject {

    fileprivate var previousPhase : SyncPhase = .done
    public internal (set) var currentSyncPhase : SyncPhase = .done {
        didSet {
            if currentSyncPhase != oldValue {
                zmLog.debug("did change sync phase: \(currentSyncPhase)")
                previousPhase = oldValue
            }
        }
    }

    fileprivate var lastUpdateEventID : UUID?
    fileprivate unowned var managedObjectContext: NSManagedObjectContext
    fileprivate unowned var syncStateDelegate: ZMSyncStateDelegate
    fileprivate var forceSlowSyncToken : Any?
    
    public internal (set) var isInBackground : Bool = false
    public internal (set) var needsToRestartQuickSync : Bool = false
    public internal (set) var pushChannelEstablishedDate : Date?
    
    fileprivate var pushChannelIsOpen : Bool {
        return pushChannelEstablishedDate != nil
    }
    
    public var isSyncing : Bool {
        return currentSyncPhase.isSyncing
    }
    
    public init(managedObjectContext: NSManagedObjectContext, syncStateDelegate: ZMSyncStateDelegate) {
        self.managedObjectContext = managedObjectContext
        self.syncStateDelegate = syncStateDelegate
        super.init()
        
        currentSyncPhase = hasPersistedLastEventID ? .fetchingMissedEvents : .fetchingLastUpdateEventID
        self.syncStateDelegate.didStartSync()
        
        self.forceSlowSyncToken = NotificationInContext.addObserver(name: .ForceSlowSync, context: managedObjectContext.notificationContext) { [weak self] (note) in
            self?.forceSlowSync()
        }
    }
    
    public func forceSlowSync() {
        // Refetch user settings.
        ZMUser.selfUser(in: managedObjectContext).needsPropertiesUpdate = true
        // Set the status.
        currentSyncPhase = SyncPhase.fetchingLastUpdateEventID.nextPhase!
        syncStateDelegate.didStartSync()
    }

}

// MARK: Slow Sync
extension SyncStatus {
    
    public func finishCurrentSyncPhase(phase : SyncPhase) {
        precondition(phase == currentSyncPhase, "Finished syncPhase does not match currentPhase")
        
        zmLog.debug("finished sync phase: \(phase)")
        
        guard let nextPhase = currentSyncPhase.nextPhase else { return }
        
        if currentSyncPhase.isLastSlowSyncPhase {
            persistLastUpdateEventID()
        }
        
        currentSyncPhase = nextPhase
        
        if currentSyncPhase == .done {
            if needsToRestartQuickSync && pushChannelIsOpen {
                // If the push channel closed while fetching notifications
                // We need to restart fetching the notification stream since we might be missing notifications
                currentSyncPhase = .fetchingMissedEvents
                needsToRestartQuickSync = false
                zmLog.debug("restarting quick sync since push channel was closed")
                return
            }
            
            zmLog.debug("sync complete")
            syncStateDelegate.didFinishSync()
            managedObjectContext.performGroupedBlock {
                ZMUserSession.notifyInitialSyncCompleted(context: self.managedObjectContext)
            }
        }
        RequestAvailableNotification.notifyNewRequestsAvailable(self)
    }
    
    public func failCurrentSyncPhase(phase : SyncPhase) {
        precondition(phase == currentSyncPhase, "Failed syncPhase does not match currentPhase")
        
        zmLog.debug("failed sync phase: \(phase)")
        
        if currentSyncPhase == .fetchingMissedEvents {
            managedObjectContext.zm_lastNotificationID = nil
            currentSyncPhase = .fetchingLastUpdateEventID
            needsToRestartQuickSync = false
        }
    }
    
    var hasPersistedLastEventID : Bool {
        return managedObjectContext.zm_lastNotificationID != nil
    }
    
    public func updateLastUpdateEventID(eventID : UUID) {
        zmLog.debug("update last eventID: \(eventID)")
        lastUpdateEventID = eventID
    }
    
    public func persistLastUpdateEventID() {
        guard let lastUpdateEventID = lastUpdateEventID else { return }
        zmLog.debug("persist last eventID: \(lastUpdateEventID)")
        managedObjectContext.zm_lastNotificationID = lastUpdateEventID
    }
}

// MARK: Quick Sync
extension SyncStatus {
    
    public func pushChannelDidClose() {
        pushChannelEstablishedDate = nil
        
        if !currentSyncPhase.isSyncing {
            // As soon as the pushChannel closes we should notify the UI that we are syncing (if we are not already syncing)
            self.syncStateDelegate.didStartSync()
        }
    }
    
    public func pushChannelDidOpen() {
        pushChannelEstablishedDate = Date()
        
        if !currentSyncPhase.isSyncing {
            // As soon as the pushChannel opens we should notify the UI that we are syncing (if we are not already syncing)
            self.syncStateDelegate.didStartSync()
        }
        
        if currentSyncPhase == .fetchingMissedEvents {
            // If the pushChannel closed while we are fetching the notifications, we might be missing notifications that are sent between the server response and the channel reopening
            // We therefore need to mark the quicksync to be restarted
            needsToRestartQuickSync = true
        }
        
        startQuickSyncIfNeeded()
    }
    
    func startQuickSyncIfNeeded() {
        guard self.currentSyncPhase == .done else { return }
        self.currentSyncPhase = .fetchingMissedEvents
    }
}

