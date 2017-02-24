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
@import WireRequestStrategy;

#import "ZMEventProcessingState.h"
#import "ZMConnectionTranscoder.h"
#import "ZMUserTranscoder.h"
#import "ZMSyncStrategy.h"
#import "ZMSyncStateDelegate.h"
#import "ZMStateMachineDelegate.h"
#import <zmessaging/zmessaging-Swift.h>

@interface ZMEventProcessingState ()

@property (nonatomic) BOOL isSyncing; // Only used to send a notification to UI that syncing finished
@property (nonatomic) SyncStatus *synStatus;

@end;



@implementation ZMEventProcessingState

-(BOOL)shouldProcessLiveEvents
{
    return YES;
}

- (instancetype)initWithAuthenticationCenter:(ZMAuthenticationStatus *)authenticationStatus
                    clientRegistrationStatus:(ZMClientRegistrationStatus *)clientRegistrationStatus
                     objectStrategyDirectory:(id<ZMObjectStrategyDirectory>)objectStrategyDirectory
                        stateMachineDelegate:(id<ZMStateMachineDelegate>)stateMachineDelegate
                               slowSynStatus:(SyncStatus *)synStatus;
{
    
    self = [super initWithAuthenticationCenter:authenticationStatus
                      clientRegistrationStatus:clientRegistrationStatus
                       objectStrategyDirectory:objectStrategyDirectory
                          stateMachineDelegate:stateMachineDelegate];
    if (self) {
        self.synStatus = synStatus;
    }
    return self;
}

- (ZMTransportRequest *)nextRequest
{
    return nil;
}

- (void)didEnterState
{

}

- (void)tearDown
{
    [super tearDown];
}

@end
