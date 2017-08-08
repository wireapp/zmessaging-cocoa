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


public extension Bundle {
    var appGroupIdentifier: String? {
        return bundleIdentifier.map { "group." + $0 }
    }
}

@objc public protocol LocalStoreProviderProtocol: class {
    var userIdentifier: UUID { get }
    var sharedContainerDirectory: URL { get }
    var contextDirectory: ManagedObjectContextDirectory? { get }
}


/// Encapsulates all storage related data and methods. LocalStoreProviderProtocol protocol
/// is used instead of concrete class to let us inject a custom implementation in tests
@objc public class LocalStoreProvider: NSObject, LocalStoreProviderProtocol {
    public let userIdentifier: UUID
    public let sharedContainerDirectory: URL
    public var contextDirectory: ManagedObjectContextDirectory?
    private let dispatchGroup: ZMSDispatchGroup?

    @objc public init(sharedContainerDirectory: URL, userIdentifier: UUID, dispatchGroup: ZMSDispatchGroup? = nil) {
        self.userIdentifier = userIdentifier
        self.sharedContainerDirectory = sharedContainerDirectory
        self.dispatchGroup = dispatchGroup
    }

    public func createStorageStack(migration: (() -> Void)?, completion: @escaping (LocalStoreProviderProtocol) -> Void) {
        StorageStack.shared.createManagedObjectContextDirectory(
            accountIdentifier: userIdentifier,
            applicationContainer: sharedContainerDirectory,
            dispatchGroup: dispatchGroup,
            startedMigrationCallback: { migration?() },
            completionHandler: { [weak self] contextDirectory in
                guard let `self` = self else { return }
                self.contextDirectory = contextDirectory
                completion(self)
            }
        )
    }

    public static func fetchUserIDFromLegacyStore(
        in sharedContainer: URL,
        migration: (() -> Void)?,
        completion: @escaping (UUID?) -> Void
        ) {
        StorageStack.shared.fetchUserIDFromLegacyStore(
            applicationContainer: sharedContainer,
            startedMigrationCallback: migration,
            completionHandler: completion
        )
    }
}
