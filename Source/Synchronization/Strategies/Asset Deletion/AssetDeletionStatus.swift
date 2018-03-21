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

private let log = ZMSLog(tag: "AssetDeletion")

public protocol AssetDeletionIdentifierProviderType: class {
    func nextIdentifierToDelete() -> String?
    func didDelete(identifier: String)
    func didFailToDelete(identifier: String)
}

final public class AssetDeletionStatus: NSObject, AssetDeletionIdentifierProviderType {
    
    private var provider: DeletableAssetIdentifierProvider
    private var identifiersInProgress = Set<String>()
    
    private var remainingIdentifiersToDelete: Set<String> {
        return provider.assetIdentifiersToBeDeleted.subtracting(identifiersInProgress)
    }
    
    init(provider: DeletableAssetIdentifierProvider) {
        self.provider = provider
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(handle), name: .deleteAssetNotification, object: nil)
    }
    
    @objc private func handle(note: Notification) {
        guard note.name == Notification.Name.deleteAssetNotification, let identifier = note.object as? String else { return }
        provider.assetIdentifiersToBeDeleted.insert(identifier)
        RequestAvailableNotification.notifyNewRequestsAvailable(nil)
        log.debug("Added asset identifier to list: \(identifier)")
    }
    
    private func remove(_ identifier: String) {
        identifiersInProgress.remove(identifier)
        provider.assetIdentifiersToBeDeleted.remove(identifier)
    }
    
    // MARK: - AssetDeletionIdentifierProviderType
    
    public func nextIdentifierToDelete() -> String? {
        guard let first = remainingIdentifiersToDelete.first else { return nil }
        identifiersInProgress.insert(first)
        return first
    }
    
    public func didDelete(identifier: String) {
        remove(identifier)
        log.debug("Successfully deleted identifier: \(identifier)")
    }
    
    public func didFailToDelete(identifier: String) {
        remove(identifier)
        log.debug("Failed to delete identifier: \(identifier)")
    }
}
