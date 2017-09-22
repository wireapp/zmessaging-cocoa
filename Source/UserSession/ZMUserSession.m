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


@import UIKit;
@import CoreData;
@import WireSystem;
@import WireUtilities;
@import WireDataModel;
@import CallKit;
@import CoreTelephony;

#import "ZMUserSession+Background.h"
#import "ZMUserSession+Internal.h"
#import "ZMUserSession+OperationLoop.h"
#import "ZMSyncStrategy.h"
#import "NSError+ZMUserSessionInternal.h"
#import "ZMCredentials.h"
#import <libkern/OSAtomic.h>
#import "ZMAuthenticationStatus.h"
#import "ZMPushToken.h"
#import "ZMBlacklistVerificator.h"
#import "ZMUserSessionAuthenticationNotification.h"
#import "NSURL+LaunchOptions.h"
#import "WireSyncEngineLogs.h"
#import "ZMCallFlowRequestStrategy.h"
#import "ZMCallKitDelegate.h"
#import "ZMOperationLoop+Private.h"
#import <WireSyncEngine/WireSyncEngine-Swift.h>

#import "ZMClientRegistrationStatus.h"
#import "ZMCallKitDelegate+TypeConformance.h"

NSString * const ZMPhoneVerificationCodeKey = @"code";
NSString * const ZMLaunchedWithPhoneVerificationCodeNotificationName = @"ZMLaunchedWithPhoneVerificationCode";
static NSString * const ZMRequestToOpenSyncConversationNotificationName = @"ZMRequestToOpenSyncConversation";
NSString * const ZMAppendAVSLogNotificationName = @"ZMAppendAVSLogNotification";
NSString * const ZMUserSessionResetPushTokensNotificationName = @"ZMUserSessionResetPushTokensNotification";
NSString * const ZMTransportRequestLoopNotificationName = @"ZMTransportRequestLoopNotificationName";
NSString * const ZMFlowManagerDidBecomeAvailableNotification = @"ZMFlowManagerDidBecomeAvailableNotification";

static NSString * const AppstoreURL = @"https://itunes.apple.com/us/app/zeta-client/id930944768?ls=1&mt=8";


@interface ZMUserSession ()
@property (nonatomic) ZMOperationLoop *operationLoop;
@property (nonatomic) ZMTransportRequest *runningLoginRequest;
@property (nonatomic) ZMTransportSession *transportSession;
@property (atomic) ZMNetworkState networkState;
@property (nonatomic) ZMBlacklistVerificator *blackList;
@property (nonatomic) ZMAPNSEnvironment *apnsEnvironment;
@property (nonatomic) ZMPushRegistrant *pushRegistrant;
@property (nonatomic) ZMApplicationRemoteNotification *applicationRemoteNotification;
@property (nonatomic) ZMStoredLocalNotification *pendingLocalNotification;
@property (nonatomic) LocalNotificationDispatcher *localNotificationDispatcher;

@property (nonatomic) id <LocalStoreProviderProtocol> storeProvider;

@property (nonatomic) TopConversationsDirectory *topConversationsDirectory;
@property (nonatomic) BOOL hasCompletedInitialSync;


/// Build number of the Wire app
@property (nonatomic) NSString *appVersion;

/// map from NSUUID to ZMCommonContactsSearchCachedEntry
@property (nonatomic) NSCache *commonContactsCache;

@property (nonatomic) AVSMediaManager* mediaManager;
@property (nonatomic) id<FlowManagerType> flowManager;
@end

@interface ZMUserSession(PushChannel)
- (void)pushChannelDidChange:(NSNotification *)note;
@end


NSURL *__nullable CBCreateTemporaryDirectoryAndReturnURL(void);


NSURL *__nullable CBCreateTemporaryDirectoryAndReturnURL()
{
    NSError *error = nil;
    NSURL *directoryURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]] isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:directoryURL withIntermediateDirectories:YES attributes:nil error:&error];
    if (error) {
        return nil;
    }
    
    return directoryURL;
}

