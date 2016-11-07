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


@import ZMUtilities;
@import ZMTransport;
@import ZMCDataModel;
@import WireRequestStrategy;

#import "ZMHotFix.h"
#import "ZMHotFixDirectory.h"
#import "ZMUserSession.h"

static NSString* ZMLogTag ZM_UNUSED = @"HotFix";
static NSString * const LastSavedVersionKey = @"lastSavedVersion";
NSString * const ZMSkipHotfix = @"ZMSkipHotfix";

@interface ZMHotFix ()
@property (nonatomic) ZMHotFixDirectory *hotFixDirectory;
@property (nonatomic) NSManagedObjectContext *syncMOC;
@end


@implementation ZMHotFix


- (instancetype)initWithSyncMOC:(NSManagedObjectContext *)syncMOC
{
    return [self initWithHotFixDirectory:nil syncMOC:syncMOC];
}

- (instancetype)initWithHotFixDirectory:(ZMHotFixDirectory *)hotFixDirectory syncMOC:(NSManagedObjectContext *)syncMOC
{
    self = [super init];
    if (self != nil) {
        self.syncMOC = syncMOC;
        self.hotFixDirectory = hotFixDirectory ?: [[ZMHotFixDirectory alloc] init];
    }
    return self;
}

- (void)applyPatches
{
    if ([[self.syncMOC persistentStoreMetadataForKey:ZMSkipHotfix] boolValue]) {
        ZMLogDebug(@"Skipping applying HotFix");
        return;
    }
    
    NSString * currentVersionString = [[[NSBundle bundleForClass:ZMUserSession.class] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
    [self applyPatchesForCurrentVersion:currentVersionString];
}

- (void)applyPatchesForCurrentVersion:(NSString *)currentVersionString;
{
    if (currentVersionString.length == 0) {
        ZMLogDebug(@"Invalid version string, skipping HotFix");
        return;
    }
    ZMVersion *lastSavedVersion = [self lastSavedVersion];
    ZMVersion *currentVersion = [[ZMVersion alloc] initWithVersionString:currentVersionString];
    if ([currentVersion compareWithVersion:lastSavedVersion] == NSOrderedSame) {
        ZMLogDebug(@"Current version equal to last saved version (%@). Not applying any HotFix.", lastSavedVersion.versionString);
        return;
    }
    
    ZMLogDebug(@"Applying HotFix with last saved version %@, current version %@.", lastSavedVersion.versionString, currentVersion.versionString);
    [self.syncMOC performGroupedBlock:^{
        [self applyFixesSinceVersion:lastSavedVersion];
        [self saveNewVersion:currentVersionString];
        [self.syncMOC saveOrRollback];
        [ZMRequestAvailableNotification notifyNewRequestsAvailable:self];
    }];
}

- (ZMVersion *)lastSavedVersion
{
    NSString *versionString = [self.syncMOC persistentStoreMetadataForKey:LastSavedVersionKey];
    return [[ZMVersion alloc] initWithVersionString:versionString];
}


- (void)saveNewVersion:(NSString *)version
{
    [self.syncMOC setPersistentStoreMetadata:version forKey:LastSavedVersionKey];
    ZMLogDebug(@"Saved new HotFix version %@", version);
}

- (void)applyFixesSinceVersion:(ZMVersion *)lastSavedVersion
{
    for(ZMHotFixPatch *patch in self.hotFixDirectory.patches) {
        ZMVersion *version = [[ZMVersion alloc] initWithVersionString:patch.version];
        if (
            (lastSavedVersion == nil || [version compareWithVersion:lastSavedVersion] == NSOrderedDescending)
            && patch.code
            ) {
            patch.code(self.syncMOC);
        }
    }
}

@end



@interface ZMVersion ()

@property (nonatomic) NSArray *arrayRepresentation;
@property (nonatomic) NSString *versionString;

@end


@implementation ZMVersion

- (instancetype)initWithVersionString:(NSString *)versionString
{
    if (versionString == nil) {
        return nil;
    }

    self = [super init];
    if (self != nil) {
        self.versionString = versionString;
        self.arrayRepresentation = [self intComponentsOfString:versionString];
    }
    return self;
}

- (NSArray *)intComponentsOfString:(NSString *)versionString;
{
    NSArray *components = [versionString componentsSeparatedByString:@"."];
    return [components mapWithBlock:^id(NSString *numberPresentation) {
        return @([numberPresentation intValue]);
    }];
}

- (NSComparisonResult)compareWithVersion:(ZMVersion *)otherVersion;
{
    if (otherVersion.arrayRepresentation.count == 0) {
        return NSOrderedDescending;
    }
    
    if ([self.versionString isEqualToString:otherVersion.versionString]) {
        return NSOrderedSame;
    }
    
    for (NSUInteger i = 0; i < self.arrayRepresentation.count; i++) {
        if (otherVersion.arrayRepresentation.count == i) {
            // 1.0.1 compare 1.0
            return NSOrderedDescending;
        }
        
        NSNumber *selfNumber = self.arrayRepresentation[i];
        NSNumber *otherNumber = otherVersion.arrayRepresentation[i];
        
        if (selfNumber > otherNumber) {
            return NSOrderedDescending;
        } else if (selfNumber < otherNumber) {
            return NSOrderedAscending;
        }
    }
    
    if (self.arrayRepresentation.count < otherVersion.arrayRepresentation.count) {
        // 1.0 compare 1.0.1
        return NSOrderedAscending;
    }
    
    return NSOrderedSame;
}

- (NSString *)description
{
    return [self.arrayRepresentation componentsJoinedByString:@","];
}

- (NSString *)debugDescription
{
    return [NSString stringWithFormat:@"<%@ %p> %@",NSStringFromClass(self.class), self, self.description];
}

@end





