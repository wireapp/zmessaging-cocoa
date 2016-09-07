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
@import WireRequestStrategy;

@class ZMUserIDsForSearchDirectoryTable;
@class ZMAssetIDsForSearchDirectoryTable;

@interface ZMSearchUserImageTranscoder : ZMObjectSyncStrategy <ZMObjectStrategy>

@property (nonatomic, readonly) ZMUserIDsForSearchDirectoryTable* userIDsTable;
@property (nonatomic, readonly) NSCache *imagesByUserIDCache;

- (instancetype)initWithManagedObjectContext:(NSManagedObjectContext *)moc
                                   uiContext:(NSManagedObjectContext *)uiContext;

- (instancetype)initWithManagedObjectContext:(NSManagedObjectContext *)moc
                                   uiContext:(NSManagedObjectContext *)uiContext
             userIDsWithoutProfileImageTable:(ZMUserIDsForSearchDirectoryTable *)userIDsTable
                         imagesByUserIDCache:(NSCache *)cache
                  mediumAssetIDByUserIDCache:(NSCache *)mediumAssetIDByUserIDCache;


+ (ZMTransportRequest *)fetchAssetsForUsersWithIDs:(NSSet *)userIDsToDownload completionHandler:(ZMCompletionHandler *)completionHandler;
+ (void)processSingleUserProfileResponse:(ZMTransportResponse *)response forUserID:(NSUUID *)userID mediumAssetIDCache:(NSCache *)mediumAssetIDCache;


@end



@interface ZMSearchUserAssetIDs : NSObject

@property (nonatomic) NSUUID *smallImageAssetID;
@property (nonatomic) NSUUID *mediumImageAssetID;

- (instancetype)initWithUserImageResponse:(NSArray *)response;

@end

