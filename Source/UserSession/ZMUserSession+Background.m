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
#import "ZMOperationLoop+Background.h"
#import "ZMOperationLoop+Private.h"
#import "ZMPushToken.h"
#import "ZMSyncStrategy.h"
#import "ZMUserSession+UserNotificationCategories.h"
#import "ZMStoredLocalNotification.h"
#import "ZMMissingUpdateEventsTranscoder.h"
#import <WireSyncEngine/WireSyncEngine-Swift.h>

static NSString *ZMLogTag = @"Push";

@implementation ZMUserSession (ZMBackground)

- (void)setupPushNotificationsForApplication:(id<ZMApplication>)application
{
    NOT_USED(application);
    
#if TARGET_OS_SIMULATOR
    ZMLogInfo(@"Skipping request for remote notification permission on simulator.");    
#else
    NSSet *categories = [NSSet setWithArray:@[
                                              self.replyCategory,
                                              self.replyCategoryIncludingLike,
                                              self.missedCallCategory,
                                              self.incomingCallCategory,
                                              self.connectCategory
                                              ]];
    [application registerUserNotificationSettings:[UIUserNotificationSettings  settingsForTypes:(UIUserNotificationTypeSound |
                                                                                                 UIUserNotificationTypeAlert |
                                                                                                 UIUserNotificationTypeBadge)
                                                                                     categories:categories]];
#endif
}

- (void)application:(id<ZMApplication>)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions;
{
    UILocalNotification *notification = launchOptions[UIApplicationLaunchOptionsLocalNotificationKey];
    if (notification != nil) {
        [self application:application didReceiveLocalNotification:notification];
    }
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

- (void)application:(id<ZMApplication>)application didReceiveLocalNotification:(UILocalNotification *)notification;
{
    [self didReceiveLocalWithNotification:notification application:application];
}

- (void)application:(id<ZMApplication>)application handleActionWithIdentifier:(NSString *)identifier forLocalNotification:(UILocalNotification *)notification responseInfo:(NSDictionary *)responseInfo completionHandler:(void(^)(void))completionHandler;
{
    [self handleActionWithApplication:application
                                 with:identifier
                                  for:notification
                                 with:responseInfo
                    completionHandler:completionHandler];
}

- (void)application:(id<ZMApplication>)application
performFetchWithCompletionHandler:(void (^)(UIBackgroundFetchResult result))completionHandler;
{
    NOT_USED(application);
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
}

- (void)applicationWillEnterForeground:(NSNotification *)note;
{
    NOT_USED(note);
    self.didNotifyThirdPartyServices = NO;

    [self mergeChangesFromStoredSaveNotificationsIfNeeded];
    
    [ZMConversationList refetchAllListsInUserSession:self];
    
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

    for (NSDictionary *changes in storedNotifications) {
        [NSManagedObjectContext mergeChangesFromRemoteContextSave:changes intoContexts:@[self.managedObjectContext]];
        [self.syncManagedObjectContext performGroupedBlock:^{
            [NSManagedObjectContext mergeChangesFromRemoteContextSave:changes intoContexts:@[self.syncManagedObjectContext]];
        }];
    }

    [self.managedObjectContext processPendingChanges];

    [self.syncManagedObjectContext performGroupedBlock:^{
        [self.syncManagedObjectContext processPendingChanges];
    }];
}

- (void)processPendingNotificationActions
{
    if (self.pendingLocalNotification == nil) {
        return;
    }
    
    [self.managedObjectContext performGroupedBlock: ^{
        ZMStoredLocalNotification *note = self.pendingLocalNotification;
        
        if ([note.category isEqualToString:ZMConnectCategory]) {
            [self handleConnectionRequestCategoryNotification:note];
        }
        else if ([note.category isEqualToString:ZMIncomingCallCategory] || [note.category isEqualToString:ZMMissedCallCategory]){
            [self handleCallCategoryNotification:note];
        }
        else {
            [self handleDefaultCategoryNotification:note];
        }
        self.pendingLocalNotification = nil;
    }];
    
}


@end


@implementation ZMUserSession (ZMBackgroundFetch)

- (void)enableBackgroundFetch;
{
    // We enable background fetch by setting the minimum interval to something different from UIApplicationBackgroundFetchIntervalNever
    [self.application setMinimumBackgroundFetchInterval:10. * 60. + arc4random_uniform(5 * 60)];
}

@end
