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
@protocol FlowManagerType;

@class ZMPersistentCookieStorage;
@class ApplicationStatusDirectory;
@class ZMSyncStrategy;

extern NSString * const ZMPushChannelIsOpenKey;

@interface ZMOperationLoop : NSObject <TearDownCapable>

@property (nonatomic, readonly) id<ZMApplication> application;
@property (nonatomic, readonly) ZMTransportSession *transportSession;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithTransportSession:(ZMTransportSession *)transportSession
                            syncStrategy:(ZMSyncStrategy *)syncStrategy
              applicationStatusDirectory:(ApplicationStatusDirectory *)applicationStatusDirectory
                                   uiMOC:(NSManagedObjectContext *)uiMOC
                                 syncMOC:(NSManagedObjectContext *)syncMOC;

- (void)tearDown;

@end


