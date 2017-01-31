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

@class ZMHotFixDirectory;

extern NSString * const ZMSkipHotfix;

@interface ZMVersion : NSObject

@property (nonatomic, readonly) NSArray *arrayRepresentation;
@property (nonatomic, readonly) NSString *versionString;

- (instancetype)initWithVersionString:(NSString *)versionString;
- (NSComparisonResult)compareWithVersion:(ZMVersion *)otherVersion;

@end




@interface ZMHotFix : NSObject

- (instancetype)initWithSyncMOC:(NSManagedObjectContext *)syncMOC;

/// It checks if there is a last version stored in the persistentStore and then applies patches (once) for older versions and saves the current version in the persistentStore.
/// This executes only the patches that are supposed to be executed at startup (as soon as the database is loaded)
- (void)applyPatchesAtStartup;

/// It checks if there is a last version stored in the persistentStore and then applies patches (once) for older versions and saves the current version in the persistentStore
/// This executes only the patches that are supposed to be executed after processing the notification stream
- (void)applyPatchesAfterSyncCompleted;


@end


@interface ZMHotFix (Testing)

- (instancetype)initWithHotFixDirectory:(ZMHotFixDirectory *)hotFixDirectory syncMOC:(NSManagedObjectContext *)syncMOC;
- (void)applyPatchesForCurrentVersion:(NSString *)currentVersion afterSync:(BOOL)afterSync;

@end



