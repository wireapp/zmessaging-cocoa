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


@import ZMTransport;

#import "StateBaseTest.h"
#import "ZMObjectStrategyDirectory.h"

#import "ZMUserTranscoder.h"
#import "ZMUserImageTranscoder.h"
#import "ZMConversationTranscoder.h"
#import "ZMSelfTranscoder.h"
#import "ZMConnectionTranscoder.h"
#import "ZMLoginCodeRequestTranscoder.h"
#import "ZMPhoneNumberVerificationTranscoder.h"

#import "ZMStateMachineDelegate.h"

#import "ZMEventProcessingState.h"
#import "ZMUnauthenticatedState.h"
#import "ZMUnauthenticatedBackgroundState.h"
#import "ZMSlowSyncPhaseOneState.h"
#import "ZMSlowSyncPhaseTwoState.h"
#import "ZMUpdateEventsCatchUpPhaseOneState.h"
#import "ZMUpdateEventsCatchUpPhaseTwoState.h"
#import "ZMBackgroundState.h"
#import "ZMPreBackgroundState.h"
#import "ZMCookie.h"
#import "zmessaging_iOS_Tests-Swift.h"

@implementation StateBaseTest

- (void)setUp
{
    [super setUp];
    ZMPersistentCookieStorage *cookieStorage = [ZMPersistentCookieStorage storageForServerName:@"test-test"];
    ZMCookie *cookie = [[ZMCookie alloc] initWithManagedObjectContext:self.uiMOC cookieStorage:cookieStorage];
    
    _authenticationStatus = [[ZMAuthenticationStatus alloc] initWithManagedObjectContext:self.uiMOC cookie:cookie];
    _clientRegistrationStatus = [[ZMClientRegistrationStatus alloc] initWithManagedObjectContext:self.uiMOC loginCredentialProvider:self.authenticationStatus updateCredentialProvider:nil cookie:cookie registrationStatusDelegate:nil];
    _clientUpdateStatus = [[ClientUpdateStatus alloc] initWithSyncManagedObjectContext:self.uiMOC];
        
    _stateMachine = [OCMockObject mockForProtocol:@protocol(ZMStateMachineDelegate)];

    id eventProcessingState = [OCMockObject mockForClass:ZMEventProcessingState.class];
    [self verifyMockLater:eventProcessingState];
    id unauthenticatedState = [OCMockObject mockForClass:ZMUnauthenticatedState.class];
    [self verifyMockLater:unauthenticatedState];
    id unauthenticatedBackgroundState = [OCMockObject mockForClass:ZMUnauthenticatedBackgroundState.class];
    [self verifyMockLater:unauthenticatedBackgroundState];
    id slowSyncPhaseOneState = [OCMockObject mockForClass:ZMSlowSyncPhaseOneState.class];
    [self verifyMockLater:slowSyncPhaseOneState];
    id slowSyncPhaseTwoState = [OCMockObject mockForClass:ZMSlowSyncPhaseTwoState.class];
    [self verifyMockLater:slowSyncPhaseTwoState];
    id updateEventsCatchUpPhaseOneState = [OCMockObject mockForClass:ZMUpdateEventsCatchUpPhaseOneState.class];
    [self verifyMockLater:updateEventsCatchUpPhaseOneState];
    id updateEventsCatchUpPhaseTwoState = [OCMockObject mockForClass:ZMUpdateEventsCatchUpPhaseTwoState.class];
    [self verifyMockLater:updateEventsCatchUpPhaseTwoState];
    id backgroundState = [OCMockObject mockForClass:ZMBackgroundState.class];
    [self verifyMockLater:backgroundState];
    id preBackgroundState = [OCMockObject mockForClass:ZMPreBackgroundState.class];
    [self verifyMockLater:preBackgroundState];
    
    
    [[[(id) self.stateMachine stub] andReturn:eventProcessingState] eventProcessingState];
    [[[(id) self.stateMachine stub] andReturn:unauthenticatedState] unauthenticatedState];
    [[[(id) self.stateMachine stub] andReturn:unauthenticatedBackgroundState] unauthenticatedBackgroundState];
    [[[(id) self.stateMachine stub] andReturn:slowSyncPhaseOneState] slowSyncPhaseOneState];
    [[[(id) self.stateMachine stub] andReturn:slowSyncPhaseTwoState] slowSyncPhaseTwoState];
    [[[(id) self.stateMachine stub] andReturn:updateEventsCatchUpPhaseOneState] updateEventsCatchUpPhaseOneState];
    [[[(id) self.stateMachine stub] andReturn:updateEventsCatchUpPhaseTwoState] updateEventsCatchUpPhaseTwoState];
    [[[(id) self.stateMachine stub] andReturn:backgroundState] backgroundState];
    [[[(id) self.stateMachine stub] andReturn:preBackgroundState] preBackgroundState];
    
    _objectDirectory = [self createMockObjectStrategyDirectoryInMoc:self.uiMOC];
    
    [self verifyMockLater:self.stateMachine];
}

