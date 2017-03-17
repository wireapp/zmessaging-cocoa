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


@import ZMUtilities;
@import ZMTransport;
@import WireRequestStrategy;

#import "ZMBackgroundState.h"
#import "ZMObjectStrategyDirectory.h"
#import "ZMStateMachineDelegate.h"

@interface ZMBackgroundState ()

@property (nonatomic, readonly, weak) id<ZMBackgroundable> backgroundableSession;
@property (nonatomic) BOOL didPrepareForSuspend;

@end



@implementation ZMBackgroundState


- (instancetype)initWithAuthenticationCenter:(ZMAuthenticationStatus *)authenticationStatus
                    clientRegistrationStatus:(ZMClientRegistrationStatus *)clientRegistrationStatus
                     objectStrategyDirectory:(id<ZMObjectStrategyDirectory>)objectStrategyDirectory
                        stateMachineDelegate:(id<ZMStateMachineDelegate>)stateMachineDelegate
{
    NOT_USED(authenticationStatus);
    NOT_USED(objectStrategyDirectory);
    NOT_USED(stateMachineDelegate);
    NOT_USED(clientRegistrationStatus);
    RequireString(NO, "Should not use this init.");
    return nil;
}

- (instancetype)initWithAuthenticationCenter:(ZMAuthenticationStatus *)authenticationStatus
                    clientRegistrationStatus:(ZMClientRegistrationStatus *)clientRegistrationStatus
                     objectStrategyDirectory:(id<ZMObjectStrategyDirectory>)objectStrategyDirectory
                        stateMachineDelegate:(id<ZMStateMachineDelegate>)stateMachineDelegate
                       backgroundableSession:(id<ZMBackgroundable>)session
{
    self = [super initWithAuthenticationCenter:authenticationStatus
                      clientRegistrationStatus:clientRegistrationStatus
                       objectStrategyDirectory:objectStrategyDirectory
                          stateMachineDelegate:stateMachineDelegate];
    if(self) {
        _backgroundableSession = session;
    }
    return self;
}

- (ZMUpdateEventsPolicy)updateEventsPolicy
{
    return ZMUpdateEventPolicyIgnore;
}

- (BOOL)supportsBackgroundFetch;
{
    return YES;
}

- (void)didEnterState
{
    self.didPrepareForSuspend = NO;
    [self.backgroundableSession enterBackground];
}

- (void)didLeaveState
{
    [self.backgroundableSession enterForeground];
}

- (void)didRequestSynchronization
{
    // no op
}

- (void)didEnterBackground
{
    // no op
}

- (void)didEnterForeground
{
    [self.stateMachineDelegate startQuickSync];
}

- (ZMTransportRequest *)nextRequest
{
    id<ZMObjectStrategyDirectory> directory = self.objectStrategyDirectory;
    NSMutableArray *transcoders = @[
                            directory.flowTranscoder,
                            directory.selfTranscoder,
                            ].mutableCopy;

    if ([ZMUserSession useCallKit]) {
        [transcoders addObject:directory.callStateTranscoder];
    }
    
    ZMTransportRequest *nextRequest = [self nextRequestFromTranscoders:transcoders];
    
    if ((nextRequest == nil) && (! self.didPrepareForSuspend)) {
        [self prepareForSuspend];
    }
    return nextRequest;
}

- (void)prepareForSuspend;
{
    self.didPrepareForSuspend = YES;
    
    [self.backgroundableSession prepareForSuspendedState];
}

@end
