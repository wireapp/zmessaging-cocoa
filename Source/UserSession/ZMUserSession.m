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
@import ZMCSystem;
@import ZMUtilities;
@import ZMCDataModel;
@import CallKit;
@import CoreTelephony;

#import "ZMUserSession+Background.h"

#import "ZMUserSession+Internal.h"
#import "ZMUserSession+OperationLoop.h"
#import "ZMSyncStrategy.h"
#import "NSError+ZMUserSessionInternal.h"
#import "ZMCredentials.h"
#import "ZMSearchDirectory+Internal.h"
#import <libkern/OSAtomic.h>
#import "ZMAuthenticationStatus.h"
#import "ZMPushToken.h"
#import "ZMCommonContactsSearch.h"
#import "ZMBlacklistVerificator.h"
#import "ZMSyncStateMachine.h"
#import "ZMUserSessionAuthenticationNotification.h"
#import "NSURL+LaunchOptions.h"
#import "ZMessagingLogs.h"
#import "ZMAVSBridge.h"
#import "ZMOnDemandFlowManager.h"
#import "ZMCookie.h"
#import "ZMFlowSync.h"
#import "ZMCallKitDelegate.h"
#import "ZMOperationLoop+Private.h"
#import <zmessaging/zmessaging-Swift.h>

#import "ZMEnvironmentsSetup.h"
#import "ZMClientRegistrationStatus.h"
#import "ZMCallKitDelegate+TypeConformance.h"
#import "CallingProtocolStrategy.h"

NSString * const ZMPhoneVerificationCodeKey = @"code";
NSString * const ZMLaunchedWithPhoneVerificationCodeNotificationName = @"ZMLaunchedWithPhoneVerificationCode";
static NSString * const ZMRequestToOpenSyncConversationNotificationName = @"ZMRequestToOpenSyncConversation";
NSString * const ZMAppendAVSLogNotificationName = @"ZMAppendAVSLogNotification";
NSString * const ZMUserSessionResetPushTokensNotificationName = @"ZMUserSessionResetPushTokensNotification";
NSString * const ZMTransportRequestLoopNotificationName = @"ZMTransportRequestLoopNotificationName";

static NSString * const AppstoreURL = @"https://itunes.apple.com/us/app/zeta-client/id930944768?ls=1&mt=8";


@interface ZMUserSession ()
@property (nonatomic) ZMOperationLoop *operationLoop;
@property (nonatomic) ZMTransportRequest *runningLoginRequest;
@property (nonatomic) BOOL ownsQueue;
@property (nonatomic) ZMTransportSession *transportSession;
@property (nonatomic) NSManagedObjectContext *managedObjectContext;
@property (nonatomic) NSManagedObjectContext *syncManagedObjectContext;
@property (atomic) ZMNetworkState networkState;
@property (nonatomic) ZMBlacklistVerificator *blackList;
@property (nonatomic) ZMAPNSEnvironment *apnsEnvironment;
@property (nonatomic) ZMAuthenticationStatus *authenticationStatus;
@property (nonatomic) UserProfileUpdateStatus *userProfileUpdateStatus;
@property (nonatomic) ZMClientRegistrationStatus *clientRegistrationStatus;
@property (nonatomic) ClientUpdateStatus *clientUpdateStatus;
@property (nonatomic) BackgroundAPNSPingBackStatus *pingBackStatus;
@property (nonatomic) ZMAccountStatus *accountStatus;

@property (nonatomic) ProxiedRequestsStatus *proxiedRequestStatus;

@property (nonatomic) BOOL isVersionBlacklisted;
@property (nonatomic) ZMOnDemandFlowManager *onDemandFlowManager;

@property (nonatomic) ZMPushRegistrant *pushRegistrant;
@property (nonatomic) ZMApplicationRemoteNotification *applicationRemoteNotification;
@property (nonatomic) ZMStoredLocalNotification *pendingLocalNotification;
@property (nonatomic) LocalNotificationDispatcher *localNotificationDispatcher;
@property (nonatomic) NSString *applicationGroupIdentifier;
@property (nonatomic) NSURL *storeURL;
@property (nonatomic) NSURL *keyStoreURL;
@property (nonatomic, readwrite) NSURL *sharedContainerURL;
@property (nonatomic) TopConversationsDirectory *topConversationsDirectory;
@property (nonatomic) SystemMessageCallObserver *systemMessageCallObserver;


