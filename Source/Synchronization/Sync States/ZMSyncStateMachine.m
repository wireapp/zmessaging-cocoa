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
@import WireTransport;
@import WireDataModel;

#import "ZMUserTranscoder.h"
#import "ZMSyncStateMachine+internal.h"
#import "ZMSyncState.h"
#import "ZMUnauthenticatedState.h"
#import "ZMEventProcessingState.h"
#import "ZMSlowSyncPhaseOneState.h"
#import "ZMSlowSyncPhaseTwoState.h"
#import "ZMUpdateEventsCatchUpPhaseOneState.h"
#import "ZMUpdateEventsCatchUpPhaseTwoState.h"
#import "ZMDownloadLastUpdateEventIDState.h"
#import "ZMBackgroundState.h"
#import "ZMPreBackgroundState.h"
#import "ZMUnauthenticatedBackgroundState.h"
#import "ZMBackgroundFetchState.h"
#import "ZMBackgroundTaskState.h"

#import "ZMObjectStrategyDirectory.h"
#import "ZMAuthenticationStatus.h"
#import "ZMUserSessionAuthenticationNotification.h"

#import <WireSyncEngine/WireSyncEngine-Swift.h>

NSString *const ZMApplicationDidEnterEventProcessingStateNotificationName = @"ZMApplicationDidEnterEventProcessingStateNotification";


static NSString *ZMLogTag ZM_UNUSED = @"State machine";

@interface ZMSyncStateMachine ()

@property (nonatomic) ZMSyncState *unauthenticatedState; ///< need to log in
@property (nonatomic) ZMSyncState *unauthenticatedBackgroundState; ///< need to log in, but we are in the background
@property (nonatomic) ZMSyncState *eventProcessingState; ///< can normally process events
@property (nonatomic) ZMSyncState *slowSyncPhaseOneState; ///< first part of the hard sync
@property (nonatomic) ZMSyncState *slowSyncPhaseTwoState; ///< second part of the hard sync
@property (nonatomic) ZMSyncState *updateEventsCatchUpPhaseOneState; ///< start procedure to catch up with missing notifications
@property (nonatomic) ZMSyncState *updateEventsCatchUpPhaseTwoState; ///< finish catching up with missing notifications
@property (nonatomic) ZMSyncState *downloadLastUpdateEventIDState; ///< handle getting the last notification ID
@property (nonatomic) ZMSyncState *backgroundState; ///< handles background requests
@property (nonatomic) ZMSyncState *preBackgroundState; ///< waits until we are ready to go to background
@property (nonatomic) ZMBackgroundFetchState *backgroundFetchState; ///< does background fetching on iOS
@property (nonatomic) ZMBackgroundTaskState *backgroundTaskState; ///< performs background tasks

@property (nonatomic, weak) id<ZMObjectStrategyDirectory> directory;
@property (nonatomic, weak) ZMAuthenticationStatus * authenticationStatus;
@property (nonatomic, weak) ZMClientRegistrationStatus * clientRegistrationStatus;

@property (nonatomic) BOOL wasLoggedInAtLastRequest;
@property (nonatomic) ZMSyncState *currentState;

@property (nonatomic) BOOL isUpdateEventStreamActive;

@property (nonatomic, weak) id<ZMSyncStateDelegate> syncStateDelegate;

@property (nonatomic) id authNotificationToken;

@end



@implementation ZMSyncStateMachine

