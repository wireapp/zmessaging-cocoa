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
@import WireSystem;
@import WireDataModel;

#import <WireSyncEngine/ZMNetworkState.h>
#import <WireTransport/ZMTransportRequest.h>

@class ZMTransportSession;
@class ZMMessage;
@class ZMConversation;
@class UserClient;
@class ZMProxyRequest;
@class CallKitDelegate;
@class CallingRequestStrategy;
@class AVSMediaManager;
@class WireCallCenterV3;
@class SessionManager;

@protocol UserProfile;
@protocol AnalyticsType;
@protocol ZMNetworkAvailabilityObserver;
@protocol ZMRequestsToOpenViewsDelegate;
@protocol ZMThirdPartyServicesDelegate;
@protocol UserProfileImageUpdateProtocol;
@protocol ZMApplication;
@protocol LocalStoreProviderProtocol;
@protocol FlowManagerType;
@protocol SessionManagerType;
@protocol LocalStoreProviderProtocol;

@class ManagedObjectContextDirectory;
@class TopConversationsDirectory;

extern NSString * const ZMLaunchedWithPhoneVerificationCodeNotificationName;
extern NSString * const ZMPhoneVerificationCodeKey;
extern NSString * const ZMUserSessionResetPushTokensNotificationName;

/// The main entry point for the WireSyncEngine API.
///
/// The client app should create this object upon launch and keep a reference to it
@interface ZMUserSession : NSObject <ZMManagedObjectContextProvider>

/**
 Intended initializer to be used by the UI
 @param mediaManager: The media manager delegate
 @param analytics: An object conforming to the @c AnalyticsType protocol that can be used to track events on the sync engine
 @param appVersion: The application version (build number)
 @param storeProvider: An object conforming to the @c LocalStoreProviderProtocol that provides information about local store locations etc.
*/
- (instancetype)initWithMediaManager:(AVSMediaManager *)mediaManager
                         flowManager:(id<FlowManagerType>)flowManager
                           analytics:(id<AnalyticsType>)analytics
                    transportSession:(ZMTransportSession *)transportSession
                         application:(id<ZMApplication>)application
                          appVersion:(NSString *)appVersion
                       storeProvider:(id<LocalStoreProviderProtocol>)storeProvider;

@property (nonatomic, readonly) id <LocalStoreProviderProtocol> storeProvider;
@property (nonatomic, weak) id<SessionManagerType> sessionManager;
@property (nonatomic, weak) id<ZMThirdPartyServicesDelegate> thirdPartyServicesDelegate;
@property (atomic, readonly) ZMNetworkState networkState;
@property (atomic) BOOL isNotificationContentHidden;

/// Performs a save in the context
- (void)saveOrRollbackChanges;

/// Performs some changes on the managed object context (in the block) before saving
- (void)performChanges:(dispatch_block_t)block ZM_NON_NULL(1);

/// Enqueue some changes on the managed object context (in the block) before saving
- (void)enqueueChanges:(dispatch_block_t)block ZM_NON_NULL(1);

/// Enqueue some changes on the managed object context (in the block) before saving, then invokes the completion handler
- (void)enqueueChanges:(dispatch_block_t)block completionHandler:(dispatch_block_t)completionHandler ZM_NON_NULL(1);

/// Initiates the deletion process for the current signed in user
- (void)initiateUserDeletion;

/// Top conversation directory
@property (nonatomic, readonly) TopConversationsDirectory *topConversationsDirectory;

/// The sync has been completed as least once
@property (nonatomic, readonly) BOOL hasCompletedInitialSync;

@end

@interface ZMUserSession (LaunchOptions)

- (void)didLaunchWithURL:(NSURL *)URL;

@end


@interface ZMUserSession (Calling)

@property (nonatomic, readonly) CallingRequestStrategy *callingStrategy;

@end


@protocol ZMThirdPartyServicesDelegate <NSObject>

/// This will get called at a convenient point in time when Hockey and Localytics should upload their data.
/// We try not to have Hockey and Localytics use the network while we're sync'ing.
- (void)userSessionIsReadyToUploadServicesData:(ZMUserSession *)userSession;

@end


typedef NS_ENUM (NSInteger, ProxiedRequestType) {
    ProxiedRequestTypeGiphy,
    ProxiedRequestTypeSoundcloud,
    ProxiedRequestTypeYouTube
};

@interface ZMUserSession (Proxy)

- (ZMProxyRequest *)proxiedRequestWithPath:(NSString *)path method:(ZMTransportRequestMethod)method type:(ProxiedRequestType)type callback:(void (^)(NSData *, NSHTTPURLResponse *, NSError *))callback;
- (void)cancelProxiedRequest:(ZMProxyRequest *)proxyRequest;

@end


@interface ZMUserSession (SelfUserClient)

/// Object for updating profile
@property (nonatomic, readonly) id<UserProfile> userProfile;

- (UserClient *)selfUserClient;
@end

@interface ZMUserSession (ProfilePictureUpdate)

@property (nonatomic, readonly) id<UserProfileImageUpdateProtocol> profileUpdate;

@end