- (void)tearDown
{
    [super tearDown];
    _objectDirectory = nil;
    _stateMachine = nil;
    _authenticationStatus = nil;
    [self.clientRegistrationStatus tearDown];
    [self.clientUpdateStatus tearDown];
    _clientRegistrationStatus = nil;
    _clientUpdateStatus = nil;
}

- (void)stubRequestsOnHighPriorityObjectSync
{
    [[[(id)[self.objectDirectory flowTranscoder] stub] andReturn:@[]] requestGenerators];
    [[[(id)[self.objectDirectory callStateTranscoder] stub] andReturn:@[]] requestGenerators];
}

- (void)checkThatItCallsRequestGeneratorsOnObjectsOfClass:(NSArray *)objectsToTest creationOfStateBlock:(ZMSyncState *(^)(id<ZMObjectStrategyDirectory> directory))creationBlock;
{
    /*
     NOTE: a failure here might mean that you either forgot to add a new sync to
     self.syncObjectsUsedByThisState, or that the order of that array doesn't match
     the order used by the state to ask for nextRequest
     */
    
    NSArray *classesOfObjectsToTest = [objectsToTest mapWithBlock:^id(id obj) {
        return [obj class];
    }];
    
    ZMTransportRequest *dummyRequest = [ZMTransportRequest requestGetFromPath:@"foo"];
    id<ZMRequestGenerator> generator = [OCMockObject niceMockForProtocol:@protocol(ZMRequestGenerator)];
    [[[(id) generator stub] andReturn:dummyRequest] nextRequest];
    
    for(Class classOfSyncExpectedToReturnARequest in classesOfObjectsToTest) {
        
        // For each sync object, I want to test that it calls nextRequest until that object,
        // and stops requesting after that object. I need to tear down everything for each
        // test as there is no way apparently to revert the "reject" once it's set
        
        id<ZMObjectStrategyDirectory> directory = [self createMockObjectStrategyDirectoryInMoc:self.uiMOC];
        ZMSyncState *sut = creationBlock(directory);
        XCTAssertNotNil(sut);
        
        NSArray *objectsInDirectory = [classesOfObjectsToTest mapWithBlock:^id(id syncClass) {
            return [[directory allTranscoders] firstObjectMatchingWithBlock:^BOOL(id syncObject) {
                return [syncObject class] == syncClass;
            }];
        }];
        
        // expect
        BOOL shouldStartRejectingFromThisPointInArray = NO;
        for(id sync in objectsInDirectory) {
            
            
            if([sync class] == classOfSyncExpectedToReturnARequest)
            {
                [[[sync expect] andReturn:@[generator]] requestGenerators];
                shouldStartRejectingFromThisPointInArray = YES;
            }
            else {
                if(shouldStartRejectingFromThisPointInArray) {
                    [[sync reject] requestGenerators];
                }
                else {
                    [[[sync expect] andReturn:@[]] requestGenerators];
                }
            }
        }
        
        // when
        ZMTransportRequest *request = [sut nextRequest];
        XCTAssertEqual(request, dummyRequest);
        
        // then
        for(id sync in objectsInDirectory) {
            [sync verify];
        }
    }
}

- (id<ZMRequestGenerator>)generatorReturningNiceMockRequest;
{
    ZMTransportRequest *request = [OCMockObject niceMockForClass:ZMTransportRequest.class];
    return [self generatorReturningRequest:request];
}

- (id<ZMRequestGenerator>)generatorReturningRequest:(ZMTransportRequest *)request;
{
    id<ZMRequestGenerator> generator = [OCMockObject niceMockForProtocol:@protocol(ZMRequestGenerator)];
    [[[(id) generator stub] andReturn:request] nextRequest];
    return generator;
}

@end
