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
@import WireDataModel;

#import "ZMUpdateEventsCatchUpPhaseOneState.h"
#import "ZMMissingUpdateEventsTranscoder.h"
#import "ZMObjectStrategyDirectory.h"
#import "ZMStateMachineDelegate.h"


@interface ZMUpdateEventsCatchUpPhaseOneState ()

@property (nonatomic) BOOL errorInDowloading;

@end

@implementation ZMUpdateEventsCatchUpPhaseOneState

- (ZMUpdateEventsPolicy)updateEventsPolicy
{
    return ZMUpdateEventPolicyBuffer;
}


- (void)didEnterState
{
    id<ZMObjectStrategyDirectory> directory = self.objectStrategyDirectory;
    self.errorInDowloading = NO;
    
    id<ZMStateMachineDelegate> strongMachine = self.stateMachineDelegate;
    [strongMachine didStartSync];
    
    // NOTE:
    // this relies on the state machine to switch (re-enter) this state when the push channel goes down
    // and the web socket automatically attempting to re-open. So I don't have to explicitly open it here
    
    if(directory.missingUpdateEventsTranscoder.hasLastUpdateEventID) {
        [directory.missingUpdateEventsTranscoder startDownloadingMissingNotifications];
    }
    else {
        [directory.missingUpdateEventsTranscoder startDownloadingMissingNotifications];
        //slow sync will wait for notification to be loaded
        [strongMachine startSlowSync];
    }
}

- (void)dataDidChange
{
    id<ZMStateMachineDelegate> stateMachine = self.stateMachineDelegate;
    
    if(self.errorInDowloading) {
        self.errorInDowloading = NO;
        [stateMachine startSlowSync];
        return;
    }
    
    
    const BOOL waitingForNotifications = self.objectStrategyDirectory.missingUpdateEventsTranscoder.isDownloadingMissingNotifications;
    const BOOL isUpdateStreamActive = [stateMachine isUpdateEventStreamActive];
    
    if(!waitingForNotifications && isUpdateStreamActive) {
        [stateMachine goToState:stateMachine.updateEventsCatchUpPhaseTwoState];
        return;
    }
}

- (ZMTransportRequest *)nextRequest
{
    id<ZMObjectStrategyDirectory> directory = self.objectStrategyDirectory;
    ZMTransportRequest *request = [directory.missingUpdateEventsTranscoder.requestGenerators nextRequest];
    if(request != nil) {
        ZM_WEAK(self);
        [request addCompletionHandler:[ZMCompletionHandler handlerOnGroupQueue:directory.moc block:^(ZMTransportResponse *response) {
            ZM_STRONG(self);
            if(response.result == ZMTransportResponseStatusPermanentError) {
                self.errorInDowloading = YES;
            }
        }]];
    }
    return request;
}

@end