/// Build number of the Wire app
@property (nonatomic) NSString *appVersion;

/// map from NSUUID to ZMCommonContactsSearchCachedEntry
@property (nonatomic) NSCache *commonContactsCache;
@end

@interface ZMUserSession(PushChannel)
- (void)pushChannelDidChange:(NSNotification *)note;
@end

@interface ZMUserSession (AlertView) <UIAlertViewDelegate>
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

+ (NSURL *)sharedContainerDirectoryForApplicationGroup:(NSString *)appGroupIdentifier
{
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *sharedContainerURL = [fm containerURLForSecurityApplicationGroupIdentifier:appGroupIdentifier];
    
    if (nil == sharedContainerURL) {
        // Seems like the shared container is not available. This could happen for series of reasons:
        // 1. The app is compiled with with incorrect provisioning profile (for example with 3rd parties)
        // 2. App is running on simulator and there is no correct provisioning profile on the system
        // 3. Bug with signing
        //
        // The app should allow not having a shared container in cases 1 and 2; in case 3 the app should crash
        
        ZMDeploymentEnvironmentType deploymentEnvironment = [[ZMDeploymentEnvironment alloc] init].environmentType;
        if (!TARGET_IPHONE_SIMULATOR && (deploymentEnvironment == ZMDeploymentEnvironmentTypeAppStore || deploymentEnvironment == ZMDeploymentEnvironmentTypeInternal)) {
            RequireString(nil != sharedContainerURL, "Unable to create shared container url using app group identifier: %s", appGroupIdentifier.UTF8String);
        }
        else {
            sharedContainerURL = [[fm URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] firstObject];
            ZMLogError(@"ERROR: self.databaseDirectoryURL == nil and deploymentEnvironment = %d", deploymentEnvironment);
            ZMLogError(@"================================WARNING================================");
            ZMLogError(@"Wire is going to use APPLICATION SUPPORT directory to host the database");
            ZMLogError(@"================================WARNING================================");
        }
    }
    
    return sharedContainerURL;
}

+ (NSURL *)cachesURLForAppGroupIdentifier:(NSString *)appGroupIdentifier
{
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *sharedContainerURL = [fm containerURLForSecurityApplicationGroupIdentifier:appGroupIdentifier];
    
    if (sharedContainerURL != nil) {
        return [[sharedContainerURL URLByAppendingPathComponent:@"Library" isDirectory:YES] URLByAppendingPathComponent:@"Caches" isDirectory:YES];
    }
    
    return nil;
}

+ (NSURL *)keyStoreURLForAppGroupIdentifier:(NSString *)appGroupIdentifier
{
    return [self sharedContainerDirectoryForApplicationGroup:appGroupIdentifier];
}

+ (NSURL *)storeURLForAppGroupIdentifier:(NSString *)appGroupIdentifier
{
    return [[[self sharedContainerDirectoryForApplicationGroup:appGroupIdentifier]
             URLByAppendingPathComponent:[NSBundle mainBundle].bundleIdentifier isDirectory:YES]
             URLByAppendingPathComponent:@"store.wiredatabase"];
}

+ (BOOL)needsToPrepareLocalStoreUsingAppGroupIdentifier:(NSString *)appGroupIdentifier
{
    return [NSManagedObjectContext needsToPrepareLocalStoreAtURL:[self storeURLForAppGroupIdentifier:appGroupIdentifier]];
}

+ (void)prepareLocalStoreUsingAppGroupIdentifier:(NSString *)appGroupIdentifier completion:(void (^)())completionHandler
{
    ZMDeploymentEnvironmentType environment = [[ZMDeploymentEnvironment alloc] init].environmentType;
    BOOL shouldBackupCorruptedDatabase = environment == ZMDeploymentEnvironmentTypeInternal || DEBUG;
    
    [NSManagedObjectContext prepareLocalStoreAtURL:[self storeURLForAppGroupIdentifier:appGroupIdentifier]
                           backupCorruptedDatabase:shouldBackupCorruptedDatabase
                                       synchronous:NO
                                 completionHandler:completionHandler];
}

