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
@import WireMessageStrategy;

#import "ZMPreBackgroundState.h"
#import "ZMCallFlowRequestStrategy.h"
#import "ZMObjectStrategyDirectory.h"
#import "ZMStateMachineDelegate.h"

@interface ZMPreBackgroundState ()

@property (nonatomic) ZMBackgroundActivity *activity;

@end


@implementation ZMPreBackgroundState

- (void)didEnterState
{
//    id<ZMStateMachineDelegate> strongDelegate = self.stateMachineDelegate;
    if ([self canGoToBackgroundState])
    {
//        [strongDelegate goToState:strongDelegate.backgroundState];
        return;
    }
    self.activity = [[BackgroundActivityFactory sharedInstance] backgroundActivityWithName:@"ZMPreBackgroundState"];
}

- (void)tearDown
{
    [self.activity endActivity];
    self.activity = nil;
    [super tearDown];
}

- (void)didLeaveState
{
    [self.activity endActivity];
    self.activity = nil;
}

- (void)didEnterBackground
{
    // noop
}

- (void)didEnterForeground
{
    id<ZMStateMachineDelegate> stateMachine = self.stateMachineDelegate;
    [stateMachine goToState:stateMachine.eventProcessingState];
}

- (void)dataDidChange
{
//    id<ZMStateMachineDelegate> strongDelegate = self.stateMachineDelegate;
    if ([self canGoToBackgroundState])
    {
//        [strongDelegate goToState:strongDelegate.backgroundState];
    }
}

- (ZMTransportRequest *)nextRequest
{
    NSArray *transcoders = @[];
    
    ZMTransportRequest *nextRequest = [self nextRequestFromTranscoders:transcoders];
    return nextRequest;
}

- (BOOL)canGoToBackgroundState
{
    // TODO Sabine what's supposed to happen here? do we still need this?
    id<ZMObjectStrategyDirectory> directory = self.objectStrategyDirectory;
    BOOL clientMessageHasPending = directory.clientMessageTranscoder.hasPendingMessages;
    return !clientMessageHasPending;
}

@end
