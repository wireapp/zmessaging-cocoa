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

#import "ZMDownloadLastUpdateEventIDState.h"
#import "ZMObjectStrategyDirectory.h"
#import "ZMMissingUpdateEventsTranscoder.h"
#import "ZMLastUpdateEventIDTranscoder.h"
#import "ZMStateMachineDelegate.h"

@implementation ZMDownloadLastUpdateEventIDState

- (void)dataDidChange
{
    id<ZMObjectStrategyDirectory> directory = self.objectStrategyDirectory;
    BOOL hasLastUpdateEvent = directory.missingUpdateEventsTranscoder.hasLastUpdateEventID;
    if( hasLastUpdateEvent || ! directory.lastUpdateEventIDTranscoder.isDownloadingLastUpdateEventID) {
        id<ZMStateMachineDelegate> stateMachine = self.stateMachineDelegate;
        [stateMachine goToState:stateMachine.slowSyncPhaseOneState];
    }
}

- (ZMTransportRequest *)nextRequest;
{
    id<ZMObjectStrategyDirectory> directory = self.objectStrategyDirectory;
    return [self nextRequestFromTranscoders:@[directory.lastUpdateEventIDTranscoder]];
}

- (ZMUpdateEventsPolicy)updateEventsPolicy
{
    return ZMUpdateEventPolicyBuffer;
}

- (void)didEnterState
{
    [[self.objectStrategyDirectory lastUpdateEventIDTranscoder] startRequestingLastUpdateEventIDWithoutPersistingIt];
}

@end
