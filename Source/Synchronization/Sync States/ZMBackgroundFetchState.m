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


@import WireSystem;
@import WireUtilities;
@import WireTransport;

#import "ZMBackgroundFetchState.h"

#import "ZMObjectStrategyDirectory.h"
#import "ZMMissingUpdateEventsTranscoder.h"
#import "ZMSyncStateMachine.h"


static NSString* ZMLogTag ZM_UNUSED = @"BackgroundFetch";

static NSTimeInterval const MaximumTimeInState = 25;



@interface ZMBackgroundFetchState () <ZMTimerClient>

@property (nonatomic) BOOL errorInDowloading;
@property (nonatomic) NSUUID *updateEventIDWhenStartingFetch;
@property (nonatomic, readonly, weak) ZMMissingUpdateEventsTranscoder *missingUpdateEventsTranscoder;
@property (nonatomic) NSDate *stateEnterDate;
@property (nonatomic) ZMTimer *timer;
@property (nonatomic) NSTimeInterval maximumTimeInState;

@end



@implementation ZMBackgroundFetchState

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
    
    self.stateEnterDate = [NSDate date];
    self.errorInDowloading = NO;
    ZMMissingUpdateEventsTranscoder *strongTranscoder = self.missingUpdateEventsTranscoder;
    
    self.updateEventIDWhenStartingFetch = strongTranscoder.lastUpdateEventID;
    
    if (self.updateEventIDWhenStartingFetch == nil) {
        id<ZMStateMachineDelegate> stateMachine = self.stateMachineDelegate;
        [stateMachine goToState:stateMachine.preBackgroundState];
    } else {
        [strongTranscoder startDownloadingMissingNotifications];
    }
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
    
    [stateMachine goToState:stateMachine.preBackgroundState];
    [self markFetchAsComplete];
    
    ZMLogError(@"Timer cancelled background fetch after %g seconds.", fabs([self.stateEnterDate timeIntervalSinceNow]));
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
    request = [self.missingUpdateEventsTranscoder.requestGenerators nextRequest];

    ZM_WEAK(self);
    [request addCompletionHandler:[ZMCompletionHandler handlerOnGroupQueue:directory.moc block:^(ZMTransportResponse *response) {
        ZM_STRONG(self);
        if(response.result != ZMTransportResponseStatusSuccess) {
            self.errorInDowloading = YES;
        }
    }]];
    ZMLogDebug(@"Background fetch request: %@", request);
    
    // Be sure to transition out if there is nothing more to do. If there's no request, then -dataDidChange will not get called.
    if (request == nil) {
        [self transitionOutIfComplete];
    }
    
    return request;
}

- (void)transitionOutIfComplete;
{
    id<ZMStateMachineDelegate> stateMachine = self.stateMachineDelegate;
    
    if (self.errorInDowloading) {
        [stateMachine goToState:stateMachine.preBackgroundState];
    } else {
        const BOOL waitingForNotifications = self.missingUpdateEventsTranscoder.isDownloadingMissingNotifications;
        ZMLogDebug(@"Background fetch: waiting for %@", waitingForNotifications ? @"notifications " : @"");
        
        if (!waitingForNotifications) {
            [stateMachine goToState:stateMachine.preBackgroundState];
        }
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
    ZMBackgroundFetchResult const result = self.fetchResult;
    if (self.fetchCompletionHandler != nil) {
        self.fetchCompletionHandler(result);
        self.fetchCompletionHandler = nil;
    }
}

- (ZMBackgroundFetchResult)fetchResult;
{
    if (self.errorInDowloading) {
        return ZMBackgroundFetchResultFailed;
    } else {
        return self.didDownloadEvents ? ZMBackgroundFetchResultNewData : ZMBackgroundFetchResultNoData;
    }
}

- (BOOL)didDownloadEvents;
{
    NSUUID *start = self.updateEventIDWhenStartingFetch;
    NSUUID *end = self.missingUpdateEventsTranscoder.lastUpdateEventID;
    return !((start == end) || [start isEqual:end]);
}

- (ZMMissingUpdateEventsTranscoder *)missingUpdateEventsTranscoder;
{
    return self.objectStrategyDirectory.missingUpdateEventsTranscoder;
}

@end
