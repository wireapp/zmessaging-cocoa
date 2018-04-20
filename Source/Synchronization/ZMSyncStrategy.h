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
@class ApplicationStatusDirectory;
@class AVSMediaManager;
@class CallingRequestStrategy;

@protocol ZMTransportData;
@protocol ZMSyncStateDelegate;
@protocol ZMBackgroundable;
@protocol ApplicationStateOwner;
@protocol FlowManagerType;
@protocol ZMApplication;
@protocol LocalStoreProviderProtocol;

@interface ZMSyncStrategy : NSObject <ZMObjectStrategyDirectory, TearDownCapable>

- (instancetype)initWithStoreProvider:(id<LocalStoreProviderProtocol>)storeProvider
                        cookieStorage:(ZMPersistentCookieStorage *)cookieStorage
                         mediaManager:(AVSMediaManager *)mediaManager
                          flowManager:(id<FlowManagerType>)flowManager
         localNotificationsDispatcher:(LocalNotificationDispatcher *)localNotificationsDispatcher
           applicationStatusDirectory:(ApplicationStatusDirectory *)applicationStatusDirectory
                          application:(id<ZMApplication>)application;

- (void)didInterruptUpdateEventsStream;
- (void)didEstablishUpdateEventsStream;
- (void)didFinishSync;

- (ZMTransportRequest *)nextRequest;

- (void)tearDown;

@property (nonatomic, readonly) NSManagedObjectContext *syncMOC;
@property (nonatomic, weak, readonly) ApplicationStatusDirectory *applicationStatusDirectory;
@property (nonatomic, readonly) CallingRequestStrategy *callingRequestStrategy;

@end

