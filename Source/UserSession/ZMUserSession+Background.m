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


@import WireTransport;
@import WireDataModel;

#import "ZMUserSession+Internal.h"
#import "ZMOperationLoop+Private.h"
#import "ZMSyncStrategy.h"
#import "ZMMissingUpdateEventsTranscoder.h"
#import <WireSyncEngine/WireSyncEngine-Swift.h>

static NSString *ZMLogTag = @"Push";

@implementation ZMUserSession (ZMBackground)

- (void)application:(id<ZMApplication>)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions;
{
    [self startEphemeralTimers];
    NSDictionary *payload = launchOptions[UIApplicationLaunchOptionsRemoteNotificationKey];
    if (payload != nil) {
        [self application:application didReceiveRemoteNotification:payload fetchCompletionHandler:^(UIBackgroundFetchResult result) {
            NOT_USED(result);
        }];
    }
}

- (void)application:(id<ZMApplication>)application didReceiveRemoteNotification:(NSDictionary *)userInfo fetchCompletionHandler:(void (^)(UIBackgroundFetchResult result))completionHandler;
{
    NOT_USED(application);
    NOT_USED(userInfo);
    NOT_USED(completionHandler);
}

- (void)application:(id<ZMApplication>)application
performFetchWithCompletionHandler:(void (^)(UIBackgroundFetchResult result))completionHandler;
{
    NOT_USED(application);
    [BackgroundActivityFactory.sharedFactory resume];
    [self.syncManagedObjectContext performGroupedBlock:^{
        [self.operationLoop.syncStrategy.missingUpdateEventsTranscoder startDownloadingMissingNotifications];
        [self.operationStatus startBackgroundFetchWithCompletionHandler:completionHandler];
    }];
}

- (void)application:(id<ZMApplication>)application handleEventsForBackgroundURLSession:(NSString *)identifier completionHandler:(void (^)(void))completionHandler;
{
    NOT_USED(application);
    NOT_USED(identifier);
    completionHandler();
}

- (void)applicationDidEnterBackground:(NSNotification *)note;
{
    NOT_USED(note);
    [self notifyThirdPartyServices];
    [self stopEphemeralTimers];
}

- (void)applicationWillEnterForeground:(NSNotification *)note;
{
    NOT_USED(note);
    self.didNotifyThirdPartyServices = NO;

    [self mergeChangesFromStoredSaveNotificationsIfNeeded];
    
    [self startEphemeralTimers];
    // In the case that an ephemeral was sent via the share extension, we need
    // to ensure that they have timers running or are deleted/obfuscated if
    // needed. Note: ZMMessageTimer will only create a new timer for a message
    // if one does not already exist.
    [self.syncManagedObjectContext performGroupedBlock:^{
        [ZMMessage deleteOldEphemeralMessages:self.syncManagedObjectContext];
    }];
}

- (void)mergeChangesFromStoredSaveNotificationsIfNeeded
{
    NSArray *storedNotifications = self.storedDidSaveNotifications.storedNotifications.copy;
    [self.storedDidSaveNotifications clear];

    if (storedNotifications.count == 0) {
        return;
    }
    
    for (NSDictionary *changes in storedNotifications) {
        [NSManagedObjectContext mergeChangesFromRemoteContextSave:changes intoContexts:@[self.managedObjectContext]];
        [self.syncManagedObjectContext performGroupedBlock:^{
            [NSManagedObjectContext mergeChangesFromRemoteContextSave:changes intoContexts:@[self.syncManagedObjectContext]];
        }];
    }

    // we only process pending changes on sync context bc changes on the
    // ui context will be processed when we do the save.
    [self.syncManagedObjectContext performGroupedBlock:^{
        [self.syncManagedObjectContext processPendingChanges];
    }];
    
    [self.managedObjectContext saveOrRollback];
}

@end


@implementation ZMUserSession (ZMBackgroundFetch)

- (void)enableBackgroundFetch;
{
    // We enable background fetch by setting the minimum interval to something different from UIApplicationBackgroundFetchIntervalNever
    [self.application setMinimumBackgroundFetchInterval:10. * 60. + arc4random_uniform(5 * 60)];
}

@end