@implementation ZMUserSession

ZM_EMPTY_ASSERTING_INIT()

+ (BOOL)shouldSendOnlyEncrypted
{
    return [[NSProcessInfo processInfo] environment][@"ZMEncryptionOnly"] != nil;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (instancetype)initWithMediaManager:(AVSMediaManager *)mediaManager
                        flowManager:(id<FlowManagerType>)flowManager
                           analytics:(id<AnalyticsType>)analytics
                    transportSession:(ZMTransportSession *)transportSession
                     apnsEnvironment:(ZMAPNSEnvironment *)apnsEnvironment
                         application:(id<ZMApplication>)application
                          appVersion:(NSString *)appVersion
                       storeProvider:(id<LocalStoreProviderProtocol>)storeProvider;
{
    if (apnsEnvironment == nil) {
        apnsEnvironment = [[ZMAPNSEnvironment alloc] init];
    }


    [storeProvider.contextDirectory.syncContext performBlockAndWait:^{
        storeProvider.contextDirectory.syncContext.analytics = analytics;
    }];

    [[BackgroundActivityFactory sharedInstance] setApplication:[UIApplication sharedApplication]]; // TODO make BackgroundActivityFactory work with ZMApplication
    [[BackgroundActivityFactory sharedInstance] setMainGroupQueue:storeProvider.contextDirectory.uiContext];
    
    RequestLoopAnalyticsTracker *tracker = [[RequestLoopAnalyticsTracker alloc] initWithAnalytics:analytics];
    
    if ([transportSession respondsToSelector:@selector(setRequestLoopDetectionCallback:)]) {
        transportSession.requestLoopDetectionCallback = ^(NSString *path) {
            // The tracker will return NO in case the path should be ignored.
            if (! [tracker tagWithPath:path]) {
                return;
            }
            ZMLogWarn(@"Request loop happening at path: %@", path);
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:ZMTransportRequestLoopNotificationName object:nil userInfo:@{@"path" : path}];
            });
        };
    }
    
    self = [self initWithTransportSession:transportSession
                             mediaManager:mediaManager
                              flowManager:flowManager
                          apnsEnvironment:apnsEnvironment
                            operationLoop:nil
                              application:application
                               appVersion:appVersion
                            storeProvider:storeProvider];
    return self;
}

