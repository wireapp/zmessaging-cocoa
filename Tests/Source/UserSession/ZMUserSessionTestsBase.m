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


#import <Foundation/Foundation.h>
#include "ZMUserSessionTestsBase.h"
#import "WireSyncEngine_iOS_Tests-Swift.h"
@import WireSyncEngine;


@implementation MockLocalStoreProvider

- (instancetype)initWithSharedContainerDirectory:(NSURL *)sharedContainerDirectory userIdentifier:(NSUUID *)userIdentifier contextDirectory:(ManagedObjectContextDirectory *)contextDirectory
{
    self = [super init];
    if (self) {
        self.userIdentifier = userIdentifier;
        self.accountContainer = [[sharedContainerDirectory URLByAppendingPathComponent:@"AccountData"] URLByAppendingPathComponent:userIdentifier.UUIDString];
        self.applicationContainer = sharedContainerDirectory;
        self.contextDirectory = contextDirectory;
    }
    return self;
}

@end

@implementation ThirdPartyServices

- (void)userSessionIsReadyToUploadServicesData:(ZMUserSession *)userSession;
{
    NOT_USED(userSession);
    ++self.uploadCount;
}

@end


@interface ZMUserSessionTestsBase ()

@property (nonatomic) OperationStatus *operationStatus;

@end



@implementation ZMUserSessionTestsBase

- (void)setUp
{
    [super setUp];
    
    WireCallCenterV3Factory.wireCallCenterClass = WireCallCenterV3Mock.self;
    
    self.thirdPartyServices = [[ThirdPartyServices alloc] init];
    self.dataChangeNotificationsCount = 0;
    self.baseURL = [NSURL URLWithString:@"http://bar.example.com"];
    self.cookieStorage = [ZMPersistentCookieStorage storageForServerName:@"usersessiontest.example.com" userIdentifier:NSUUID.createUUID];
    self.mockPushChannel = [[MockPushChannel alloc] init];
    self.transportSession = [[RecordingMockTransportSession alloc] initWithCookieStorage:self.cookieStorage pushChannel:self.mockPushChannel];
    self.mockSessionManager = [[MockSessionManager alloc] init];
    self.mediaManager = [[MockMediaManager alloc] init];
    self.flowManagerMock = [[FlowManagerMock alloc] init];
    self.requestAvailableNotification = [OCMockObject mockForClass:ZMRequestAvailableNotification.class];
    
    self.clientRegistrationStatus = [[ZMClientRegistrationStatus alloc] initWithManagedObjectContext:self.syncMOC cookieStorage:self.cookieStorage registrationStatusDelegate:nil];
    self.proxiedRequestStatus = [[ProxiedRequestsStatus alloc] initWithRequestCancellation:self.transportSession];
    self.operationStatus = [[OperationStatus alloc] init];
    
    id applicationStatusDirectory = [OCMockObject niceMockForClass:[ApplicationStatusDirectory class]];
    [(ApplicationStatusDirectory *)[[(id)applicationStatusDirectory stub] andReturn:self.clientRegistrationStatus] clientRegistrationStatus];
    [(ApplicationStatusDirectory *)[[(id)applicationStatusDirectory stub] andReturn:self.proxiedRequestStatus] proxiedRequestStatus];
    [(ApplicationStatusDirectory *)[[(id)applicationStatusDirectory stub] andReturn:self.operationStatus] operationStatus];
    
    self.syncStrategy = [OCMockObject mockForClass:[ZMSyncStrategy class]];
    [(ZMSyncStrategy *)[[(id)self.syncStrategy stub] andReturn:applicationStatusDirectory] applicationStatusDirectory];
    [[(id)self.syncStrategy stub] didFinishSync];
    [self verifyMockLater:self.syncStrategy];

    self.operationLoop = [OCMockObject mockForClass:ZMOperationLoop.class];
    [[self.operationLoop stub] tearDown];
    [[[self.operationLoop stub] andReturn:self.syncStrategy] syncStrategy];
    
    self.storeProvider = [[MockLocalStoreProvider alloc] initWithSharedContainerDirectory:self.sharedContainerURL userIdentifier:self.userIdentifier contextDirectory:self.contextDirectory];
    
    self.sut = [[ZMUserSession alloc] initWithTransportSession:self.transportSession
                                                  mediaManager:self.mediaManager
                                                   flowManager:self.flowManagerMock
                                                     analytics:nil
                                                 operationLoop:self.operationLoop
                                                   application:self.application
                                                    appVersion:@"00000"
                                                 storeProvider:self.storeProvider
                                           showContentDelegate:nil];
        
    self.sut.thirdPartyServicesDelegate = self.thirdPartyServices;
    self.sut.sessionManager = (id<SessionManagerType>)self.mockSessionManager;
    
    WaitForAllGroupsToBeEmpty(0.5);
    
    self.validCookie = [@"valid-cookie" dataUsingEncoding:NSUTF8StringEncoding];
    [self verifyMockLater:self.syncStrategy];
    [self verifyMockLater:self.operationLoop];
}

- (void)tearDown
{
    [self.clientRegistrationStatus tearDown];
    self.clientRegistrationStatus = nil;
    self.proxiedRequestStatus = nil;
    self.operationStatus = nil;
    
    [self tearDownUserInfoObjectsOfMOC:self.syncMOC];
    [self.syncMOC.userInfo removeAllObjects];
    
    [self tearDownUserInfoObjectsOfMOC:self.uiMOC];
    [self.uiMOC.userInfo removeAllObjects];
    
    [super cleanUpAndVerify];
    NSURL *cachesURL = [[NSFileManager defaultManager] cachesURLForAccountWith:self.userIdentifier in:self.sut.sharedContainerURL];
    NSArray *items = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:cachesURL includingPropertiesForKeys:nil options:0 error:nil];
    for (NSURL *item in items) {
        [[NSFileManager defaultManager] removeItemAtURL:item error:nil];
    }
    
    self.storeProvider = nil;

    self.baseURL = nil;
    self.cookieStorage = nil;
    self.validCookie = nil;
    self.thirdPartyServices = nil;
    self.sut.thirdPartyServicesDelegate = nil;
    self.mockSessionManager = nil;
    self.transportSession = nil;
    
    [self.operationLoop stopMocking];
    self.operationLoop = nil;
    
    [self.requestAvailableNotification stopMocking];
    self.requestAvailableNotification = nil;
    
    self.mediaManager = nil;
    
    self.flowManagerMock = nil;
    
    [(id)self.syncStrategy stopMocking];
    self.syncStrategy = nil;
    
    id tempSut = self.sut;
    self.sut = nil;
    [tempSut tearDown];
    
    [super tearDown];
}

- (void)didChangeAuthenticationData
{
    ++self.dataChangeNotificationsCount;
}

- (void)simulateLoggedInUser
{
    [self.syncMOC setPersistentStoreMetadata:@"foooooo" forKey:ZMPersistedClientIdKey];
    [ZMUser selfUserInContext:self.syncMOC].remoteIdentifier = [NSUUID createUUID];
    [self.cookieStorage setAuthenticationCookieData:self.validCookie];
}

@end
