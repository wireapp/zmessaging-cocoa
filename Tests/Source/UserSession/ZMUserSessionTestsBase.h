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


#import <CoreData/CoreData.h>
#import <WireTransport/WireTransport.h>
#import <WireDataModel/WireDataModel.h>

#import "MessagingTest.h"
#import "ZMUserSessionRegistrationNotification.h"

#import "NSError+ZMUserSessionInternal.h"
#import "ZMCredentials.h"
#import "ZMSyncStrategy.h"
#import "ZMOperationLoop.h"

#import "ZMCredentials.h"
#import "NSURL+LaunchOptions.h"

#import <WireSyncEngine/ZMAuthenticationStatus.h>

@class MockPushChannel;
@class FlowManagerMock;
@class MockSessionManager;
@class RecordingMockTransportSession;

@interface ThirdPartyServices : NSObject <ZMThirdPartyServicesDelegate>

@property (nonatomic) NSUInteger uploadCount;

@end

@protocol LocalStoreProviderProtocol;

@interface MockLocalStoreProvider : NSObject <LocalStoreProviderProtocol>

@property (nonatomic, copy) NSUUID *userIdentifier;
@property (nonatomic, copy) NSURL *applicationContainer;
@property (nonatomic, copy) NSURL *accountContainer;
@property (nonatomic, strong) ManagedObjectContextDirectory *contextDirectory;

- (instancetype)initWithSharedContainerDirectory:(NSURL *)sharedContainerDirectory userIdentifier:(NSUUID *)userIdentifier contextDirectory:(ManagedObjectContextDirectory *)contextDirectory;

@end

@interface ZMUserSessionTestsBase : MessagingTest <ZMAuthenticationStatusObserver>

@property (nonatomic) MockSessionManager *mockSessionManager;
@property (nonatomic) MockPushChannel *mockPushChannel;
@property (nonatomic) RecordingMockTransportSession *transportSession;
@property (nonatomic) ZMPersistentCookieStorage *cookieStorage;
@property (nonatomic) NSData *validCookie;
@property (nonatomic) NSURL *baseURL;
@property (nonatomic) ZMUserSession *sut;
@property (nonatomic) ZMSyncStrategy *syncStrategy;
@property (nonatomic) id mediaManager;
@property (nonatomic) FlowManagerMock *flowManagerMock;
@property (nonatomic) NSUInteger dataChangeNotificationsCount;
@property (nonatomic) ThirdPartyServices *thirdPartyServices;
@property (nonatomic) id requestAvailableNotification;
@property (nonatomic) id operationLoop;
@property (nonatomic) ZMClientRegistrationStatus * clientRegistrationStatus;
@property (nonatomic) ProxiedRequestsStatus *proxiedRequestStatus;
@property (nonatomic) id<LocalStoreProviderProtocol> storeProvider;

- (void)simulateLoggedInUser;

@end
