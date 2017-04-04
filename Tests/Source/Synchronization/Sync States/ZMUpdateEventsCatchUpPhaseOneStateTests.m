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


@import WireTransport;
@import WireSyncEngine;

#import "StateBaseTest.h"
#import "ZMUpdateEventsCatchUpPhaseOneState.h"
#import "ZMMissingUpdateEventsTranscoder.h"
#import "ZMStateMachineDelegate.h"

@interface ZMUpdateEventsCatchUpPhaseOneStateTests : StateBaseTest

@property (nonatomic, readonly) ZMUpdateEventsCatchUpPhaseOneState *sut;

@end



@implementation ZMUpdateEventsCatchUpPhaseOneStateTests

- (void)setUp
{
    [super setUp];
    _sut = [[ZMUpdateEventsCatchUpPhaseOneState alloc] initWithAuthenticationCenter:self.authenticationStatus
                                                           clientRegistrationStatus:self.clientRegistrationStatus
                                                            objectStrategyDirectory:self.objectDirectory
                                                               stateMachineDelegate:self.stateMachine];
    
    [self stubRequestsOnHighPriorityObjectSync];

}

- (void)tearDown
{
    _sut = nil;
    [super tearDown];
}

- (void)testThatItSwitchesToPreBackgroundState
{
    // expectation
    [[(id)self.stateMachine expect] goToState:[self.stateMachine preBackgroundState]];
    
    // when
    [self.sut didEnterBackground];
}

- (void)testThatItDoesNotSwitchToQuickSyncOnEnteringForeground
{
    // expectation
    [[(id)self.stateMachine reject] startQuickSync];
    
    // when
    [self.sut didEnterForeground];
}

- (void)testThatItCallsDidStartSyncOnEnter
{
    // expect
    [[(id)self.sut.stateMachineDelegate expect] didStartSync];
    [[[(id)self.objectDirectory.missingUpdateEventsTranscoder stub] andReturnValue:@YES] hasLastUpdateEventID];
    [[(id)self.objectDirectory.missingUpdateEventsTranscoder stub] startDownloadingMissingNotifications];
    
    // when
    [self performPretendingUiMocIsSyncMoc:^{
        [self.sut didEnterState];
    }];
}

- (void)testThatThePolicyIsToBufferEvents
{
    XCTAssertEqual(self.sut.updateEventsPolicy, ZMUpdateEventPolicyBuffer);
}

- (void)testThatItRequestsANotificationSyncDownloadWhenEnteringAndWeHaveALastUpdateEventID
{
    // expect
    [[(id)self.sut.stateMachineDelegate expect] didStartSync];
    [[[(id)self.objectDirectory.missingUpdateEventsTranscoder stub] andReturnValue:@YES] hasLastUpdateEventID];
    [[(id)self.objectDirectory.missingUpdateEventsTranscoder expect] startDownloadingMissingNotifications];
    
    // when
    [self performPretendingUiMocIsSyncMoc:^{
        [self.sut didEnterState];
    }];
}

- (void)testThatItRequestsANotificationSyncDownloadWhenEnteringAndWeDoNotHaveALastUpdateEventID
{
    // expect
    id delegate = self.sut.stateMachineDelegate;
    [[delegate expect] didStartSync];
    [[delegate expect] startSlowSync];
    [[[(id)self.objectDirectory.missingUpdateEventsTranscoder stub] andReturnValue:@NO] hasLastUpdateEventID];
    [[(id)self.objectDirectory.missingUpdateEventsTranscoder expect] startDownloadingMissingNotifications];
    
    // when
    [self performPretendingUiMocIsSyncMoc:^{
        [self.sut didEnterState];
    }];
}

- (void)testThatItAsksNextRequestToTheObjectSyncs
{
    NSArray *expectedObjectSync = @[
                                    [self.objectDirectory missingUpdateEventsTranscoder],
                                    ];
    
    [self checkThatItCallsRequestGeneratorsOnObjectsOfClass:expectedObjectSync creationOfStateBlock:^ZMSyncState *(id<ZMObjectStrategyDirectory> directory) {
        
        [[[(id)self.stateMachine stub] andReturnValue:OCMOCK_VALUE(YES) ]isUpdateEventStreamActive];
        [[[(id)directory.missingUpdateEventsTranscoder stub] andReturnValue:OCMOCK_VALUE(YES)] isDownloadingMissingNotifications];
        
        return [[ZMUpdateEventsCatchUpPhaseOneState alloc] initWithAuthenticationCenter:self.authenticationStatus clientRegistrationStatus:self.clientRegistrationStatus objectStrategyDirectory:directory stateMachineDelegate:self.stateMachine];
    }];
    
}