- (instancetype)initWithTransportSession:(ZMTransportSession *)session
                            mediaManager:(AVSMediaManager *)mediaManager
                             flowManager:(id<FlowManagerType>)flowManager
                         apnsEnvironment:(ZMAPNSEnvironment *)apnsEnvironment
                           operationLoop:(ZMOperationLoop *)operationLoop
                             application:(id<ZMApplication>)application
                              appVersion:(NSString *)appVersion
                            storeProvider:(id<LocalStoreProviderProtocol>)storeProvider
{
    self = [super init];
    if(self) {
        self.storeProvider = storeProvider;

        self.appVersion = appVersion;
        [ZMUserAgent setWireAppVersion:appVersion];
        self.didStartInitialSync = NO;
        self.pushChannelIsOpen = NO;

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(pushChannelDidChange:) name:ZMPushChannelStateChangeNotificationName object:nil];

        self.apnsEnvironment = apnsEnvironment;
        self.networkIsOnline = YES;
        self.managedObjectContext.isOffline = NO;
        
        [self.syncManagedObjectContext performBlockAndWait:^{
            self.syncManagedObjectContext.zm_userInterfaceContext = self.managedObjectContext;
        }];
        self.managedObjectContext.zm_syncContext = self.syncManagedObjectContext;
        
        NSURL *cacheLocation = [NSFileManager.defaultManager cachesURLForAccountWith:storeProvider.userIdentifier in:storeProvider.applicationContainer];
        [self.class moveCachesIfNeededForAccountWith:storeProvider.userIdentifier in:storeProvider.applicationContainer];
        
        UserImageLocalCache *userImageCache = [[UserImageLocalCache alloc] initWithLocation:cacheLocation];
        self.managedObjectContext.zm_userImageCache = userImageCache;
        
        ImageAssetCache *imageAssetCache = [[ImageAssetCache alloc] initWithMBLimit:500 location:cacheLocation];
        self.managedObjectContext.zm_imageAssetCache = imageAssetCache;
        
        FileAssetCache *fileAssetCache = [[FileAssetCache alloc] initWithLocation:cacheLocation];
        self.managedObjectContext.zm_fileAssetCache = fileAssetCache;
        
        CTCallCenter *callCenter = [[CTCallCenter alloc] init];
        self.managedObjectContext.zm_coreTelephonyCallCenter = callCenter;
        
        [self.syncManagedObjectContext performBlockAndWait:^{
            self.syncManagedObjectContext.zm_imageAssetCache = imageAssetCache;
            self.syncManagedObjectContext.zm_userImageCache = userImageCache;
            self.syncManagedObjectContext.zm_fileAssetCache = fileAssetCache;
            
            self.localNotificationDispatcher = [[LocalNotificationDispatcher alloc] initWithManagedObjectContext:self.syncManagedObjectContext
                                                                                                     application:application];
            self.callStateObserver = [[ZMCallStateObserver alloc] initWithLocalNotificationDispatcher:self.localNotificationDispatcher
                                                                                          userSession:self];
            
            self.transportSession = session;
            self.transportSession.pushChannel.clientID = self.selfUserClient.remoteIdentifier;
            self.transportSession.networkStateDelegate = self;
            self.mediaManager = mediaManager;
        }];

        _application = application;
        self.topConversationsDirectory = [[TopConversationsDirectory alloc] initWithManagedObjectContext:self.managedObjectContext];
        
        [self.syncManagedObjectContext performBlockAndWait:^{
    
            self.operationLoop = operationLoop ?: [[ZMOperationLoop alloc] initWithTransportSession:session
                                                                                      cookieStorage:session.cookieStorage
                                                                        localNotificationDispatcher:self.localNotificationDispatcher
                                                                                       mediaManager:mediaManager
                                                                                        flowManager:flowManager
                                                                                      storeProvider:storeProvider
                                                                                  syncStateDelegate:self
                                                                                        application:application];
            
            __weak id weakSelf = self;
            session.accessTokenRenewalFailureHandler = ^(ZMTransportResponse *response) {
                ZMUserSession *strongSelf = weakSelf;
                [strongSelf transportSessionAccessTokenDidFail:response];
            };
            session.accessTokenRenewalSuccessHandler = ^(NSString *token, NSString *type) {
                ZMUserSession *strongSelf = weakSelf;
                [strongSelf transportSessionAccessTokenDidSucceedWithToken:token ofType:type];
            };
        }];
        
        self.commonContactsCache = [[NSCache alloc] init];
        self.commonContactsCache.name = @"ZMUserSession commonContactsCache";
        
        [self registerForResetPushTokensNotification];
        [self registerForBackgroundNotifications];
        [self registerForRequestToOpenConversationNotification];
        
        [self.syncManagedObjectContext performGroupedBlockAndWait:^{
            [self enablePushNotifications];
        }];
        [self enableBackgroundFetch];

        self.storedDidSaveNotifications = [[ContextDidSaveNotificationPersistence alloc] initWithAccountContainer:self.storeProvider.accountContainer];
        
        [self.syncManagedObjectContext performBlockAndWait:^{
            if (self.clientRegistrationStatus.currentPhase != ZMClientRegistrationPhaseRegistered) {
                [self.clientRegistrationStatus prepareForClientRegistration];
            }
        }];
        
        [ZMRequestAvailableNotification notifyNewRequestsAvailable:self];
    }
    return self;
}

