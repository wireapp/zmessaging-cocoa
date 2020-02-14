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

@class ZMMessage;
@class ZMConversation;
@class UserClient;
@class ZMProxyRequest;
@class CallKitManager;
@class CallingRequestStrategy;
@class WireCallCenterV3;
@class SessionManager;

@protocol TransportSessionType;
@protocol MediaManagerType;
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
@protocol ShowContentDelegate;

@class ManagedObjectContextDirectory;
@class TopConversationsDirectory;

extern NSString * const ZMLaunchedWithPhoneVerificationCodeNotificationName;
extern NSString * const ZMPhoneVerificationCodeKey;
extern NSString * const ZMUserSessionResetPushTokensNotificationName;

/// The main entry point for the WireSyncEngine API.
///
/// The client app should create this object upon launch and keep a reference to it
@interface ZMUserSession : NSObject <ZMManagedObjectContextProvider>

@property (nonatomic, readonly) NSManagedObjectContext * managedObjectContext;
@property (nonatomic, readonly) NSManagedObjectContext * syncManagedObjectContext;

/**
 Intended initializer to be used by the UI
 @param mediaManager: The media manager delegate
 @param analytics: An object conforming to the @c AnalyticsType protocol that can be used to track events on the sync engine
 @param appVersion: The application version (build number)
 @param storeProvider: An object conforming to the @c LocalStoreProviderProtocol that provides information about local store locations etc.
*/
- (instancetype)initWithMediaManager:(id<MediaManagerType>)mediaManager
                         flowManager:(id<FlowManagerType>)flowManager
                           analytics:(id<AnalyticsType>)analytics
                    transportSession:(id<TransportSessionType>)transportSession
                         application:(id<ZMApplication>)application
                          appVersion:(NSString *)appVersion
                       storeProvider:(id<LocalStoreProviderProtocol>)storeProvider
                 showContentDelegate:(id<ShowContentDelegate>)showContentDelegate;

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

/// Enqueue some changes on the managed object context (in the block) and then performs a delayed save.
///
/// This method is prefered if you will make many changes in a loop.
- (void)enqueueDelayedChanges:(dispatch_block_t)block ZM_NON_NULL(1);

/// Enqueue some changes on the managed object context (in the block) before performing a delayed save, then invokes the completion handler after the save is performed.
///
/// This method is prefered if you will make many changes in a loop.
- (void)enqueueDelayedChanges:(dispatch_block_t)block completionHandler:(dispatch_block_t)completionHandler ZM_NON_NULL(1);

/// Initiates the deletion process for the current signed in user
- (void)initiateUserDeletion;

/// Top conversation directory
@property (nonatomic, readonly) TopConversationsDirectory *topConversationsDirectory;

/// The sync has been completed as least once
@property (nonatomic, readonly) BOOL hasCompletedInitialSync;

@end



@interface ZMUserSession (Transport)

/// This method should be called from inside @c application(application:handleEventsForBackgroundURLSession identifier:completionHandler:)
/// and passed the NSURLSession and completionHandler to store after recreating the background session with the given identifier.
/// @param identifier The identifier that should be used to recreate the background @c NSURLSession
/// @param handler The completion block from the OS that should be stored
- (void)addCompletionHandlerForBackgroundURLSessionWithIdentifier:(NSString *)identifier handler:(dispatch_block_t)handler;

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


@interface ZMUserSession (SelfUserClient)

/// Object for updating profile
@property (nonatomic, readonly) id<UserProfile> userProfile;

- (UserClient *)selfUserClient;
@end

@interface ZMUserSession (ProfilePictureUpdate)

@property (nonatomic, readonly) id<UserProfileImageUpdateProtocol> profileUpdate;

@end