- (void)testThatItDoesNotSwitchToNextStateWhenNotificationSyncIsNotDoneDownloading
{
    // expect
    [[(id)self.stateMachine reject] goToState:OCMOCK_ANY];
    [[[(id)self.objectDirectory.missingUpdateEventsTranscoder stub] andReturn:@[]] requestGenerators];
    [[[(id)self.stateMachine stub] andReturnValue:OCMOCK_VALUE(YES) ]isUpdateEventStreamActive];
    [[[(id)self.objectDirectory.missingUpdateEventsTranscoder expect] andReturnValue:OCMOCK_VALUE(YES)] isDownloadingMissingNotifications];
    
    // when
    [self.sut dataDidChange];
}

- (void)testThatItSwitchesToSlowSyncWhenTheRequestIsAPermanentError
{
    // given
    ZMTransportRequest *request = [ZMTransportRequest requestGetFromPath:@"/note"];
    id<ZMRequestGenerator> generator = [self generatorReturningRequest:request];
    [[[(id)self.objectDirectory.missingUpdateEventsTranscoder stub] andReturn:@[generator]] requestGenerators];
    [[[(id)self.stateMachine stub] andReturnValue:OCMOCK_VALUE(YES) ]isUpdateEventStreamActive];
    [[[(id)self.objectDirectory.missingUpdateEventsTranscoder stub] andReturnValue:OCMOCK_VALUE(YES)] isDownloadingMissingNotifications];

    // expect
    [[(id)self.stateMachine expect] startSlowSync];

    
    // when
    XCTAssertEqual([self.sut nextRequest], request);
    [request completeWithResponse:[ZMTransportResponse responseWithPayload:nil HTTPStatus:404 transportSessionError:nil]];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.sut dataDidChange]; // need to call to switch state
}

- (void)testThatItSwitchesToNextStateWhenNotificationSyncIsDoneDownloadingAndTheUpdateStreamIsActive
{
    // expect
    [[(id)self.stateMachine expect] goToState:self.stateMachine.updateEventsCatchUpPhaseTwoState];
    [[[(id)self.stateMachine expect] andReturnValue:OCMOCK_VALUE(YES) ]isUpdateEventStreamActive];
    [[[(id)self.objectDirectory.missingUpdateEventsTranscoder expect] andReturnValue:OCMOCK_VALUE(NO)] isDownloadingMissingNotifications];
    
    // when
    [self.sut dataDidChange];
}

- (void)testThatItDoesNotSwitchToNextStateWhenNotificationSyncIsDoneDownloadingButUpdateStreamIsNotActive
{
    // expect
    [[(id)self.stateMachine reject] goToState:OCMOCK_ANY];
    [[[(id)self.objectDirectory.missingUpdateEventsTranscoder stub] andReturn:@[]] requestGenerators];
    [[[(id)self.stateMachine expect] andReturnValue:OCMOCK_VALUE(NO) ]isUpdateEventStreamActive];
    [[[(id)self.objectDirectory.missingUpdateEventsTranscoder expect] andReturnValue:OCMOCK_VALUE(NO)] isDownloadingMissingNotifications];
    
    // when
    [self.sut dataDidChange];
}

- (void)testThatItDoesNotSwitchToNextStateWhenUpdateStreamIsActiveButNotificationSyncIsNotDoneDownloading
{
    // expect
    [[(id)self.stateMachine reject] goToState:OCMOCK_ANY];
    [[[(id)self.objectDirectory.missingUpdateEventsTranscoder stub] andReturn:@[]] requestGenerators];
    [[[(id)self.stateMachine expect] andReturnValue:OCMOCK_VALUE(YES) ]isUpdateEventStreamActive];
    [[[(id)self.objectDirectory.missingUpdateEventsTranscoder expect] andReturnValue:OCMOCK_VALUE(YES)] isDownloadingMissingNotifications];
    
    // when
    [self.sut dataDidChange];
}


- (void)testThatItSwitchsToSlowSyncOnEnterIfTheNotificationSyncHasNotLastUpdateEventID
{
    // expect
    [[[(id)self.objectDirectory.missingUpdateEventsTranscoder stub] andReturnValue:@NO] hasLastUpdateEventID];
    [[(id)self.stateMachine stub] didStartSync];
    
    [[(id)self.objectDirectory.missingUpdateEventsTranscoder expect] startDownloadingMissingNotifications];
    [[(id)self.stateMachine expect] startSlowSync];
    
    // when
    [self performPretendingUiMocIsSyncMoc:^{
        [self.sut didEnterState];
    }];

}

- (void)testThatItSwitchesToUnauthorizedStateOnDidFailAuthentication
{
    //expect
    [[(id)self.stateMachine expect] goToState:[self.stateMachine unauthenticatedState]];
    
    //when
    [self.sut didFailAuthentication];
    [(id)self.stateMachine verify];
}



@end