- (void)tearDown
{
    [self.application unregisterObserverForStateChange:self];
    self.mediaManager = nil;
    self.callStateObserver = nil;
    [self.operationLoop tearDown];
    self.operationLoop = nil;
    [self.transportSession tearDown];
    self.transportSession = nil;
    
    [self.localNotificationDispatcher tearDown];
    self.localNotificationDispatcher = nil;
    [self.blackList teardown];
    
    __block NSMutableArray *keysToRemove = [NSMutableArray array];
    [self.managedObjectContext.userInfo enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL * ZM_UNUSED stop) {
        if ([obj respondsToSelector:@selector((tearDown))]) {
            [obj tearDown];
            [keysToRemove addObject:key];
        }
    }];
    [self.managedObjectContext.userInfo removeObjectsForKeys:keysToRemove];
    [keysToRemove removeAllObjects];
    [self.syncManagedObjectContext performBlockAndWait:^{
        [self.managedObjectContext.userInfo enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL * ZM_UNUSED stop) {
            if ([obj respondsToSelector:@selector((tearDown))]) {
                [obj tearDown];
            }
            [keysToRemove addObject:key];
        }];
        [self.syncManagedObjectContext.userInfo removeObjectsForKeys:keysToRemove];
    }];
    
    NSManagedObjectContext *uiMoc = self.managedObjectContext;
    self.storeProvider = nil;
    
    BOOL shouldWaitOnUiMoc = !([NSOperationQueue currentQueue] == [NSOperationQueue mainQueue] && uiMoc.concurrencyType == NSMainQueueConcurrencyType);
    
    if(shouldWaitOnUiMoc)
    {
        [uiMoc performBlockAndWait:^{ // warning: this will hang if the uiMoc queue is same as self.requestQueue (typically uiMoc queue is the main queue)
            // nop
        }];
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    self.blackList = nil;
}

- (BOOL)isNotificationContentHidden;
{
    return [[self.managedObjectContext persistentStoreMetadataForKey:LocalNotificationDispatcher.ZMShouldHideNotificationContentKey] boolValue];
}

- (void)setIsNotificationContentHidden:(BOOL)isNotificationContentHidden;
{
    [self.managedObjectContext setPersistentStoreMetadata:@(isNotificationContentHidden) forKey:LocalNotificationDispatcher.ZMShouldHideNotificationContentKey];
}

- (BOOL)isLoggedIn
{
    return self.authenticationStatus.isAuthenticated &&
           self.clientRegistrationStatus.currentPhase == ZMClientRegistrationPhaseRegistered;
}

- (void)registerForRequestToOpenConversationNotification
{
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didRequestToOpenSyncConversation:) name:ZMRequestToOpenSyncConversationNotificationName object:nil];
}

- (void)registerForBackgroundNotifications;
{
    [self.application registerObserverForDidEnterBackground:self selector:@selector(applicationDidEnterBackground:)];
    [self.application registerObserverForWillEnterForeground:self selector:@selector(applicationWillEnterForeground:)];
}

- (void)registerForResetPushTokensNotification
{
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(resetPushTokens) name:ZMUserSessionResetPushTokensNotificationName object:nil];
}

- (NSManagedObjectContext *)managedObjectContext
{
    return self.storeProvider.contextDirectory.uiContext;
}

- (NSManagedObjectContext *)syncManagedObjectContext
{
    return self.storeProvider.contextDirectory.syncContext;
}

- (NSManagedObjectContext *)searchManagedObjectContext
{
    return self.storeProvider.contextDirectory.searchContext;
}

- (NSURL *)sharedContainerURL
{
    return self.storeProvider.applicationContainer;
}

- (void)didRequestToOpenSyncConversation:(NSNotification *)note
{
    ZM_WEAK(self);
    [self.managedObjectContext performGroupedBlock:^{
        ZM_STRONG(self);
        NSManagedObjectID *objectID = note.object;
        id managedObject = [self.managedObjectContext objectWithID:objectID];
        if(managedObject != nil) {
            [self.requestToOpenViewDelegate showConversation:managedObject];
        }
    }];
}


- (void)saveOrRollbackChanges;
{
    [self.managedObjectContext saveOrRollback];
}

