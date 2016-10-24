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


#import "ZMSlowSyncPhaseTwoState.h"
#import "ZMStateMachineDelegate.h"
#import "ZMSyncStrategy.h"
#import "ZMObjectStrategyDirectory.h"
#import "ZMStateMachineDelegate.h"
#import "ZMMissingUpdateEventsTranscoder.h"
#import "ZMLastUpdateEventIDTranscoder.h"
#import "ZMuserProfileUpdateTranscoder.h"
#import "ZMCallStateTranscoder.h"

@implementation ZMSlowSyncPhaseTwoState


- (void)dataDidChange
{
    if(self.objectStrategyDirectory.userTranscoder.isSlowSyncDone) {
        id<ZMStateMachineDelegate> strongDelegate = self.stateMachineDelegate;
        [strongDelegate goToState:strongDelegate.eventProcessingState];
        return;
    }
}

- (ZMTransportRequest *)nextRequest
{
    id<ZMObjectStrategyDirectory> directory = self.objectStrategyDirectory;

    return [self nextRequestFromTranscoders:@[directory.userTranscoder, directory.userProfileUpdateTranscoder]];
}

- (void)didLeaveState
{
    id<ZMObjectStrategyDirectory> directory = self.objectStrategyDirectory;
    [super didLeaveState];
    [[directory lastUpdateEventIDTranscoder] persistLastUpdateEventID];
}

- (void)didEnterState
{
    id<ZMObjectStrategyDirectory> directory = self.objectStrategyDirectory;

    [super didEnterState];
    [directory.userTranscoder setNeedsSlowSync];
    [directory.callStateTranscoder setNeedsSlowSync];
}

- (ZMUpdateEventsPolicy)updateEventsPolicy
{
    return ZMUpdateEventPolicyBuffer;
}

@end