+ (BOOL)storeIsReady
{
    return [NSManagedObjectContext storeIsReady];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (instancetype)initWithMediaManager:(id<AVSMediaManager>)mediaManager
                           analytics:(id<AnalyticsType>)analytics
                          appVersion:(NSString *)appVersion
                  appGroupIdentifier:(NSString *)appGroupIdentifier;
{
    zmSetupEnvironments();
    ZMBackendEnvironment *environment = [[ZMBackendEnvironment alloc] initWithUserDefaults:NSUserDefaults.standardUserDefaults];
    NSURL *backendURL = environment.backendURL;
    NSURL *websocketURL = environment.backendWSURL;
    self.applicationGroupIdentifier = appGroupIdentifier;

    ZMAPNSEnvironment *apnsEnvironment = [[ZMAPNSEnvironment alloc] init];
    
    self.storeURL = [self.class storeURLForAppGroupIdentifier:appGroupIdentifier];
    self.keyStoreURL = [self.class keyStoreURLForAppGroupIdentifier:appGroupIdentifier];
    RequireString(nil != self.storeURL, "Unable to get a store URL using group identifier: %s", appGroupIdentifier.UTF8String);
    NSManagedObjectContext *userInterfaceContext = [NSManagedObjectContext createUserInterfaceContextWithStoreAtURL:self.storeURL];
    NSManagedObjectContext *syncMOC = [NSManagedObjectContext createSyncContextWithStoreAtURL:self.storeURL keyStoreURL:self.keyStoreURL];
    [syncMOC performBlockAndWait:^{
        syncMOC.analytics = analytics;
    }];

    UIApplication *application = [UIApplication sharedApplication];
    
    ZMTransportSession *session = [[ZMTransportSession alloc] initWithBaseURL:backendURL
                                                                 websocketURL:websocketURL
                                                               mainGroupQueue:userInterfaceContext
                                                           initialAccessToken:[userInterfaceContext accessToken]
                                                                  application:application
                                                    sharedContainerIdentifier:nil];
    
    RequestLoopAnalyticsTracker *tracker = [[RequestLoopAnalyticsTracker alloc] initWithAnalytics:analytics];
    session.requestLoopDetectionCallback = ^(NSString *path) {
        //TAG analytics
        [tracker tagWithPath:path];
        ZMLogWarn(@"Request loop happening at path: %@", path);
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:ZMTransportRequestLoopNotificationName object:nil userInfo:@{@"path" : path}];
        });
    };
    
    
    self = [self initWithTransportSession:session
                     userInterfaceContext:userInterfaceContext
                 syncManagedObjectContext:syncMOC
                             mediaManager:mediaManager
                          apnsEnvironment:apnsEnvironment
                            operationLoop:nil
                              application:application
                               appVersion:appVersion
                       appGroupIdentifier:appGroupIdentifier];
    if (self != nil) {
        self.ownsQueue = YES;
    }
    return self;
}

- (instancetype)initWithTransportSession:(ZMTransportSession *)session
                    userInterfaceContext:(NSManagedObjectContext *)userInterfaceContext
                syncManagedObjectContext:(NSManagedObjectContext *)syncManagedObjectContext
                            mediaManager:(id<AVSMediaManager>)mediaManager
                         apnsEnvironment:(ZMAPNSEnvironment *)apnsEnvironment
                           operationLoop:(ZMOperationLoop *)operationLoop
                             application:(id<ZMApplication>)application
                              appVersion:(NSString *)appVersion
                      appGroupIdentifier:(NSString *)appGroupIdentifier;