- (void)performChanges:(dispatch_block_t)block;
{
    ZM_WEAK(self);
    [self.managedObjectContext performGroupedBlockAndWait:^{
        ZM_STRONG(self);
        block();
        [self saveOrRollbackChanges];
    }];
}

- (void)enqueueChanges:(dispatch_block_t)block
{
    [self enqueueChanges:block completionHandler:nil];
}

- (void)enqueueChanges:(dispatch_block_t)block completionHandler:(dispatch_block_t)completionHandler;
{
    ZM_WEAK(self);
    [self.managedObjectContext performGroupedBlock:^{
        ZM_STRONG(self);
        block();
        [self saveOrRollbackChanges];
        
        if(completionHandler != nil) {
            completionHandler();
        }
    }];
}

- (void)registerForRemoteNotifications
{
    [self.managedObjectContext performGroupedBlock:^{
        // Refresh the Voip token if needed
        NSData *actualToken = self.pushRegistrant.pushToken;
        if (actualToken != nil && ![actualToken isEqual:self.managedObjectContext.pushKitToken.deviceToken]){
            self.managedObjectContext.pushKitToken = nil;
            [self setPushKitToken:actualToken];
        }
        
        // Request the current token, the rest is taken care of
        [self setupPushNotificationsForApplication:self.application];
    }];
}

- (void)resetPushTokens
{
    // instead of relying on the tokens we have cached locally we should always ask the OS about the latest tokens
    [self.managedObjectContext performGroupedBlock:^{
        
        // (1) Refresh VoIP token
        NSData *pushKitToken = self.pushRegistrant.pushToken;
        if (pushKitToken != nil) {
            self.managedObjectContext.pushKitToken = nil;
            [self setPushKitToken:pushKitToken];
        } else {
            ZMLogError(@"The OS did not provide a valid VoIP token, pushRegistry might be nil");
        }
        
        // (2) Refresh "normal" remote notification token
        // we need to set the current push token to nil,
        // otherwise if the push token didn't change it would not resend the request to the backend
        self.managedObjectContext.pushToken = nil;
        
        // according to Apple's documentation, calling [registerForRemoteNotifications] should not cause additional overhead
        // and should return the *existing* device token to the app delegate via [didRegisterForRemoteNotifications:] immediately
        // this call is forwarded to the ZMUserSession+Background where the new token is set
        [self.application registerForRemoteNotifications];
        
        // (3) reset the preKeys for encrypting and decrypting
        [UserClient resetSignalingKeysInContext:self.managedObjectContext];

        if (![self.managedObjectContext forceSaveOrRollback]) {
            ZMLogError(@"Failed to save push token after refresh");
        }
        
    }];
}

- (void)initiateUserDeletion
{
    [self.syncManagedObjectContext performGroupedBlock:^{
        [self.syncManagedObjectContext setPersistentStoreMetadata:@YES forKey:[DeleteAccountRequestStrategy userDeletionInitiatedKey]];
        [ZMRequestAvailableNotification notifyNewRequestsAvailable:self];
    }];
}

- (void)openAppstore
{
    NSURL *appStoreURL = [NSURL URLWithString:AppstoreURL];
    [[UIApplication sharedApplication] openURL:appStoreURL];
    [NSTimer scheduledTimerWithTimeInterval:30 target:self selector:@selector(didNotUpdateApp:) userInfo:nil repeats:NO];
}

- (void)didNotUpdateApp:(NSTimer *)timer;
{
    NOT_USED(timer);
    __builtin_trap();
}

- (void)transportSessionAccessTokenDidFail:(ZMTransportResponse *)response
{
    ZMLogWithLevelAndTag(ZMLogLevelDebug, ZMTAG_NETWORK, @"Access token fail in %@: %@", self.class, NSStringFromSelector(_cmd));
    NOT_USED(response);
    
    [self.syncManagedObjectContext performGroupedBlock:^{
        self.syncManagedObjectContext.accessToken = nil;
    }];

    
    [self.managedObjectContext performGroupedBlock:^{
        ZMUser *selfUser = [ZMUser selfUserInContext:self.managedObjectContext];
        [ZMUserSessionAuthenticationNotification notifyAuthenticationDidFail:[NSError userSessionErrorWithErrorCode:ZMUserSessionAccessTokenExpired userInfo:selfUser.credentialsUserInfo]];
    }];
}

