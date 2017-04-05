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
@import ZMTransport;
@import ZMCDataModel;

#import "ZMUserTranscoder.h"
#import "ZMSyncStateMachine+internal.h"
#import "ZMSyncState.h"
#import "ZMUnauthenticatedState.h"
#import "ZMEventProcessingState.h"

#import "ZMObjectStrategyDirectory.h"
#import "ZMAuthenticationStatus.h"
#import "ZMUserSessionAuthenticationNotification.h"

#import <zmessaging/zmessaging-Swift.h>

static NSString *ZMLogTag ZM_UNUSED = @"State machine";

@interface ZMSyncStateMachine ()

@property (nonatomic) ZMSyncState *unauthenticatedState; ///< need to log in
@property (nonatomic) ZMSyncState *eventProcessingState; ///< can normally process events

@property (nonatomic, weak) id<ZMObjectStrategyDirectory> directory;
@property (nonatomic, weak) ZMAuthenticationStatus * authenticationStatus;
@property (nonatomic, weak) ZMClientRegistrationStatus * clientRegistrationStatus;

@property (nonatomic) BOOL wasLoggedInAtLastRequest;
@property (nonatomic) ZMSyncState *currentState;

@property (nonatomic, weak) id<ZMSyncStateDelegate> syncStateDelegate;

@property (nonatomic) id authNotificationToken;
@end



@implementation ZMSyncStateMachine

- (instancetype)initWithAuthenticationStatus:(ZMAuthenticationStatus *)authenticationStatus
                    clientRegistrationStatus:(ZMClientRegistrationStatus *)clientRegistrationStatus
                     objectStrategyDirectory:(id<ZMObjectStrategyDirectory>)objectStrategyDirectory
                           syncStateDelegate:(id<ZMSyncStateDelegate>)syncStateDelegate
                                 application:(id<ZMApplication>)application
                               slowSynStatus:(SyncStatus *)slowSynStatus;

{
    self = [super init];
    if(self) {
        self.directory = objectStrategyDirectory;
        self.authenticationStatus = authenticationStatus;
        self.clientRegistrationStatus = clientRegistrationStatus;
        
        self.unauthenticatedState = [[ZMUnauthenticatedState alloc] initWithAuthenticationCenter:authenticationStatus
                                                                        clientRegistrationStatus:clientRegistrationStatus
                                                                         objectStrategyDirectory:objectStrategyDirectory
                                                                            stateMachineDelegate:self
                                                                                     application:application
                                     ];
        self.eventProcessingState = [[ZMEventProcessingState alloc] initWithAuthenticationCenter:authenticationStatus clientRegistrationStatus:clientRegistrationStatus  objectStrategyDirectory:objectStrategyDirectory stateMachineDelegate:self slowSynStatus:slowSynStatus];
        
        self.syncStateDelegate = syncStateDelegate;
        
        ZM_WEAK(self);
        self.authNotificationToken = [ZMUserSessionAuthenticationNotification addObserverWithBlock:^(ZMUserSessionAuthenticationNotification *note) {
            ZM_STRONG(self);
            if (note.type == ZMAuthenticationNotificationAuthenticationDidFail) {
                [self.directory.moc performGroupedBlock:^{
                    [self didFailAuthentication];
                }];
            }
        }];

        [objectStrategyDirectory.moc performGroupedBlock:^{
            [self goToState:self.unauthenticatedState];
        }];
        
    }
    return self;
}

- (void)tearDown
{
    [ZMUserSessionAuthenticationNotification removeObserver:self.authNotificationToken];

    [self.unauthenticatedState tearDown];
    [self.eventProcessingState tearDown];
}

- (void)dealloc
{
    [self tearDown];
}

- (void)prepareForSuspendedState;
{
    // No-op
}

- (void)goToState:(ZMSyncState *)state
{
    ZMLogDebug(@"%@ %@", NSStringFromSelector(_cmd), state);
    [self.currentState didLeaveState];
    
    self.currentState = state;
    [self.currentState didEnterState];
}

- (ZMTransportRequest *)nextRequest
{
    ZMSyncState *initialState = self.currentState;
    ZMTransportRequest *request = [self.currentState nextRequest];
    
    while(request == nil && self.currentState != initialState) {
        initialState = self.currentState;
        request = [self.currentState nextRequest];
    }
    [request setDebugInformationState:self.currentState];
    
    return request;
}

- (ZMUpdateEventsPolicy)updateEventsPolicy
{
    return self.currentState.updateEventsPolicy;
}

- (void)didFailAuthentication
{
    [self.currentState didFailAuthentication];
}

- (void)dataDidChange
{
    [self.currentState dataDidChange];
}


@end
