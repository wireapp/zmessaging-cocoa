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


@import ZMCSystem;
@import ZMUtilities;
@import ZMTransport;
@import WireRequestStrategy;

#import "ZMSyncState.h"
#import "ZMStateMachineDelegate.h"
#import "ZMObjectStrategyDirectory.h"


@implementation ZMSyncState

- (instancetype)init
{
    RequireString(NO, "Do not use.");
    return [self initWithAuthenticationCenter:nil
                     clientRegistrationStatus:nil
                      objectStrategyDirectory:nil
                         stateMachineDelegate:nil];
}

- (instancetype)initWithAuthenticationCenter:(ZMAuthenticationStatus *)authenticationStatus
                    clientRegistrationStatus:(ZMClientRegistrationStatus *)clientRegistrationStatus
                     objectStrategyDirectory:(id<ZMObjectStrategyDirectory>)objectStrategyDirectory
                        stateMachineDelegate:(id<ZMStateMachineDelegate>)stateMachineDelegate;
{
    self = [super self];
    if(self)
    {
        _authenticationStatus = authenticationStatus;
        _stateMachineDelegate = stateMachineDelegate;
        _objectStrategyDirectory = objectStrategyDirectory;
        _clientRegistrationStatus= clientRegistrationStatus;
    }
    return self;
}

- (ZMUpdateEventsPolicy)updateEventsPolicy
{
    return ZMUpdateEventPolicyProcess;
}

- (BOOL)supportsBackgroundFetch;
{
    return NO;
}

- (void)didRequestSynchronization
{
    [self.stateMachineDelegate startQuickSync];
}

- (void)didFailAuthentication
{
    NSObject<ZMStateMachineDelegate> *strongDelegate = self.stateMachineDelegate;
    [strongDelegate goToState:strongDelegate.unauthenticatedState];
}

- (void)didEnterState
{
    // no-op
}

- (void)didLeaveState
{
    // no-op
}

- (void)didEnterBackground
{
    NSObject<ZMStateMachineDelegate> *strongDelegate = self.stateMachineDelegate;
    [strongDelegate goToState:strongDelegate.preBackgroundState];
}

- (void)didEnterForeground
{
    // no-op
}

- (ZMTransportRequest *)nextRequest
{
    return nil;
}


- (void)dataDidChange
{
    
}

- (void)tearDown
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)dealloc
{
    [self tearDown];
}

@end



@implementation ZMSyncState (Subclasses)

- (ZMTransportRequest *)nextRequestFromTranscoders:(NSArray *)transcoders;
{
    ZMTransportRequest *nextRequest;
    for (id <ZMObjectStrategy> transcoder in transcoders) {
        nextRequest = [transcoder.requestGenerators nextRequest];
        [nextRequest setDebugInformationTranscoder:transcoder];
        if (nextRequest != nil) {
            return nextRequest;
            
        }
    }
    return nil;
}

@end