- (void)transportSessionAccessTokenDidSucceedWithToken:(NSString *)token ofType:(NSString *)type;
{
    ZMLogWithLevelAndTag(ZMLogLevelDebug, ZMTAG_NETWORK, @"Access token succeeded in %@: %@", self.class, NSStringFromSelector(_cmd));
    
    [self.syncManagedObjectContext performGroupedBlock:^{
        self.syncManagedObjectContext.accessToken = [[ZMAccessToken alloc] initWithToken:token type:type expiresInSeconds:0];
    }];
}

- (void)notifyThirdPartyServices;
{
    if (! self.didNotifyThirdPartyServices) {
        self.didNotifyThirdPartyServices = YES;
        [self.thirdPartyServicesDelegate userSessionIsReadyToUploadServicesData:self];
    }
}

- (ZMOperationStatus *)operationStatus
{
    return self.operationLoop.syncStrategy.applicationStatusDirectory.operationStatus;
}

- (void)setCallNotificationStyle:(ZMCallNotificationStyle)callNotificationStyle
{
    _callNotificationStyle = callNotificationStyle;
    
    switch (callNotificationStyle) {
        case ZMCallNotificationStylePushNotifications:
            self.callKitDelegate = nil;
            break;
        case ZMCallNotificationStyleCallKit:
        {
            CXProvider *provider = [[CXProvider alloc] initWithConfiguration:[ZMCallKitDelegate providerConfiguration]];
            CXCallController *callController = [[CXCallController alloc] initWithQueue:dispatch_get_main_queue()];
            
            self.callKitDelegate = [[ZMCallKitDelegate alloc] initWithCallKitProvider:provider
                                                                       callController:callController
                                                                          flowManager:self.flowManager
                                                                          userSession:self
                                                                         mediaManager:(AVSMediaManager *)self.mediaManager];
        }
            break;
    }
}

- (WireCallCenterV3* )callCenter
{
    return self.managedObjectContext.zm_callCenter;
}

@end



@implementation ZMUserSession (Test)

- (NSArray *)allManagedObjectContexts
{
    NSMutableArray *mocs = [NSMutableArray array];
    if (self.managedObjectContext != nil) {
        [mocs addObject:self.managedObjectContext];
    }
    if (self.syncManagedObjectContext != nil) {
        [mocs addObject:self.syncManagedObjectContext];
    }
    return mocs;
}

@end



@implementation ZMUserSession (PushToken)


- (void)setPushToken:(NSData *)deviceToken;
{
    NSString *transportType = [self.apnsEnvironment transportTypeForTokenType:ZMAPNSTypeNormal];
    NSString *appIdentifier = self.apnsEnvironment.appIdentifier;
    ZMPushToken *token = nil;
    if (transportType != nil && deviceToken != nil && appIdentifier != nil) {
        token = [[ZMPushToken alloc] initWithDeviceToken:deviceToken identifier:appIdentifier transportType:transportType fallback:nil isRegistered:NO];
    }
    
    if ((self.managedObjectContext.pushToken != token) && ! [self.managedObjectContext.pushToken isEqual:token]) {
        self.managedObjectContext.pushToken = token;
        if (![self.managedObjectContext forceSaveOrRollback]) {
            ZMLogError(@"Failed to save push token");
        }
    }
}