{
    self = [super init];
    if(self) {
        zmSetupEnvironments();
        [ZMUserSession enableLogsByEnvironmentVariable];
        self.appVersion = appVersion;
        [ZMUserAgent setWireAppVersion:appVersion];
        self.didStartInitialSync = NO;
        self.pushChannelIsOpen = NO;

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(pushChannelDidChange:) name:ZMPushChannelStateChangeNotificationName object:nil];

        self.sharedContainerURL = [self.class sharedContainerDirectoryForApplicationGroup:appGroupIdentifier];
        self.apnsEnvironment = apnsEnvironment;
        self.networkIsOnline = YES;
        self.managedObjectContext = userInterfaceContext;
        self.managedObjectContext.isOffline = NO;
        self.syncManagedObjectContext = syncManagedObjectContext;
        
        [self.syncManagedObjectContext performBlockAndWait:^{
            self.syncManagedObjectContext.zm_userInterfaceContext = self.managedObjectContext;
        }];
        self.managedObjectContext.zm_syncContext = self.syncManagedObjectContext;
        
        NSURL *cacheLocation = [self.class cachesURLForAppGroupIdentifier:appGroupIdentifier];
        
        UserImageLocalCache *userImageCache = [[UserImageLocalCache alloc] initWithLocation:cacheLocation];
        self.managedObjectContext.zm_userImageCache = userImageCache;
        
        ImageAssetCache *imageAssetCache = [[ImageAssetCache alloc] initWithMBLimit:500 location:cacheLocation];
        self.managedObjectContext.zm_imageAssetCache = imageAssetCache;
        
        FileAssetCache *fileAssetCache = [[FileAssetCache alloc] initWithLocation:cacheLocation];
        self.managedObjectContext.zm_fileAssetCache = fileAssetCache;
        
        CTCallCenter *callCenter = [[CTCallCenter alloc] init];
        self.managedObjectContext.zm_callCenter = callCenter;
        
        [self.syncManagedObjectContext performBlockAndWait:^{
            self.syncManagedObjectContext.zm_imageAssetCache = imageAssetCache;
            self.syncManagedObjectContext.zm_userImageCache = userImageCache;
            self.syncManagedObjectContext.zm_fileAssetCache = fileAssetCache;
            
            ZMCookie *cookie = [[ZMCookie alloc] initWithManagedObjectContext:self.syncManagedObjectContext cookieStorage:session.cookieStorage];
            self.authenticationStatus = [[ZMAuthenticationStatus alloc] initWithManagedObjectContext:syncManagedObjectContext cookie:cookie];
            self.userProfileUpdateStatus = [[UserProfileUpdateStatus alloc] initWithManagedObjectContext:syncManagedObjectContext];
            self.clientUpdateStatus = [[ClientUpdateStatus alloc] initWithSyncManagedObjectContext:syncManagedObjectContext];
            
            self.clientRegistrationStatus = [[ZMClientRegistrationStatus alloc] initWithManagedObjectContext:syncManagedObjectContext
                                                                                     loginCredentialProvider:self.authenticationStatus
                                                                                    updateCredentialProvider:self.userProfileUpdateStatus
                                                                                                      cookie:cookie
                                                                                  registrationStatusDelegate:self];
            self.accountStatus = [[ZMAccountStatus alloc] initWithManagedObjectContext: syncManagedObjectContext cookieStorage: session.cookieStorage];
            
            
            
            self.localNotificationDispatcher =
            [[LocalNotificationDispatcher alloc] initWithManagedObjectContext:syncManagedObjectContext application:application];
            
            self.pingBackStatus = [[BackgroundAPNSPingBackStatus alloc] initWithSyncManagedObjectContext:syncManagedObjectContext
                                                                                  authenticationProvider:self.authenticationStatus];

           self.callStateObserver = [[ZMCallStateObserver alloc] initWithLocalNotificationDispatcher:self.localNotificationDispatcher
                                                                                managedObjectContext:syncManagedObjectContext];
            
            self.transportSession = session;
            self.transportSession.clientID = self.selfUserClient.remoteIdentifier;
            self.transportSession.networkStateDelegate = self;
            self.mediaManager = mediaManager;
            
            self.onDemandFlowManager = [[ZMOnDemandFlowManager alloc] initWithMediaManager:mediaManager];
            self.proxiedRequestStatus = [[ProxiedRequestsStatus alloc] initWithRequestCancellation:self.transportSession];
        }];
        
        _application = application;
        self.topConversationsDirectory = [[TopConversationsDirectory alloc] initWithManagedObjectContext:self.managedObjectContext];
        
        [self.syncManagedObjectContext performBlockAndWait:^{
    
            self.operationLoop = operationLoop ?: [[ZMOperationLoop alloc] initWithTransportSession:session
                                                                               authenticationStatus:self.authenticationStatus
                                                                            userProfileUpdateStatus:self.userProfileUpdateStatus
                                                                           clientRegistrationStatus:self.clientRegistrationStatus
                                                                                 clientUpdateStatus:self.clientUpdateStatus
                                                                               proxiedRequestStatus:self.proxiedRequestStatus
                                                                                      accountStatus:self.accountStatus
                                                                       backgroundAPNSPingBackStatus:self.pingBackStatus
                                                                        localNotificationdispatcher:self.localNotificationDispatcher
                                                                                       mediaManager:mediaManager
                                                                                onDemandFlowManager:self.onDemandFlowManager
                                                                                              uiMOC:self.managedObjectContext
                                                                                            syncMOC:self.syncManagedObjectContext
                                                                                  syncStateDelegate:self
                                                                                 appGroupIdentifier:appGroupIdentifier
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

        self.storedDidSaveNotifications = [[ContextDidSaveNotificationPersistence alloc] initWithSharedContainerURL:self.sharedContainerURL];
        
        ZM_ALLOW_MISSING_SELECTOR([[NSNotificationCenter defaultCenter] addObserver:self
                                                                           selector:@selector(didEnterEventProcessingState:)
                                                                               name:ZMApplicationDidEnterEventProcessingStateNotificationName
                                                                             object:nil]);
        if ([self.class useCallKit]) {
            CXProvider *provider = [[CXProvider alloc] initWithConfiguration:[ZMCallKitDelegate providerConfiguration]];
            CXCallController *callController = [[CXCallController alloc] initWithQueue:dispatch_get_main_queue()];
            
            self.callKitDelegate = [[ZMCallKitDelegate alloc] initWithCallKitProvider:provider
                                                                       callController:callController
                                                                  onDemandFlowManager:self.onDemandFlowManager
                                                                          userSession:self
                                                                         mediaManager:(AVSMediaManager *)mediaManager];
        }

        self.systemMessageCallObserver = [[SystemMessageCallObserver alloc] initWithUserSession:self];
    }
    return self;
}

- (void)tearDown
{
    [self.application unregisterObserverForStateChange:self];
    self.mediaManager = nil;
    [self.operationLoop tearDown];
    [self.localNotificationDispatcher tearDown];
    self.localNotificationDispatcher = nil;
    [self.blackList teardown];
    
    if(self.ownsQueue) {
        [self.transportSession tearDown];
        self.transportSession = nil;
    }
    [self.clientUpdateStatus tearDown];
    self.clientUpdateStatus = nil;
    [self.clientRegistrationStatus tearDown];
    self.clientRegistrationStatus = nil;
    self.authenticationStatus = nil;
    self.userProfileUpdateStatus = nil;
    self.proxiedRequestStatus = nil;
    
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
    self.managedObjectContext = nil;
    self.syncManagedObjectContext = nil;
    
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
    return self.authenticationStatus.currentPhase == ZMAuthenticationPhaseAuthenticated &&
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

- (void)setMediaManager:(id <AVSMediaManager>)delegate;
{
    NOT_USED(delegate);
}

- (void)startAndCheckClientVersionWithCheckInterval:(NSTimeInterval)interval blackListedBlock:(void (^)())blackListed;
{
    [self start];
    ZM_WEAK(self);
    self.blackList = [[ZMBlacklistVerificator alloc] initWithCheckInterval:interval
                                                                   version:self.appVersion
                                                              workingGroup:self.syncManagedObjectContext.dispatchGroup
                                                               application:self.application
                                                         blacklistCallback:^(BOOL isBlackListed) {
        ZM_STRONG(self);
        if (!self.isVersionBlacklisted && isBlackListed && blackListed) {
            blackListed();
            self.isVersionBlacklisted = YES;
        }
    }];
}

- (void)start;
{
    [self didStartApplication];
    [self refreshTokensIfNeeded];
    [ZMRequestAvailableNotification notifyNewRequestsAvailable:self];
}

- (void)didStartApplication
{
    [self.syncManagedObjectContext performGroupedBlock:^{
        if (self.isLoggedIn) {
            [ZMUserSessionAuthenticationNotification notifyAuthenticationDidSucceed];
            return;
        }

        if (self.authenticationStatus.needsCredentialsToLogin) {
            [ZMUserSessionAuthenticationNotification notifyAuthenticationDidFail:[NSError userSessionErrorWithErrorCode:ZMUserSessionNeedsCredentials
                                                                                                               userInfo:nil]];
        } else {
            [self.clientRegistrationStatus prepareForClientRegistration];
        }
    }];
}

- (void)refreshTokensIfNeeded
{
    [self.managedObjectContext performGroupedBlock:^{
        // Refresh the Voip token if needed
        NSData *actualToken = self.pushRegistrant.pushToken;
        if (actualToken != nil && ![actualToken isEqual:self.managedObjectContext.pushKitToken.deviceToken]){
            self.managedObjectContext.pushKitToken = nil;
            [self setPushKitToken:actualToken];
        }
        
        // Request the current token, the rest is taken care of
        [self.application registerForRemoteNotifications];
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
        [ZMUserSessionAuthenticationNotification notifyAuthenticationDidFail:[NSError userSessionErrorWithErrorCode:ZMUserSessionNeedsCredentials userInfo:nil]];
    }];
}

- (void)transportSessionAccessTokenDidSucceedWithToken:(NSString *)token ofType:(NSString *)type;
{
    ZMLogWithLevelAndTag(ZMLogLevelDebug, ZMTAG_NETWORK, @"Access token succeeded in %@: %@", self.class, NSStringFromSelector(_cmd));
    
    [self.syncManagedObjectContext performGroupedBlock:^{
        self.syncManagedObjectContext.accessToken = [[ZMAccessToken alloc] initWithToken:token type:type expiresInSeconds:0];
        
        [self.operationLoop accessTokenDidChangeWithToken:token ofType:type];
    }];
}

- (void)notifyThirdPartyServices;
{
    if (! self.didNotifyThirdPartyServices) {
        self.didNotifyThirdPartyServices = YES;
        [self.thirdPartyServicesDelegate userSessionIsReadyToUploadServicesData:self];
    }
}

- (AVSFlowManager *)flowManager
{
    return self.onDemandFlowManager.flowManager;
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
        [self changeNetworkStateAndNotify];
        [self notifyThirdPartyServices];
    }];
}

@end

@implementation ZMUserSession(PushChannel)

- (void)pushChannelDidChange:(NSNotification *)note
{
    BOOL newValue = [note.userInfo[ZMPushChannelIsOpenKey] boolValue];
    self.pushChannelIsOpen = newValue;
}

@end



static unsigned long CommonContactsSearchUniqueCounter = 0;

@implementation ZMUserSession (CommonContacts)

- (void)syncSearchCommonContactsWithUserID:(NSUUID *)userID forToken:(id<ZMCommonContactsSearchToken>)token searchDelegate:(id<ZMCommonContactsSearchDelegate>)searchDelegate
{
    [ZMCommonContactsSearch startSearchWithTransportSession:self.transportSession
                                                     userID:userID
                                                      token:token
                                                    syncMOC:self.syncManagedObjectContext
                                                      uiMOC:self.managedObjectContext
                                             searchDelegate:searchDelegate
                                               resultsCache:self.commonContactsCache];
}

- (id<ZMCommonContactsSearchToken>)searchCommonContactsWithUserID:(NSUUID *)userID searchDelegate:(id<ZMCommonContactsSearchDelegate>)searchDelegate
{
    id token = @(++CommonContactsSearchUniqueCounter);
    __weak id<ZMCommonContactsSearchDelegate> weakDelegate = searchDelegate;
    ZM_WEAK(self);
    [self.syncManagedObjectContext performGroupedBlock:^{
        ZM_STRONG(self);
        [self syncSearchCommonContactsWithUserID:userID forToken:token searchDelegate:weakDelegate];
    }];
    return token;
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



@implementation ZMUserSession (AlertView)

- (void)alertView:(UIAlertView * __unused)alertView clickedButtonAtIndex:(NSInteger __unused)buttonIndex
{
    [self openAppstore];
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


static BOOL ZMUserSessionUseCallKit = NO;

@implementation ZMUserSession (Calling)

- (CallingRequestStrategy *)callingStrategy
{
    return self.operationLoop.syncStrategy.callingRequestStrategy;
}

+ (BOOL)useCallKit
{
    return ZMUserSessionUseCallKit;
}

+ (void)setUseCallKit:(BOOL)useCallKit
{
    ZMUserSessionUseCallKit = useCallKit;
}

static CallingProtocolStrategy ZMUserSessionCallingProtocolStrategy = CallingProtocolStrategyNegotiate;

+ (CallingProtocolStrategy)callingProtocolStrategy
{
    return ZMUserSessionCallingProtocolStrategy;
}

+ (void)setCallingProtocolStrategy:(CallingProtocolStrategy)callingProtocolStrategy
{
    ZMUserSessionCallingProtocolStrategy = callingProtocolStrategy;
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

@implementation ZMUserSession (ClientRegistrationStatus)

- (void)didRegisterUserClient:(UserClient *)userClient
{
    self.transportSession.clientID = userClient.remoteIdentifier;
    [self.transportSession restartPushChannel];
}

@end
