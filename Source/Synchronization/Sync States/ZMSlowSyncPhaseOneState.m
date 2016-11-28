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


#import "ZMSlowSyncPhaseOneState.h"
#import "ZMStateMachineDelegate.h"
#import "ZMConnectionTranscoder.h"
#import "ZMConversationTranscoder.h"
#import "ZMObjectStrategyDirectory.h"
#import "ZMSyncStateDelegate.h"


@implementation ZMSlowSyncPhaseOneState

- (void)didEnterState
{
    id<ZMStateMachineDelegate> strongMachine = self.stateMachineDelegate;
    [strongMachine didStartSlowSync];
    [strongMachine didStartSync];
}

- (void)dataDidChange
{
    id<ZMObjectStrategyDirectory> directory = self.objectStrategyDirectory;
    if(directory.connectionTranscoder.isSlowSyncDone && directory.conversationTranscoder.isSlowSyncDone) {
        id<ZMStateMachineDelegate> strongDelegate = self.stateMachineDelegate;
        [strongDelegate goToState:strongDelegate.slowSyncPhaseTwoState];
        return;
    }
}

- (ZMTransportRequest *)nextRequest
{
    id<ZMObjectStrategyDirectory> directory = self.objectStrategyDirectory;
    return [self nextRequestFromTranscoders:@[directory.connectionTranscoder,
                                              directory.conversationTranscoder]];
}

- (ZMUpdateEventsPolicy)updateEventsPolicy
{
    return ZMUpdateEventPolicyBuffer;
}



@end
