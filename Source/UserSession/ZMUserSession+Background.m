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
#import "ZMCallKitDelegate.h"
#import "ZMSyncStrategy.h"
#import "ZMLocalNotification.h"
#import "ZMUserSession+UserNotificationCategories.h"
#import "ZMStoredLocalNotification.h"
#import "ZMMissingUpdateEventsTranscoder.h"
#import <WireSyncEngine/WireSyncEngine-Swift.h>

static NSString *ZMLogTag = @"Push";

@implementation ZMUserSession (PushReceivers)

@end




@implementation ZMUserSession (ZMBackground)

- (void)setupPushNotificationsForApplication:(id<ZMApplication>)application
{
    [application registerForRemoteNotifications];
    
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

- (void)application:(id<ZMApplication>)application
handleActionWithIdentifier:(NSString *)identifier
forLocalNotification:(UILocalNotification *)notification
       responseInfo:(NSDictionary *)responseInfo
  completionHandler:(void(^)())completionHandler;
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
        [self.operationLoop.syncStrategy.applicationStatusDirectory.operationStatus startBackgroundFetchWithCompletionHandler:completionHandler];
    }];
}

- (void)application:(id<ZMApplication>)application handleEventsForBackgroundURLSession:(NSString *)identifier completionHandler:(void (^)())completionHandler;
{
    NOT_USED(application);
    NOT_USED(identifier);
    completionHandler(UIBackgroundFetchResultFailed);
}

- (BOOL)application:(id<ZMApplication>)application continueUserActivity:(NSUserActivity *)userActivity restorationHandler:(void (^)(NSArray * _Nullable))restorationHandler
{
    NOT_USED(application);
    NOT_USED(restorationHandler);
    return [self.callKitDelegate continueUserActivity:userActivity];
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

@end






@implementation ZMUserSession (NotificationProcessing)

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
            [self openConversation:note.conversation atMessage:note.message];
        }
        self.pendingLocalNotification = nil;
    }];
    
}

// Foreground Actions

- (void)handleConnectionRequestCategoryNotification:(ZMStoredLocalNotification *)note
{
    ZMConversation *conversation = note.conversation;
    
    ZMUser *sender = [ZMUser fetchObjectWithRemoteIdentifier:note.senderUUID inManagedObjectContext:self.managedObjectContext];
    if (sender != nil) {
        conversation = sender.connection.conversation;
        if ([note.actionIdentifier isEqualToString:ZMConnectAcceptAction]) {
            [sender accept];
            [self.managedObjectContext saveOrRollback];
        }
    }
    
    [self openConversation:conversation atMessage:nil];
}

- (void)handleCallCategoryNotification:(ZMStoredLocalNotification *)note
{
    if (note.actionIdentifier == nil || [note.actionIdentifier isEqualToString:ZMCallAcceptAction]) {
        BOOL callIsStillOngoing = note.conversation.voiceChannel.state == VoiceChannelV2StateIncomingCall;
        
        if ([WireCallCenter activeCallConversationsInUserSession:self].count == 0 && callIsStillOngoing) {
            NOT_USED([note.conversation.voiceChannel joinWithVideo:NO userSession:self]);
            [note.conversation.managedObjectContext saveOrRollback];
        }
    }
    
    [self openConversation:note.conversation atMessage:nil];
}

- (void)openConversation:(ZMConversation *)conversation atMessage:(ZMMessage *)message
{
    id<ZMRequestsToOpenViewsDelegate> strongDelegate = self.requestToOpenViewDelegate;
    if (conversation == nil) {
        [strongDelegate showConversationListForUserSession:self];
    }
    else if (message == nil) {
        [strongDelegate userSession:self showConversation:conversation];
    }
    else {
        [strongDelegate userSession:self showMessage:message inConversation:conversation];
    }
}

// Background Actions

- (void)ignoreCallForNotification:(UILocalNotification *)notification withCompletionHandler:(void (^)())completionHandler;
{
    ZMBackgroundActivity *activity = [[BackgroundActivityFactory sharedInstance] backgroundActivityWithName:@"IgnoreCall Action Handler"];
    ZMConversation *conversation = [notification conversationInManagedObjectContext:self.managedObjectContext];
    [self.managedObjectContext performBlock:^{
        [conversation.voiceChannel ignoreWithUserSession:self];
        [self.managedObjectContext saveOrRollback];
        
        [activity endActivity];
        if (completionHandler != nil) {
            completionHandler();
        }
    }];
}

