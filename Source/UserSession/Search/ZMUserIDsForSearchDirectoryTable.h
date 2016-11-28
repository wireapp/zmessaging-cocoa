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


@import Foundation;

@class ZMSearchDirectory;
@class ZMSearchUser;
@protocol ZMSearchResultStore;


@interface ZMSearchUserAndAssetID : NSObject

@property (nonatomic, readonly) ZMSearchUser *searchUser;
@property (nonatomic, readonly) NSUUID *assetID;
@property (nonatomic, readonly) NSUUID *userID;

- (instancetype)initWithSearchUser:(ZMSearchUser *)searchUser assetID:(NSUUID *)assetID;

@end



/// This call is thread safe.
@interface ZMUserIDsForSearchDirectoryTable : NSObject

/// returns a set of NSUUID
@property (nonatomic, readonly) NSSet<NSUUID*> *allUserIDs;
/// returns a set of ZMUserIDAndAssetID
@property (nonatomic, readonly) NSSet<ZMSearchUserAndAssetID*> *allAssetIDs;

/// sets the search users that need a profile picture for a given search directory
- (void)setSearchUsers:(NSSet *)searchUsers forSearchDirectory:(id<ZMSearchResultStore>)directory;

/// Replace all user ID to download with an asset ID to download
- (void)replaceUserIDToDownload:(NSUUID *)userID withAssetIDToDownload:(NSUUID *)assetID;

/// Remove all entries that contain these user IDs
- (void)removeAllEntriesWithUserIDs:(NSSet<NSUUID*> *)userIDs;

/// Remove the search directory from the table
- (void)removeSearchDirectory:(ZMSearchDirectory *)directory;

/// removes all
- (void)clear;

@end
