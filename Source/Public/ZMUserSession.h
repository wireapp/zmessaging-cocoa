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
#import <WireSyncEngine/CallingProtocolStrategy.h>

@class ZMTransportSession;
@class ZMSearchDirectory;
@class ZMMessage;
@class ZMConversation;
@class UserClient;
@class ZMProxyRequest;
@class ZMCallKitDelegate;
@class CallingRequestStrategy;

@protocol UserProfile;
@protocol AnalyticsType;
@protocol AVSMediaManager;
@protocol ZMNetworkAvailabilityObserver;
@protocol ZMRequestsToOpenViewsDelegate;
@protocol ZMThirdPartyServicesDelegate;
@protocol UserProfileImageUpdateProtocol;
@class TopConversationsDirectory;

@protocol ZMAVSLogObserver <NSObject>
@required
- (void)logMessage:(NSString *)msg;
@end

@protocol ZMAVSLogObserverToken <NSObject>
@end


extern NSString * const ZMLaunchedWithPhoneVerificationCodeNotificationName;
extern NSString * const ZMPhoneVerificationCodeKey;
extern NSString * const ZMUserSessionResetPushTokensNotificationName;
extern NSString * const ZMTransportRequestLoopNotificationName;

/// The main entry point for the WireSyncEngine API.
///
/// The client app should create this object upon launch and keep a reference to it
@interface ZMUserSession : NSObject <ZMManagedObjectContextProvider>

/**
 Returns YES if data store needs to be migrated.
 */
+ (BOOL)needsToPrepareLocalStoreUsingAppGroupIdentifier:(NSString *)appGroupIdentifier;

/**
 Should be called <b>before</b> using ZMUserSession when applications is started if +needsToPrepareLocalStore returns YES. 
    It will intialize persistent store and perform migration (if needed) on background thread.
    When it's done it will call completionHandler on an arbitrary thread. It is the responsability of the caller to switch to the desired thread.
    The local store is not ready to be used (and the ZMUserSession is not ready to be initialized) until the completionHandler has been called.
 */
+ (void)prepareLocalStoreUsingAppGroupIdentifier:(NSString *)appGroupIdentifier completion:(void (^)())completionHandler;

/// Whether the local store is ready to be opened. If it returns false, the user session can't be started yet
+ (BOOL)storeIsReady;

/**
 Intended initializer to be used by the UI
 @param mediaManager: The media manager delegate
 @param analytics: An object conforming to the @c AnalyticsType protocol that can be used to track events on the sync engine
 @param appVersion: The application version (build number)
 @param appGroupIdentifier: The identifier of the shared application group container that should be used to store databases etc.
*/
- (instancetype)initWithMediaManager:(id<AVSMediaManager>)mediaManager
                           analytics:(id<AnalyticsType>)analytics
                          appVersion:(NSString *)appVersion
                  appGroupIdentifier:(NSString *)appGroupIdentifier;

@property (nonatomic, weak) id<ZMRequestsToOpenViewsDelegate> requestToOpenViewDelegate;
@property (nonatomic, weak) id<ZMThirdPartyServicesDelegate> thirdPartyServicesDelegate;
@property (atomic, readonly) ZMNetworkState networkState;
@property (atomic) BOOL isNotificationContentHidden;

/**
 Starts session and checks if client version is not in black list.
 Version should be a build number. blackListedBlock is retained and called only if passed version is black listed. The block is 
 called only once, even if the file is downloaded multiple times.
 */
- (void)startAndCheckClientVersionWithCheckInterval:(NSTimeInterval)interval blackListedBlock:(void (^)())blackListed;

- (void)start;

/// Performs a save in the context
- (void)saveOrRollbackChanges;

/// Performs some changes on the managed object context (in the block) before saving
- (void)performChanges:(dispatch_block_t)block ZM_NON_NULL(1);

/// Enqueue some changes on the managed object context (in the block) before saving
- (void)enqueueChanges:(dispatch_block_t)block ZM_NON_NULL(1);

/// Enqueue some changes on the managed object context (in the block) before saving, then invokes the completion handler
- (void)enqueueChanges:(dispatch_block_t)block completionHandler:(dispatch_block_t)completionHandler ZM_NON_NULL(1);

/// Creates new signaling keys  and reregisters the keys and the push tokens with the backend
- (void)resetPushTokens;

/// Initiates the deletion process for the current signed in user
- (void)initiateUserDeletion;

/// Top conversation directory
@property (nonatomic, readonly) TopConversationsDirectory *topConversationsDirectory;

/// CallKit delegate
@property (nonatomic, readonly) ZMCallKitDelegate *callKitDelegate;

/// The URL of the shared container that has been determinned using the passed in application group identifier
@property (nonatomic, readonly) NSURL *sharedContainerURL;

@property (nonatomic, readonly) NSURL *storeURL;

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



@interface ZMUserSession (AVSLogging)

/// Add observer for AVS logging
+ (id<ZMAVSLogObserverToken>)addAVSLogObserver:(id<ZMAVSLogObserver>)observer;
/// Remove observer for AVS logging
+ (void)removeAVSLogObserver:(id<ZMAVSLogObserverToken>)token;

+ (void)appendAVSLogMessageForConversation:(ZMConversation *)conversation withMessage:(NSString *)message;

@end

@interface ZMUserSession (Calling)

@property (class) BOOL useCallKit;
@property (class) CallingProtocolStrategy callingProtocolStrategy;
@property (nonatomic, readonly) CallingRequestStrategy *callingStrategy;

@end


@protocol ZMRequestsToOpenViewsDelegate <NSObject>

/// This will be called when the UI should display a conversation, message or the conversation list.
- (void)showMessage:(ZMMessage *)message inConversation:(ZMConversation *)conversation;
- (void)showConversation:(ZMConversation *)conversation;
- (void)showConversationList;

@end



@protocol ZMThirdPartyServicesDelegate <NSObject>

/// This will get called at a convenient point in time when Hockey and Localytics should upload their data.
/// We try not to have Hockey and Localytics use the network while we're sync'ing.
- (void)userSessionIsReadyToUploadServicesData:(ZMUserSession *)userSession;

@end


typedef NS_ENUM (NSInteger, ProxiedRequestType){
    ProxiedRequestTypeGiphy,
    ProxiedRequestTypeSoundcloud
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

