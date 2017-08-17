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

@class ZMTransportSession;
@class LocalNotificationDispatcher;
@class AVSMediaManager;

@protocol ZMSyncStateDelegate;
@protocol ZMApplication;
@protocol LocalStoreProviderProtocol;

@class ZMOnDemandFlowManager;
@class ZMPersistentCookieStorage;

extern NSString * const ZMPushChannelStateChangeNotificationName;
extern NSString * const ZMPushChannelIsOpenKey;
extern NSString * const ZMPushChannelResponseStatusKey;

@interface ZMOperationLoop : NSObject

@property (nonatomic, readonly) id<ZMApplication> application;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithTransportSession:(ZMTransportSession *)transportSession
                           cookieStorage:(ZMPersistentCookieStorage *)cookieStorage
             localNotificationdispatcher:(LocalNotificationDispatcher *)dispatcher
                            mediaManager:(AVSMediaManager *)mediaManager
                     onDemandFlowManager:(ZMOnDemandFlowManager *)onDemandFlowManager
                           storeProvider:(id<LocalStoreProviderProtocol>)storeProvider
                       syncStateDelegate:(id<ZMSyncStateDelegate>)syncStateDelegate
                             application:(id<ZMApplication>)application;

- (void)tearDown;

@end


