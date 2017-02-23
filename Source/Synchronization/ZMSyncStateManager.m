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
    if (!self.clientRegistrationStatus.clientIsReadyForRequests) {
        return ZMAppStateUnauthenticated;
    }
    if (self.syncStatus.isSyncing) {
        return ZMAppStateSyncing;
    }
    return ZMAppStateEventProcessing;
}

- (id<ClientRegistrationDelegate>)clientRegistrationDelegate;
{
    return self.clientRegistrationStatus;
}

- (id<DeliveryConfirmationDelegate>)confirmationDelegate;
{
    return self.apnsConfirmationStatus;
}

@end
