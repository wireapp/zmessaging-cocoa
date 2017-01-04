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
    ZM_WEAK(self);
    [[self.transportSession stub] setAccessTokenRenewalFailureHandler:[OCMArg checkWithBlock:^BOOL(ZMCompletionHandlerBlock obj) {
        ZM_STRONG(self);
        self.authFailHandler = obj;
        return YES;
    }]];
    [[self.transportSession stub] setAccessTokenRenewalSuccessHandler:[OCMArg checkWithBlock:^BOOL(ZMAccessTokenHandlerBlock obj) {
        ZM_STRONG(self);
        self.tokenSuccessHandler = obj;
        return YES;
    }]];
    [[self.transportSession stub] setNetworkStateDelegate:OCMOCK_ANY];
    self.mediaManager = [OCMockObject niceMockForClass:NSObject.class];
    self.requestAvailableNotification = [OCMockObject mockForClass:ZMRequestAvailableNotification.class];
    self.operationLoop = [OCMockObject mockForClass:ZMOperationLoop.class];
    [[self.operationLoop stub] tearDown];
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
    
    self.syncStrategy = [OCMockObject mockForClass:[ZMSyncStrategy class]];
    
    self.validCookie = [@"valid-cookie" dataUsingEncoding:NSUTF8StringEncoding];
    [self verifyMockLater:self.transportSession];
    [self verifyMockLater:self.syncStrategy];
    [self verifyMockLater:self.authenticationObserver];
    [self verifyMockLater:self.registrationObserver];
    [self verifyMockLater:self.operationLoop];
    
    [self.sut.authenticationStatus addAuthenticationCenterObserver:self];
    
}

- (void)tearDown
{
    [self tearDownUserInfoObjectsOfMOC:self.syncMOC];
    [self.syncMOC.userInfo removeAllObjects];
    
    [self tearDownUserInfoObjectsOfMOC:self.uiMOC];
    [self.uiMOC.userInfo removeAllObjects];
    
    [super cleanUpAndVerify];
    [self.sut.authenticationStatus removeAuthenticationCenterObserver:self];
    self.authFailHandler = nil;
    self.tokenSuccessHandler = nil;
    self.baseURL = nil;
    self.cookieStorage = nil;
    self.validCookie = nil;
    self.thirdPartyServices = nil;
    self.sut.thirdPartyServicesDelegate = nil;
    self.sut.requestToOpenViewDelegate = nil;

    [self.transportSession stopMocking];
    self.transportSession = nil;
    
    [self.operationLoop stopMocking];
    self.operationLoop = nil;
    
    [self.requestAvailableNotification stopMocking];
    self.requestAvailableNotification = nil;
    
    [self.mediaManager stopMocking];
    self.mediaManager = nil;
    
    [(id)self.syncStrategy stopMocking];
    self.syncStrategy = nil;
    
    [self.apnsEnvironment stopMocking];
    self.apnsEnvironment = nil;
    
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