- (void)setPushKitToken:(NSData *)deviceToken;
{
    ZMAPNSType apnsType = ZMAPNSTypeVoIP;
    NSString *transportType = [self.apnsEnvironment transportTypeForTokenType:apnsType];
    NSString *appIdentifier = self.apnsEnvironment.appIdentifier;
    ZMPushToken *token = nil;
    if (transportType != nil && deviceToken != nil && appIdentifier != nil) {
        NSString *fallback = [self.apnsEnvironment fallbackForTransportType:apnsType];
        token = [[ZMPushToken alloc] initWithDeviceToken:deviceToken identifier:appIdentifier transportType:transportType fallback:fallback isRegistered:NO];
    }
    if ((self.managedObjectContext.pushKitToken != token) && ! [self.managedObjectContext.pushKitToken isEqual:token]) {
        self.managedObjectContext.pushKitToken = token;
        if (![self.managedObjectContext forceSaveOrRollback]) {
            ZMLogError(@"Failed to save pushKit token");
        }
    }
}

- (void)deletePushKitToken
{
    if(self.managedObjectContext.pushKitToken) {
        self.managedObjectContext.pushKitToken = [self.managedObjectContext.pushKitToken forDeletionMarkedCopy];
        if (![self.managedObjectContext forceSaveOrRollback]) {
            ZMLogError(@"Failed to save pushKit token marked for deletion");
        }
    }
}

@end



@implementation ZMUserSession (Transport)

- (void)addCompletionHandlerForBackgroundURLSessionWithIdentifier:(NSString *)identifier handler:(dispatch_block_t)handler
{
    [self.transportSession addCompletionHandlerForBackgroundSessionWithIdentifier:identifier handler:handler];
}

@end






@implementation ZMUserSession(NetworkState)

- (void)changeNetworkStateAndNotify;
{
    ZMNetworkState state;
    if (self.networkIsOnline) {
        if (self.isPerformingSync) {
            state = ZMNetworkStateOnlineSynchronizing;
        } else {
            state = ZMNetworkStateOnline;
        }
        self.managedObjectContext.isOffline = NO;
    } else {
        state = ZMNetworkStateOffline;
        self.managedObjectContext.isOffline = YES;
    }
    
    ZMNetworkState const previous = self.networkState;
    self.networkState = state;
    if(previous != self.networkState && self.application.applicationState != UIApplicationStateBackground) {
        [[NSNotificationCenter defaultCenter] postNotification:[ZMNetworkAvailabilityChangeNotification notificationWithNetworkState:self.networkState userSession:self]];
    }
}

- (void)didReceiveData
{
    ZM_WEAK(self);
    [self.managedObjectContext performGroupedBlock:^{
        ZM_STRONG(self);
        self.networkIsOnline = YES;
        [self changeNetworkStateAndNotify];
    }];
}

- (void)didGoOffline
{
    ZM_WEAK(self);
    [self.managedObjectContext performGroupedBlock:^{
        ZM_STRONG(self);
        self.networkIsOnline = NO;
        
        [self changeNetworkStateAndNotify];
        [self saveOrRollbackChanges];
    }];
}

- (void)didStartSync
{
    ZM_WEAK(self);
    [self.managedObjectContext performGroupedBlock:^{
        ZM_STRONG(self);
        self.isPerformingSync = YES;
        self.didStartInitialSync = YES;
        [self changeNetworkStateAndNotify];
    }];
}

- (void)didFinishSync
{
    ZM_WEAK(self);
    [self.managedObjectContext performGroupedBlock:^{
        ZM_STRONG(self);
        self.isPerformingSync = NO;
        self.hasCompletedInitialSync = YES;
        [self changeNetworkStateAndNotify];
        [self notifyThirdPartyServices];
        [self processPendingNotificationActions];
    }];
}

- (void)didRegisterUserClient:(UserClient *)userClient
{
    self.transportSession.pushChannel.clientID = userClient.remoteIdentifier;
}

@end

@implementation ZMUserSession(PushChannel)

- (void)pushChannelDidChange:(NSNotification *)note
{
    BOOL newValue = [note.userInfo[ZMPushChannelIsOpenKey] boolValue];
    self.pushChannelIsOpen = newValue;
}

@end



@implementation NSManagedObjectContext (NetworkState)