- (instancetype)initWithAuthenticationStatus:(ZMAuthenticationStatus *)authenticationStatus
                    clientRegistrationStatus:(ZMClientRegistrationStatus *)clientRegistrationStatus
                     objectStrategyDirectory:(id<ZMObjectStrategyDirectory>)objectStrategyDirectory
                           syncStateDelegate:(id<ZMSyncStateDelegate>)syncStateDelegate
                            backgroundableSession:(id<ZMBackgroundable>)backgroundableSession
                                 application:(id<ZMApplication>)application
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
        self.unauthenticatedBackgroundState = [[ZMUnauthenticatedBackgroundState alloc] initWithAuthenticationCenter:authenticationStatus clientRegistrationStatus:clientRegistrationStatus  objectStrategyDirectory:objectStrategyDirectory stateMachineDelegate:self];
        self.slowSyncPhaseOneState = [[ZMSlowSyncPhaseOneState alloc] initWithAuthenticationCenter:authenticationStatus clientRegistrationStatus:clientRegistrationStatus objectStrategyDirectory:objectStrategyDirectory stateMachineDelegate:self];
        self.slowSyncPhaseTwoState = [[ZMSlowSyncPhaseTwoState alloc] initWithAuthenticationCenter:authenticationStatus clientRegistrationStatus:clientRegistrationStatus  objectStrategyDirectory:objectStrategyDirectory stateMachineDelegate:self];
        self.eventProcessingState = [[ZMEventProcessingState alloc] initWithAuthenticationCenter:authenticationStatus clientRegistrationStatus:clientRegistrationStatus  objectStrategyDirectory:objectStrategyDirectory stateMachineDelegate:self];
        self.updateEventsCatchUpPhaseOneState = [[ZMUpdateEventsCatchUpPhaseOneState alloc] initWithAuthenticationCenter:authenticationStatus clientRegistrationStatus:clientRegistrationStatus  objectStrategyDirectory:objectStrategyDirectory stateMachineDelegate:self];
        self.updateEventsCatchUpPhaseTwoState = [[ZMUpdateEventsCatchUpPhaseTwoState alloc] initWithAuthenticationCenter:authenticationStatus clientRegistrationStatus:clientRegistrationStatus  objectStrategyDirectory:objectStrategyDirectory stateMachineDelegate:self];
        self.downloadLastUpdateEventIDState = [[ZMDownloadLastUpdateEventIDState alloc] initWithAuthenticationCenter:authenticationStatus clientRegistrationStatus:clientRegistrationStatus  objectStrategyDirectory:objectStrategyDirectory stateMachineDelegate:self];
        self.backgroundState = [[ZMBackgroundState alloc] initWithAuthenticationCenter:authenticationStatus clientRegistrationStatus:clientRegistrationStatus objectStrategyDirectory:objectStrategyDirectory stateMachineDelegate:self backgroundableSession:backgroundableSession];
        self.preBackgroundState = [[ZMPreBackgroundState alloc] initWithAuthenticationCenter:authenticationStatus clientRegistrationStatus:clientRegistrationStatus objectStrategyDirectory:objectStrategyDirectory stateMachineDelegate:self];
        self.backgroundFetchState = [[ZMBackgroundFetchState alloc] initWithAuthenticationCenter:authenticationStatus clientRegistrationStatus:clientRegistrationStatus objectStrategyDirectory:objectStrategyDirectory stateMachineDelegate:self];
        self.backgroundTaskState = [[ZMBackgroundTaskState alloc] initWithAuthenticationCenter:authenticationStatus clientRegistrationStatus:clientRegistrationStatus objectStrategyDirectory:objectStrategyDirectory stateMachineDelegate:self];
        
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
    [self.unauthenticatedBackgroundState tearDown];
    [self.slowSyncPhaseOneState tearDown];
    [self.slowSyncPhaseTwoState tearDown];
    [self.eventProcessingState tearDown];
    [self.updateEventsCatchUpPhaseOneState tearDown];
    [self.updateEventsCatchUpPhaseTwoState tearDown];
    [self.downloadLastUpdateEventIDState tearDown];
    [self.backgroundState tearDown];
    [self.preBackgroundState tearDown];
    [self.backgroundFetchState tearDown];
    [self.backgroundTaskState tearDown];
}

- (void)dealloc
{
    [self tearDown];
}

- (void)didStartSync
{
    [self.syncStateDelegate didStartSync];
}

- (void)didFinishSync
{
    [self.syncStateDelegate didFinishSync];
}

- (void)enterBackground;
{
    [self.currentState didEnterBackground];
}

- (void)enterForeground
{
    [self.currentState didEnterForeground];
}

- (void)prepareForSuspendedState;
{
    // No-op
}

- (void)startQuickSync
{
    [self goToState:self.updateEventsCatchUpPhaseOneState];
}

- (void)startSlowSync
{
    [self goToState:self.downloadLastUpdateEventIDState];
}

- (void)startBackgroundFetchWithCompletionHandler:(ZMBackgroundFetchHandler)handler;
{
    if (self.currentState.supportsBackgroundFetch) {
        self.backgroundFetchState.fetchCompletionHandler = handler;
        [self goToState:self.backgroundFetchState];
    } else {
        handler(ZMBackgroundFetchResultNoData);
    }
}

- (void)startBackgroundTaskWithCompletionHandler:(ZMBackgroundTaskHandler)handler
{
    if (self.currentState.supportsBackgroundFetch) {
        self.backgroundTaskState.taskCompletionHandler = handler;
        [self goToState:self.backgroundTaskState];
    } else {
        handler(ZMBackgroundTaskResultUnavailable);
    }
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

- (void)didStartSlowSync
{
    for(id obj in self.directory.allTranscoders) {
        if ([obj conformsToProtocol:@protocol(ZMObjectStrategy)]) {
            [obj setNeedsSlowSync];
        }
    }
}

- (void)didInterruptUpdateEventsStream
{
    self.isUpdateEventStreamActive = NO;
    [self.currentState didRequestSynchronization];
}


- (void)didEstablishUpdateEventsStream
{
    self.isUpdateEventStreamActive = YES;
}

- (void)dataDidChange
{
    [self.currentState dataDidChange];
}

- (void)notifyEnteringEventProcessing
{
}

@end
