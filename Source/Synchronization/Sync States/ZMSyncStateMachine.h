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


@import Foundation;
@import WireTransport;

#import "ZMStateMachineDelegate.h"
#import "ZMBackgroundFetch.h"

@class ZMAuthenticationStatus;
@class ZMTransportRequest;
@class ZMSyncState;
@class ZMClientRegistrationStatus;
@protocol ZMObjectStrategyDirectory;
@protocol ZMSyncStateDelegate;
@class ZMTransportSession;
@protocol ZMBackgroundable;
@protocol HistorySynchronizationStatus;
@protocol ZMApplication;

@interface ZMSyncStateMachine : NSObject <ZMStateMachineDelegate, ZMBackgroundable>

@property (nonatomic, readonly) ZMUpdateEventsPolicy updateEventsPolicy;

- (instancetype)initWithAuthenticationStatus:(ZMAuthenticationStatus *)authenticationStatus
                    clientRegistrationStatus:(ZMClientRegistrationStatus *)clientRegistrationStatus
                     objectStrategyDirectory:(id<ZMObjectStrategyDirectory>)objectStrategyDirectory
                           syncStateDelegate:(id<ZMSyncStateDelegate>)syncStateDelegate
                       backgroundableSession:(id<ZMBackgroundable>)backgroundableSession
                                 application:(id<ZMApplication>)application;

- (ZMTransportRequest *)nextRequest;

- (void)didEstablishUpdateEventsStream;
- (void)didInterruptUpdateEventsStream;
- (void)didStartSlowSync;
- (void)didFailAuthentication;

///called at the beginning of event processing loop if something in data model could change and context was saved
- (void)dataDidChange;

- (void)startBackgroundFetchWithCompletionHandler:(ZMBackgroundFetchHandler)handler;
- (void)startBackgroundTaskWithCompletionHandler:(ZMBackgroundTaskHandler)handler;

- (void)tearDown;

@end
