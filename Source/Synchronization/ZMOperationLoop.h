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
@class ZMSyncStrategy;
@class ZMAuthenticationStatus;
@class ZMClientRegistrationStatus;
@class NSManagedObjectContext;
@class LocalNotificationDispatcher;

@protocol ZMSyncStateDelegate;
@protocol ZMTransportData;
@protocol AVSMediaManager;
@protocol ApplicationStateOwner;

@class ZMOnDemandFlowManager;
@class ProxiedRequestsStatus;
@class ClientUpdateStatus;
@class UserProfileUpdateStatus;

@class BackgroundAPNSPingBackStatus;
@class ZMAccountStatus;
@class TopConversationsDirectory;
@protocol ZMApplication;

extern NSString * const ZMPushChannelStateChangeNotificationName;
extern NSString * const ZMPushChannelIsOpenKey;
extern NSString * const ZMPushChannelResponseStatusKey;

@interface ZMOperationLoop : NSObject

@property (nonatomic, readonly) id<ZMApplication> application;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithTransportSession:(ZMTransportSession *)transportSession
                    authenticationStatus:(ZMAuthenticationStatus *)authenticationStatus
                 userProfileUpdateStatus:(UserProfileUpdateStatus *)userProfileUpdateStatus
                clientRegistrationStatus:(ZMClientRegistrationStatus *)clientRegistrationStatus
                      clientUpdateStatus:(ClientUpdateStatus *)clientUpdateStatus
                    proxiedRequestStatus:(ProxiedRequestsStatus *)proxiedRequestStatus
                           accountStatus:(ZMAccountStatus *)accountStatus
            backgroundAPNSPingBackStatus:(BackgroundAPNSPingBackStatus *)backgroundAPNSPingBackStatus
             localNotificationdispatcher:(LocalNotificationDispatcher *)dispatcher
                            mediaManager:(id<AVSMediaManager>)mediaManager
                     onDemandFlowManager:(ZMOnDemandFlowManager *)onDemandFlowManager
                                   uiMOC:(NSManagedObjectContext *)uiMOC
                                 syncMOC:(NSManagedObjectContext *)syncMOC
                       syncStateDelegate:(id<ZMSyncStateDelegate>)syncStateDelegate
                      appGroupIdentifier:(NSString *)appGroupIdentifier
                             application:(id<ZMApplication>)application;

- (void)tearDown;
- (void)accessTokenDidChangeWithToken:(NSString *)token ofType:(NSString *)type;

@end


