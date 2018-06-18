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



import WireDataModel


final public class SearchUserAndAsset: NSObject {

    let user: ZMSearchUser
    var asset: SearchUserAsset = nil

    var userIdIfThereIsNoAssetId: UUID? {
        return asset == nil ? userId : nil
    }

    var userId: UUID {
        return user.remoteIdentifier!
    }

    public init(searchUser: ZMSearchUser) {
        user = searchUser
        super.init()
    }

    public convenience init(searchUser: ZMSearchUser, legacyID: UUID) {
        self.init(searchUser: searchUser)
        asset = .legacyId(legacyID)
    }

    public convenience init(searchUser: ZMSearchUser, assetKey: String) {
        self.init(searchUser: searchUser)
        asset = .assetKey(assetKey)
    }

    override public func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? SearchUserAndAsset else { return false }
        return asset == other.asset && user == other.user
    }

    override public var hashValue: Int {
        return userId.hashValue ^ asset.hashValue
    }
}


@objc public final class SearchDirectoryUserIDTable: NSObject {

    private let isolation = DispatchQueue(label: "SearchDirectoryUserIDTable.isolation", attributes: .concurrent)
    private var entries = [NSObject: Set<SearchUserAndAsset>]() // TODO: Use ZMSearchResultStore instead of NSObject

    public func allUserIds() -> Set<UUID> {
        return mapUsersAndAssets { $0.userIdIfThereIsNoAssetId }
    }

    func allUsersWithLegacyIds() -> Set<SearchUserAndAsset> {
        return mapUsersAndAssets {
            switch $0.asset {
            case .legacyId: return $0
            default: return nil
            }
        }
    }

    func allUsersWithAssetKeys() -> Set<SearchUserAndAsset> {
        return mapUsersAndAssets {
            switch $0.asset {
            case .assetKey: return $0
            default: return nil
            }
        }
    }

    public func allUsersWithAssets() -> Set<SearchUserAndAsset> {
        return mapUsersAndAssets {
            switch $0.asset {
            case .assetKey, .legacyId: return $0
            default: return nil
            }
        }
    }

    private func mapUsersAndAssets<Result>(_ block: @escaping (SearchUserAndAsset) -> Result?) -> Set<Result> {
        var result = Set<Result>()
        isolation.sync {
            let allSearchUsers = entries.values.reduce(Set<SearchUserAndAsset>(), { $1.union($0) })
            result = Set(allSearchUsers.compactMap(block))
        }
        return result
    }

    @objc(setSearchUsers:forSearchDirectory:)
    public func setUsers(_ users: Set<ZMSearchUser>, forDirectory directory: NSObject) {
        isolation.barrierAsync { [weak self] in
            guard let `self` = self else { return }
            let previous = self.entries[directory]
            let userIdsToPrevious = previous?.dictionary { ($0.userId, $0) }
            self.entries[directory] = Set(users.map {
                if let previous = userIdsToPrevious?[$0.remoteIdentifier!] {
                    return previous
                }
                else if let assetKeyObject = ZMSearchUser.searchUserToMediumAssetIDCache().object(forKey: $0.remoteIdentifier as AnyObject) as? SearchUserAssetObjC,
                    let assetKey = assetKeyObject.assetKey {
                    return SearchUserAndAsset(searchUser: $0, assetKey: assetKey)
                }
                else {
                    return SearchUserAndAsset(searchUser: $0)
                }
            })
        }
    }

    func replaceUserId(_ userId: UUID, withAsset asset: SearchUserAsset) {
        isolation.barrierAsync { [weak self] in
            self?.entries.values.forEach {
                $0.forEach { userAndAsset in
                    if userAndAsset.userId == userId {
                        userAndAsset.asset = asset
                    }
                }
            }
        }
    }

    func removeAllEntries(with userIds: Set<UUID>) {
        isolation.barrierAsync { [weak self] in
            guard let `self` = self else { return }
            self.entries.keys.forEach {
                if let entries = self.entries[$0] {
                    self.entries[$0] = Set(entries.filter { !userIds.contains($0.userId) })
                }
            }
        }
    }

    @objc(removeSearchDirectory:)
    public func removeDirectory(_ directory: NSObject) {
        isolation.barrierAsync { [weak self] in
            _ = self?.entries.removeValue(forKey: directory)
        }
    }

    @objc public func clear() {
        isolation.barrierSync { [weak self] in
            self?.entries.removeAll()
        }
    }

}


extension DispatchQueue {

    func barrierAsync(execute block: @escaping () -> Void) {
        async(flags: .barrier, execute: block)
    }
    
    func barrierSync(execute block: @escaping () -> Void) {
        sync(flags: .barrier, execute: block)
    }
}
