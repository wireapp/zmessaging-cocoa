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
@import ZMCSystem;
@import ZMUtilities;
@import WireMessageStrategy;

#import "ZMBackgroundTaskState.h"
#import "ZMObjectStrategyDirectory.h"
#import "ZMSyncStateMachine.h"

#import <zmessaging/zmessaging-Swift.h>


static NSString *ZMLogTag ZM_UNUSED = @"BackgroundTask";

static NSTimeInterval const MaximumTimeInState = 25;

@interface ZMBackgroundTaskState () <ZMTimerClient>

@property (nonatomic, readonly, weak) ClientMessageTranscoder *clientMessageTranscoder;
@property (nonatomic) BOOL errorPerformingTask;
@property (nonatomic) BOOL didFinishTask;

@property (nonatomic) NSDate *stateEnterDate;
@property (nonatomic) ZMTimer *timer;
@property (nonatomic) NSTimeInterval maximumTimeInState;

@end



@implementation ZMBackgroundTaskState

- (ZMUpdateEventsPolicy)updateEventsPolicy
{
    return ZMUpdateEventPolicyIgnore;
}

- (void)tearDown
{
    [self.timer cancel];
    self.timer = nil;
    [super tearDown];
}

- (void)didEnterState
{
    self.maximumTimeInState = self.maximumTimeInState > 0 ? self.maximumTimeInState : MaximumTimeInState;
    self.timer = [ZMTimer timerWithTarget:self];
    [self.timer fireAfterTimeInterval:self.maximumTimeInState];
    self.didFinishTask = NO;
    self.errorPerformingTask = NO;
    
    self.stateEnterDate = [NSDate date];
}

- (void)didLeaveState;
{
    [self.timer cancel];
    self.timer = nil;
    [super didLeaveState];
    [self markFetchAsComplete];
}

- (void)timerDidFire:(ZMTimer *)timer
{
    if (timer != self.timer){
        return;
    }
    
    [self.timer cancel];
    self.timer = nil;
    
    id<ZMStateMachineDelegate> stateMachine = self.stateMachineDelegate;
    if (stateMachine.currentState != self) {
        return;
    }
    self.errorPerformingTask = YES;
    
    [stateMachine goToState:stateMachine.preBackgroundState];
    [self markFetchAsComplete];
    
    ZMLogError(@"Timer cancelled background task after %g seconds.", fabs([self.stateEnterDate timeIntervalSinceNow]));
}

- (void)didEnterBackground
{
    // no op
}

- (void)didEnterForeground
{
    [self.stateMachineDelegate startQuickSync];
}

- (void)didRequestSynchronization
{
    // no-op
}

- (void)dataDidChange;
{
    [self transitionOutIfComplete];
}

- (ZMTransportRequest *)nextRequest
{
    id<ZMObjectStrategyDirectory> directory = self.objectStrategyDirectory;
    
    ZMTransportRequest *request;
    request = [self.clientMessageTranscoder nextRequest];
    ZM_WEAK(self);
    [request addCompletionHandler:[ZMCompletionHandler handlerOnGroupQueue:directory.moc block:^(ZMTransportResponse *response) {
        if (response.result == ZMTransportResponseStatusSuccess) {
            self.didFinishTask = YES;
        } else if (response.result == ZMTransportResponseStatusPermanentError) {
            ZM_STRONG(self);
            BOOL hasMissingClients = ([[response.payload.asDictionary optionalDictionaryForKey:@"missing"] count] > 0);
            if (!hasMissingClients) {
                self.errorPerformingTask = YES;
            }
        } else if (response.result == ZMTransportResponseStatusExpired){
            self.errorPerformingTask = YES;
        }
    }]];
    
    ZMLogDebug(@"Background fetch request: %@", request);
    
    // Be sure to transition out if there is nothing more to do. Iftran there's no request, then -dataDidChange will not get called.
    if (request == nil) {
        [self transitionOutIfComplete];
    }
    
    return request;
}

- (void)transitionOutIfComplete;
{
    id<ZMStateMachineDelegate> stateMachine = self.stateMachineDelegate;
    
    if (self.errorPerformingTask || self.didFinishTask) {
        [stateMachine goToState:stateMachine.preBackgroundState];
    }
}


- (void)markFetchAsComplete;
{
    //
    // We tell the OS if there was new data for us to download. This allows the OS to reschedule
    // background fetching based on whether there is data. For a user that continuously has new
    // data the OS can schedule background fetching more often. For a user the rarely has new data
    // the OS can decide to do background fetching less often. The OS (supposedly) also uses
    // the time of day to heuristically determine when it's a good time to schedule background
    // fetches.
    //
    ZMBackgroundTaskResult const result = self.fetchResult;
    if (self.taskCompletionHandler != nil) {
        self.taskCompletionHandler(result);
        self.taskCompletionHandler = nil;
    }
}

- (ZMBackgroundTaskResult)fetchResult;
{
    if (self.errorPerformingTask) {
        return ZMBackgroundTaskResultFailed;
    }
    return self.didFinishTask ? ZMBackgroundTaskResultSucceed : ZMBackgroundTaskResultFailed;
}

- (ClientMessageTranscoder *)clientMessageTranscoder;
{
    return self.objectStrategyDirectory.clientMessageTranscoder;
}


@end

