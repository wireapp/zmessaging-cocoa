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
@class UserProfileUpdateStatus;
@class ClientUpdateStatus;
@class CallKitDelegate;

@protocol MediaManagerType; 
@protocol FlowManagerType;


@interface ZMUserSession (AuthenticationStatus)

@property (nonatomic, readonly) UserProfileUpdateStatus *userProfileUpdateStatus;
@property (nonatomic, readonly) ZMClientRegistrationStatus *clientRegistrationStatus;
@property (nonatomic, readonly) ClientUpdateStatus *clientUpdateStatus;
@property (nonatomic, readonly) ProxiedRequestsStatus *proxiedRequestStatus;
@property (nonatomic, readonly) id<AuthenticationStatusProvider> authenticationStatus;

@end


@interface ZMUserSession ()

@property (nonatomic, readonly) id<ZMApplication> application;
@property (nonatomic) ZMCallStateObserver *callStateObserver;
@property (nonatomic) ContextDidSaveNotificationPersistence *storedDidSaveNotifications;
@property (nonatomic) ManagedObjectContextChangeObserver *messageReplyObserver;
@property (nonatomic) ManagedObjectContextChangeObserver *likeMesssageObserver;
@property (nonatomic)  UserExpirationObserver *userExpirationObserver;
@property (nonatomic, readonly) NSURL *sharedContainerURL;

- (void)notifyThirdPartyServices;

@end



@interface ZMUserSession (Internal) <TearDownCapable>

@property (nonatomic, readonly) BOOL isLoggedIn;
@property (nonatomic, readonly) NSManagedObjectContext *managedObjectContext;
@property (nonatomic, readonly) NSManagedObjectContext *syncManagedObjectContext;
@property (nonatomic, readonly) LocalNotificationDispatcher *localNotificationDispatcher;

+ (NSString *)databaseIdentifier;

- (instancetype)initWithTransportSession:(id<TransportSessionType>)tranportSession
                            mediaManager:(id<MediaManagerType>)mediaManager
                             flowManager:(id<FlowManagerType>)flowManager
                               analytics:(id<AnalyticsType>)analytics
                           operationLoop:(ZMOperationLoop *)operationLoop
                             application:(id<ZMApplication>)application
                              appVersion:(NSString *)appVersion
                           storeProvider:(id<LocalStoreProviderProtocol>)storeProvider;

@end


@interface ZMUserSession (ClientRegistrationStatus) <ZMClientRegistrationStatusDelegate>
@end


@interface ZMUserSession(NetworkState) <ZMNetworkStateDelegate, ZMSyncStateDelegate>
@end


@interface NSManagedObjectContext (NetworkState)

@property BOOL isOffline;

@end


@interface ZMUserSession (ZMBackgroundFetch)

- (void)enableBackgroundFetch;

@end
