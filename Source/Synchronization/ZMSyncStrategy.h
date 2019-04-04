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
@class EventDecoder;

@protocol ZMTransportData;
@protocol ZMSyncStateDelegate;
@protocol ZMBackgroundable;
@protocol ApplicationStateOwner;
@protocol FlowManagerType;
@protocol ZMApplication;
@protocol LocalStoreProviderProtocol;
@protocol EventProcessingTrackerProtocol;

@interface ZMSyncStrategy : NSObject <ZMObjectStrategyDirectory, TearDownCapable>

- (instancetype _Nonnull )initWithStoreProvider:(id<LocalStoreProviderProtocol> _Nonnull)storeProvider
                                  cookieStorage:(ZMPersistentCookieStorage * _Nullable)cookieStorage
                                    flowManager:(id<FlowManagerType> _Nonnull)flowManager
                   localNotificationsDispatcher:(LocalNotificationDispatcher * _Nonnull)localNotificationsDispatcher
                        notificationsDispatcher:(NotificationDispatcher * _Nonnull)notificationsDispatcher
                     applicationStatusDirectory:(ApplicationStatusDirectory * _Nonnull)applicationStatusDirectory
                                    application:(id<ZMApplication> _Nonnull)application;

- (void)didInterruptUpdateEventsStream;
- (void)didEstablishUpdateEventsStream;
- (void)didFinishSync;

- (ZMTransportRequest *_Nullable)nextRequest;

- (void)tearDown;

@property (nonatomic, readonly, nonnull) NSManagedObjectContext *syncMOC;
@property (nonatomic, weak, readonly, nullable) ApplicationStatusDirectory *applicationStatusDirectory;
@property (nonatomic, readonly, nonnull) CallingRequestStrategy *callingRequestStrategy;
@property (nonatomic, readonly, nonnull) EventDecoder *eventDecoder;
@property (nonatomic, readonly, nonnull) ZMUpdateEventsBuffer *eventsBuffer;
@property (nonatomic, readonly, nonnull) NSArray<id<ZMEventConsumer>> *eventConsumers;
@property (nonatomic, weak, readonly, nullable) LocalNotificationDispatcher *localNotificationDispatcher;
@property (nonatomic, readonly) BOOL isReadyToProcessEvents;
@property (nonatomic, nullable) id<EventProcessingTrackerProtocol> eventProcessingTracker;

@end

