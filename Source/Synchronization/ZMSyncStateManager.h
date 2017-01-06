//
//  ZMSyncStateManager.h
//  zmessaging-cocoa
//
//  Created by Sabine Geithner on 05/01/17.
//  Copyright © 2017 Zeta Project Gmbh. All rights reserved.
//

@import WireMessageStrategy;

@class ZMCookie;
@class BackgroundAPNSConfirmationStatus;
@class ZMAuthenticationStatus;
@class UserProfileUpdateStatus;
@class ZMClientRegistrationStatus;
@class BackgroundAPNSPingBackStatus;
@class ZMAccountStatus;
@class ProxiedRequestsStatus;
@class SyncStatus;
@class ClientUpdateStatus;

@protocol ZMSyncStateDelegate;
@protocol ZMRequestCancellation;
@protocol ZMApplication;
@protocol ClientDeletionDelegate;


@interface ZMSyncStateManager : NSObject <ZMAppStateDelegate>

- (instancetype)initWithSyncManagedObjectContextMOC:(NSManagedObjectContext *)syncMOC
                                             cookie:(ZMCookie *)cookie
                                  syncStateDelegate:(id<ZMSyncStateDelegate>)syncStateDelegate
                           taskCancellationProvider:(id <ZMRequestCancellation>)taskCancellationProvider
                                        application:(id<ZMApplication>)application;
- (void)tearDown;

@property (nonatomic, readonly) BackgroundAPNSConfirmationStatus *apnsConfirmationStatus;
@property (nonatomic, readonly) ZMAuthenticationStatus *authenticationStatus;
@property (nonatomic, readonly) UserProfileUpdateStatus *userProfileUpdateStatus;
@property (nonatomic, readonly) ZMClientRegistrationStatus *clientRegistrationStatus;
@property (nonatomic, readonly) ClientUpdateStatus *clientUpdateStatus;
@property (nonatomic, readonly) BackgroundAPNSPingBackStatus *pingBackStatus;
@property (nonatomic, readonly) ZMAccountStatus *accountStatus;
@property (nonatomic, readonly) ProxiedRequestsStatus *proxiedRequestStatus;
@property (nonatomic, readonly) SyncStatus *syncStatus;

@property (nonatomic, weak, readonly) id<ZMRequestCancellation> taskCancellationDelegate;
@property (nonatomic, readonly) id<ClientDeletionDelegate> clientDeletionDelegate;
@property (nonatomic, readonly) id<DeliveryConfirmationDelegate> confirmationDelegate;

@end