static NSString * const IsOfflineKey = @"IsOfflineKey";

- (void)setIsOffline:(BOOL)isOffline;
{
    self.userInfo[IsOfflineKey] = [NSNumber numberWithBool:isOffline];
}

- (BOOL)isOffline;
{
    return [self.userInfo[IsOfflineKey] boolValue];
}

@end


@implementation ZMUserSession (LaunchOptions)

- (void)didLaunchWithURL:(NSURL *)URL;
{
    if ([URL isURLForPhoneVerification]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:ZMLaunchedWithPhoneVerificationCodeNotificationName
                                                            object:nil
                                                          userInfo:@{ ZMPhoneVerificationCodeKey : [URL codeForPhoneVerification] }];
    }
}

@end



@implementation ZMUserSession (RequestToOpenConversation)

+ (void)requestToOpenSyncConversationOnUI:(ZMConversation *)conversation;
{
    [[NSNotificationCenter defaultCenter] postNotificationName:ZMRequestToOpenSyncConversationNotificationName object:conversation.objectID];
}

@end



@implementation ZMUserSession (AVSLogging)

+ (id<ZMAVSLogObserverToken>)addAVSLogObserver:(id<ZMAVSLogObserver>)observer;
{
    ZM_WEAK(observer);
    return (id<ZMAVSLogObserverToken>)[[NSNotificationCenter defaultCenter] addObserverForName:@"AVSLogMessageNotification"
                                                                                        object:nil
                                                                                         queue:nil
                                                                                    usingBlock:^(NSNotification * _Nonnull note) {
                                                                                        ZM_STRONG(observer);
                                                                                        [observer logMessage:note.userInfo[@"message"]];
                                                                                    }];
}

+ (void)removeAVSLogObserver:(id<ZMAVSLogObserverToken>)token;
{
    [[NSNotificationCenter defaultCenter] removeObserver:token];
}

+ (void)appendAVSLogMessageForConversation:(ZMConversation *)conversation withMessage:(NSString *)message;
{
    NSDictionary *userInfo = @{@"message" :message};
    
    [[NSNotificationCenter defaultCenter] postNotificationName:ZMAppendAVSLogNotificationName object:conversation userInfo:userInfo];
}

@end

@implementation ZMUserSession (Calling)

- (CallingRequestStrategy *)callingStrategy
{
    return self.operationLoop.syncStrategy.callingRequestStrategy;
}

@end



@implementation ZMUserSession (SelfUserClient)

- (id<UserProfile>)userProfile
{
    return self.userProfileUpdateStatus;
}

- (UserClient *)selfUserClient
{
    return [ZMUser selfUserInContext:self.managedObjectContext].selfClient;
}

@end



@implementation ZMUserSession (AuthenticationStatus)

- (id<AuthenticationStatusProvider>)authenticationStatus
{
    return self.transportSession.cookieStorage;
}

- (UserProfileUpdateStatus *)userProfileUpdateStatus;
{
    return self.operationLoop.syncStrategy.applicationStatusDirectory.userProfileUpdateStatus;
}

- (ZMClientRegistrationStatus *)clientRegistrationStatus;
{
    return self.operationLoop.syncStrategy.applicationStatusDirectory.clientRegistrationStatus;
}

- (ClientUpdateStatus *)clientUpdateStatus;
{
    return self.operationLoop.syncStrategy.applicationStatusDirectory.clientUpdateStatus;
}

- (ZMAccountStatus *)accountStatus;
{
    return self.operationLoop.syncStrategy.applicationStatusDirectory.accountStatus;
}

- (ProxiedRequestsStatus *)proxiedRequestStatus;
{
    return self.operationLoop.syncStrategy.applicationStatusDirectory.proxiedRequestStatus;
}

@end

@implementation ZMUserSession (ProfilePictureUpdate)

- (id<UserProfileImageUpdateProtocol>)profileUpdate
{
    return self.operationLoop.syncStrategy.applicationStatusDirectory.userProfileImageUpdateStatus;
}

@end
