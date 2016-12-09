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
#import "zmessaging_iOS_Tests-Swift.h"

@implementation ThirdPartyServices

- (void)userSessionIsReadyToUploadServicesData:(ZMUserSession *)userSession;
{
    NOT_USED(userSession);
    ++self.uploadCount;
}

@end


@interface ZMUserSessionTestsBase ()

@property (nonatomic) id<ZMAuthenticationObserverToken> authenticationObserverToken;
@property (nonatomic) id<ZMRegistrationObserverToken> registrationObserverToken;

@end



@implementation ZMUserSessionTestsBase

- (void)setUp
{
    [super setUp];
    
    self.thirdPartyServices = [[ThirdPartyServices alloc] init];
    self.dataChangeNotificationsCount = 0;
    self.baseURL = [NSURL URLWithString:@"http://bar.example.com"];
    self.transportSession = [OCMockObject niceMockForClass:[ZMTransportSession class]];
    self.cookieStorage = [ZMPersistentCookieStorage storageForServerName:@"usersessiontest.example.com"];
    [[[self.transportSession stub] andReturn:self.cookieStorage] cookieStorage];
    [[self.transportSession stub] setAccessTokenRenewalFailureHandler:[OCMArg checkWithBlock:^BOOL(ZMCompletionHandlerBlock obj) {
        self.authFailHandler = obj;
        return YES;
    }]];
    
    [[self.transportSession stub] setAccessTokenRenewalSuccessHandler:[OCMArg checkWithBlock:^BOOL(ZMAccessTokenHandlerBlock obj) {
        self.tokenSuccessHandler = obj;
        return YES;
    }]];
    [[self.transportSession stub] setNetworkStateDelegate:OCMOCK_ANY];
    self.mediaManager = [OCMockObject niceMockForClass:NSObject.class];
    self.requestAvailableNotification = [OCMockObject mockForClass:ZMRequestAvailableNotification.class];
    
    ZMCookie *cookie = [[ZMCookie alloc] initWithManagedObjectContext:self.syncMOC cookieStorage:self.cookieStorage];
    self.authenticationStatus = [[ZMAuthenticationStatus alloc] initWithManagedObjectContext: self.syncMOC cookie:cookie];
    self.clientRegistrationStatus = [[ZMClientRegistrationStatus alloc] initWithManagedObjectContext:self.syncMOC loginCredentialProvider:self.authenticationStatus updateCredentialProvider:nil cookie:cookie registrationStatusDelegate:nil];
    self.proxiedRequestStatus = [[ProxiedRequestsStatus alloc] initWithRequestCancellation:self.transportSession];
    
    self.syncStrategy = [OCMockObject mockForClass:[ZMSyncStrategy class]];
    [(ZMSyncStrategy *)[[(id)self.syncStrategy stub] andReturn:self.authenticationStatus] authenticationStatus];
    [(ZMSyncStrategy *)[[(id)self.syncStrategy stub] andReturn:self.clientRegistrationStatus] clientRegistrationStatus];
    [(ZMSyncStrategy *)[[(id)self.syncStrategy stub] andReturn:self.proxiedRequestStatus] proxiedRequestStatus];
    [self verifyMockLater:self.syncStrategy];

    self.operationLoop = [OCMockObject mockForClass:ZMOperationLoop.class];
    [[[self.operationLoop stub] andReturn:self.syncStrategy] syncStrategy];
    [[self.operationLoop stub] tearDown];
    [self verifyMockLater:self.operationLoop];

    self.apnsEnvironment = [OCMockObject niceMockForClass:[ZMAPNSEnvironment class]];
    [[[self.apnsEnvironment stub] andReturn:@"com.wire.ent"] appIdentifier];
    [[[self.apnsEnvironment stub] andReturn:@"APNS"] transportTypeForTokenType:ZMAPNSTypeNormal];
    [[[self.apnsEnvironment stub] andReturn:@"APNS_VOIP"] transportTypeForTokenType:ZMAPNSTypeVoIP];
    
    self.sut = [[ZMUserSession alloc] initWithTransportSession:self.transportSession
                                          userInterfaceContext:self.uiMOC
                                      syncManagedObjectContext:self.syncMOC
                                                  mediaManager:self.mediaManager
                                               apnsEnvironment:self.apnsEnvironment
                                                 operationLoop:self.operationLoop
                                                   application:self.application
                                                    appVersion:@"00000"
                                            appGroupIdentifier:self.groupIdentifier];
    self.sut.thirdPartyServicesDelegate = self.thirdPartyServices;
    
    WaitForAllGroupsToBeEmpty(0.5);
    
    self.authenticationObserver = [OCMockObject mockForProtocol:@protocol(ZMAuthenticationObserver)];
    self.authenticationObserverToken = [self.sut addAuthenticationObserver:self.authenticationObserver];
    
    self.registrationObserver = [OCMockObject mockForProtocol:@protocol(ZMRegistrationObserver)];
    self.registrationObserverToken = [self.sut addRegistrationObserver:self.registrationObserver];
    
    
    self.validCookie = [@"valid-cookie" dataUsingEncoding:NSUTF8StringEncoding];
    [self verifyMockLater:self.transportSession];
    [self verifyMockLater:self.authenticationObserver];
    [self verifyMockLater:self.registrationObserver];
    
    [self.sut.authenticationStatus addAuthenticationCenterObserver:self];
}

- (void)tearDown
{
    [super cleanUpAndVerify];
    self.cookieStorage = nil;
    
    [self.sut.authenticationStatus removeAuthenticationCenterObserver:self];
    self.authenticationStatus = nil;
    [self.clientRegistrationStatus tearDown];
    self.clientRegistrationStatus = nil;
    
    self.baseURL = nil;
    [self.transportSession stopMocking];
    self.transportSession = nil;
    [(id)self.syncStrategy stopMocking];
    self.syncStrategy = nil;
    [self.operationLoop stopMocking];
    self.operationLoop = nil;
    [self.requestAvailableNotification stopMocking];
    self.requestAvailableNotification = nil;
    self.sut.requestToOpenViewDelegate = nil;
    
    [self.sut removeAuthenticationObserverForToken:self.authenticationObserverToken];
    self.authenticationObserverToken = nil;
    self.authenticationObserver = nil;
    
    [self.sut removeRegistrationObserverForToken:self.registrationObserverToken];
    self.registrationObserverToken = nil;
    self.registrationObserver = nil;
    
    id tempSut = self.sut;
    self.sut = nil;
    [tempSut tearDown];
    
    [super tearDown];
}

- (void)didChangeAuthenticationData
{
    ++self.dataChangeNotificationsCount;
}

@end
