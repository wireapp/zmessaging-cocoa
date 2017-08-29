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
@import WireRequestStrategy;

#import "ZMObjectStrategyDirectory.h"
#import "ZMUpdateEventsBuffer.h"
#import <WireSyncEngine/WireSyncEngine-Swift.h>

@class ZMTransportRequest;
@class ZMPushChannelConnection;
@class ZMAuthenticationStatus;
@class ZMTransportSession;
@class LocalNotificationDispatcher;
@class UserProfileUpdateStatus;
@class ProxiedRequestsStatus;
@class ZMClientRegistrationStatus;
@class ClientUpdateStatus;
@class BackgroundAPNSPingBackStatus;
@class ZMAccountStatus;
@class ZMApplicationStatusDirectory;

@protocol ZMTransportData;
@protocol ZMSyncStateDelegate;
@protocol ZMBackgroundable;
@protocol ApplicationStateOwner;
@protocol FlowManagerType;


@interface ZMSyncStrategy : NSObject <ZMObjectStrategyDirectory>

- (instancetype)initWithStoreProvider:(id<LocalStoreProviderProtocol>)storeProvider
                        cookieStorage:(ZMPersistentCookieStorage *)cookieStorage
                         mediaManager:(AVSMediaManager *)mediaManager
                          flowManager:(id<FlowManagerType>)flowManager
                    syncStateDelegate:(id<ZMSyncStateDelegate>)syncStateDelegate
         localNotificationsDispatcher:(LocalNotificationDispatcher *)localNotificationsDispatcher
             taskCancellationProvider:(id <ZMRequestCancellation>)taskCancellationProvider
                          application:(id<ZMApplication>)application;

- (void)didInterruptUpdateEventsStream;
- (void)didEstablishUpdateEventsStream;

- (ZMTransportRequest *)nextRequest;

- (void)tearDown;

@property (nonatomic, readonly) NSManagedObjectContext *syncMOC;
@property (nonatomic, readonly) ZMApplicationStatusDirectory *applicationStatusDirectory;
@property (nonatomic, readonly) CallingRequestStrategy *callingRequestStrategy;

@end


@interface ZMSyncStrategy (SyncStateDelegate) <ZMSyncStateDelegate>
@end
