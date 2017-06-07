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


@import WireUtilities;
@import WireTransport;
@import WireDataModel;

#import "ZMUserSession.h"
#import <WireSyncEngine/ZMAuthenticationStatus.h>
#import "ZMSyncStateDelegate.h"
#import <WireSyncEngine/WireSyncEngine-Swift.h>

@class NSManagedObjectContext;
@class ZMTransportRequest;
@class ZMCredentials;
@class ZMSyncStrategy;
@class ZMOperationLoop;
@class ZMPushRegistrant;
@class ZMApplicationRemoteNotification;
@class ZMStoredLocalNotification;
@class ZMAPNSEnvironment;
@class UserProfileUpdateStatus;
@class ClientUpdateStatus;
@class AVSFlowManager;
@class ZMCallKitDelegate;

extern NSString * const ZMAppendAVSLogNotificationName;

@interface ZMUserSession (AuthenticationStatus)
@property (nonatomic, readonly) ZMAuthenticationStatus *authenticationStatus;
@property (nonatomic, readonly) UserProfileUpdateStatus *userProfileUpdateStatus;
@property (nonatomic, readonly) ZMClientRegistrationStatus *clientRegistrationStatus;
@property (nonatomic, readonly) ClientUpdateStatus *clientUpdateStatus;
@property (nonatomic, readonly) ZMAccountStatus *accountStatus;
@property (nonatomic, readonly) ProxiedRequestsStatus *proxiedRequestStatus;
@end


@interface ZMUserSession ()

@property (nonatomic) BOOL networkIsOnline;
@property (nonatomic) BOOL isPerformingSync;
@property (nonatomic) BOOL didStartInitialSync;
@property (nonatomic) BOOL pushChannelIsOpen;
@property (nonatomic) BOOL didNotifyThirdPartyServices;
@property (nonatomic, readonly) id<ZMApplication> application;
@property (nonatomic) ZMCallKitDelegate *callKitDelegate;
@property (nonatomic) ZMCallStateObserver *callStateObserver;
@property (nonatomic) ContextDidSaveNotificationPersistence *storedDidSaveNotifications;
@property (nonatomic) id<NSObject> messageReplyObserverToken;
@property (nonatomic) id<NSObject> likeMesssageObserverToken;

- (void)notifyThirdPartyServices;
- (void)start;
- (void)refreshTokensIfNeeded;

@end



@interface ZMUserSession (Internal) 

@property (nonatomic, readonly) BOOL isLoggedIn;
@property (nonatomic, readonly) NSManagedObjectContext *managedObjectContext;
@property (nonatomic, readonly) NSManagedObjectContext *syncManagedObjectContext;
@property (nonatomic, readonly) AVSFlowManager *flowManager;
@property (nonatomic, readonly) LocalNotificationDispatcher *localNotificationDispatcher;

+ (NSString *)databaseIdentifier;

- (instancetype)initWithTransportSession:(ZMTransportSession *)session
                    userInterfaceContext:(NSManagedObjectContext *)userInterfaceContext
                syncManagedObjectContext:(NSManagedObjectContext *)syncManagedObjectContext
                            mediaManager:(id<AVSMediaManager>)mediaManager
                         apnsEnvironment:(ZMAPNSEnvironment *)apnsEnvironment
                           operationLoop:(ZMOperationLoop *)operationLoop
                             application:(id<ZMApplication>)application
                              appVersion:(NSString *)appVersion
                      appGroupIdentifier:(NSString *)appGroupIdentifier;

- (void)tearDown;

@property (nonatomic) ZMPushRegistrant *pushRegistrant;
@property (nonatomic) ZMApplicationRemoteNotification *applicationRemoteNotification;
@property (nonatomic) ZMStoredLocalNotification *pendingLocalNotification;

/// Called from ZMUserSession init to initialize the push notification receiving objects
- (void)enablePushNotifications;

/// When starting the app due to a push notification action, we store the notification information and wait until sync completed before processing pending local notifications.
/// This is important for possibly outdated calling notifications for which we need to fetch the call state before joining the call.
- (void)processPendingNotificationActions;

@end


@interface ZMUserSession (ClientRegistrationStatus) <ZMClientRegistrationStatusDelegate>
@end


@interface ZMUserSession(NetworkState) <ZMNetworkStateDelegate, ZMSyncStateDelegate>
@end


@interface ZMUserSession (Test)

@property (nonatomic, readonly) NSArray *allManagedObjectContexts;

@end


@interface NSManagedObjectContext (NetworkState)

@property BOOL isOffline;

@end


@interface ZMUserSession (RequestToOpenConversation)

+ (void)requestToOpenSyncConversationOnUI:(ZMConversation *)conversation;

@end


@interface ZMUserSession (PushToken)


- (void)setPushToken:(NSData *)deviceToken;
- (void)setPushKitToken:(NSData *)deviceToken;

/// deletes the pushKit token from the backend
- (void)deletePushKitToken;


@end


@interface ZMUserSession (ZMBackgroundFetch)

- (void)enableBackgroundFetch;

@end

@interface ZMUserSession (ReplyToMessage) <ZMMessageObserver>

@end
