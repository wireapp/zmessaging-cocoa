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