- (void)muteConversationForNotification:(UILocalNotification *)notification withCompletionHandler:(void (^)())completionHandler;
{
    ZMBackgroundActivity *activity = [[BackgroundActivityFactory sharedInstance] backgroundActivityWithName:@"Mute Conversation Action Handler"];
    ZMConversation *conversation = [notification conversationInManagedObjectContext:self.managedObjectContext];
    [self.managedObjectContext performBlock:^{
        conversation.isSilenced = YES;
        [self.managedObjectContext saveOrRollback];
        
        [activity endActivity];
        if (completionHandler != nil) {
            completionHandler();
        }
    }];
}

- (void)replyToNotification:(UILocalNotification *)notification withReply:(NSString *)reply completionHandler:(void (^)())completionHandler;
{
    if (reply.length == 0) {
        if (completionHandler != nil) {
            completionHandler();
        }
        return;
    }
    ZMBackgroundActivity *activity = [[BackgroundActivityFactory sharedInstance] backgroundActivityWithName:@"DirectReply Action Handler"];
    ZMConversation *conversation = [notification conversationInManagedObjectContext:self.managedObjectContext];

    if (conversation != nil) {
        ZM_WEAK(self);
        [self.operationLoop.syncStrategy.applicationStatusDirectory.operationStatus startBackgroundTaskWithCompletionHandler:^(ZMBackgroundTaskResult result) {
            ZM_STRONG(self);
            self.messageReplyObserver = nil;
            [self.syncManagedObjectContext performGroupedBlock: ^{
                if (result == ZMBackgroundTaskResultFailed) {
                    ZMConversation *syncConversation = [notification conversationInManagedObjectContext:self.syncManagedObjectContext];
                    [self.localNotificationDispatcher didFailToSendMessageIn:syncConversation];
                }
                
                [activity endActivity];
                if (completionHandler != nil) {
                    completionHandler();
                }
            }];
        }];

        [self enqueueChanges:^{
            ZM_STRONG(self);
            id <ZMConversationMessage> message = [conversation appendMessageWithText:reply];
            self.messageReplyObserver = [[ManagedObjectContextChangeObserver alloc] initWithContext:self.managedObjectContext
                                                                                     callback:^{
                                                                                         [self updateBackgroundTaskWithMessage:message];
                                                                                     }];
        }];
    }
    else {
        [activity endActivity];
        if (completionHandler != nil) {
            completionHandler();
        }
    }
}

- (void)likeMessageForNotification:(UILocalNotification *)note withCompletionHandler:(void (^)(void))completionHandler
{
    ZMBackgroundActivity *activity = [[BackgroundActivityFactory sharedInstance] backgroundActivityWithName:@"Like Message Activity"];
    ZMConversation *conversation = [note conversationInManagedObjectContext:self.managedObjectContext];
    ZMMessage *message = [note messageInConversation:conversation inManagedObjectContext:self.managedObjectContext];

    if (message == nil) {
        [activity endActivity];
        if (completionHandler != nil) {
            completionHandler();
        }
        return;
    }
    
    ZM_WEAK(self);
    [self.operationLoop.syncStrategy.applicationStatusDirectory.operationStatus startBackgroundTaskWithCompletionHandler:^(ZMBackgroundTaskResult result) {
        ZM_STRONG(self);
        self.likeMesssageObserver = nil;
        if (result == ZMBackgroundTaskResultFailed) {
            ZMLogDebug(@"Failed to send reaction via notification");
        }
        
        [activity endActivity];
        if (completionHandler != nil) {
            completionHandler();
        }
    }];

    [self enqueueChanges:^{
        id <ZMConversationMessage> reactionMessage = [ZMMessage addReaction:MessageReactionLike toMessage:message];
        self.likeMesssageObserver = [[ManagedObjectContextChangeObserver alloc] initWithContext:self.managedObjectContext
                                                                                       callback:^{
                                                                                           ZM_STRONG(self);
                                                                                           [self updateBackgroundTaskWithMessage:reactionMessage];
                                                                                       }];
    }];
}


- (void)updateBackgroundTaskWithMessage:(id<ZMConversationMessage>)message
{
    switch (message.deliveryState) {
        case ZMDeliveryStateSent:
        case ZMDeliveryStateDelivered:
            [self.operationLoop.syncStrategy.applicationStatusDirectory.operationStatus finishBackgroundTaskWithTaskResult:ZMBackgroundTaskResultFinished];
            break;
        case ZMDeliveryStateFailedToSend:
            [self.operationLoop.syncStrategy.applicationStatusDirectory.operationStatus finishBackgroundTaskWithTaskResult:ZMBackgroundTaskResultFailed];
            break;
        default:
            break;
    }
}

@end



@implementation ZMUserSession (ZMBackgroundFetch)

- (void)enableBackgroundFetch;
{
    // We enable background fetch by setting the minimum interval to something different from UIApplicationBackgroundFetchIntervalNever
    [self.application setMinimumBackgroundFetchInterval:10. * 60. + arc4random_uniform(5 * 60)];
}

@end
