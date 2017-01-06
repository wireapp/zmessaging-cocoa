//
//  ZMSyncStateManager.m
//  zmessaging-cocoa
//
//  Created by Sabine Geithner on 05/01/17.
//  Copyright © 2017 Zeta Project Gmbh. All rights reserved.
//

#import "ZMSyncStateManager.h"
#import "ZMClientRegistrationStatus.h"
#import <zmessaging/zmessaging-Swift.h>

@interface ZMSyncStateManager()

@property (nonatomic) BackgroundAPNSConfirmationStatus *apnsConfirmationStatus;
@property (nonatomic) ZMAuthenticationStatus *authenticationStatus;
@property (nonatomic) UserProfileUpdateStatus *userProfileUpdateStatus;
@property (nonatomic) ZMClientRegistrationStatus *clientRegistrationStatus;
@property (nonatomic) ClientUpdateStatus *clientUpdateStatus;
@property (nonatomic) BackgroundAPNSPingBackStatus *pingBackStatus;
@property (nonatomic) ZMAccountStatus *accountStatus;
@property (nonatomic) ProxiedRequestsStatus *proxiedRequestStatus;
@property (nonatomic) SyncStatus *syncStatus;
@property (nonatomic, weak) id<ZMRequestCancellation> taskCancellationDelegate;

@end


@implementation ZMSyncStateManager

- (instancetype)initWithSyncManagedObjectContextMOC:(NSManagedObjectContext *)syncMOC
                                             cookie:(ZMCookie *)cookie
                                  syncStateDelegate:(id<ZMSyncStateDelegate>)syncStateDelegate
                           taskCancellationProvider:(id <ZMRequestCancellation>)taskCancellationProvider
                                        application:(id<ZMApplication>)application;
{
    self = [super init];
    if (self  != nil) {
        self.taskCancellationDelegate = taskCancellationProvider;
        
        self.apnsConfirmationStatus = [[BackgroundAPNSConfirmationStatus alloc] initWithApplication:application
                                                                               managedObjectContext:syncMOC
                                                                          backgroundActivityFactory:[BackgroundActivityFactory sharedInstance]];
        self.syncStatus = [[SyncStatus alloc] initWithManagedObjectContext:syncMOC syncStateDelegate:syncStateDelegate];
        
        self.authenticationStatus = [[ZMAuthenticationStatus alloc] initWithManagedObjectContext:syncMOC cookie:cookie];
        self.userProfileUpdateStatus = [[UserProfileUpdateStatus alloc] initWithManagedObjectContext:syncMOC];
        self.clientUpdateStatus = [[ClientUpdateStatus alloc] initWithSyncManagedObjectContext:syncMOC];
        
        self.clientRegistrationStatus = [[ZMClientRegistrationStatus alloc] initWithManagedObjectContext:syncMOC
                                                                                 loginCredentialProvider:self.authenticationStatus
                                                                                updateCredentialProvider:self.userProfileUpdateStatus
                                                                                                  cookie:cookie
                                                                              registrationStatusDelegate:syncStateDelegate];
        
        self.accountStatus = [[ZMAccountStatus alloc] initWithManagedObjectContext:syncMOC cookieStorage:cookie];
        
        self.pingBackStatus = [[BackgroundAPNSPingBackStatus alloc] initWithSyncManagedObjectContext:syncMOC
                                                                              authenticationProvider:self.authenticationStatus];
        self.proxiedRequestStatus = [[ProxiedRequestsStatus alloc] initWithRequestCancellation:taskCancellationProvider];
    }
    return self;
}

- (void)tearDown
{
    [self.apnsConfirmationStatus tearDown];
    [self.clientUpdateStatus tearDown];
    self.clientUpdateStatus = nil;
    [self.clientRegistrationStatus tearDown];
    self.clientRegistrationStatus = nil;
    self.authenticationStatus = nil;
    self.userProfileUpdateStatus = nil;
    self.proxiedRequestStatus = nil;
}

- (ZMAppState)appState
{
    return ZMAppStateEventProcessing;
}

- (id<ClientDeletionDelegate>)clientDeletionDelegate;
{
    return self.clientRegistrationStatus;
}

- (id<DeliveryConfirmationDelegate>)confirmationDelegate;
{
    return self.apnsConfirmationStatus;
}

@end
