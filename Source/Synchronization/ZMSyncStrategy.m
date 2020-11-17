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


@import UIKit;
@import WireImages;
@import WireUtilities;
@import WireTransport;
@import WireDataModel;
@import WireRequestStrategy;

#import "ZMSyncStrategy+Internal.h"
#import "ZMSyncStrategy+ManagedObjectChanges.h"
#import "WireSyncEngineLogs.h"
#import "ZMClientRegistrationStatus.h"
#import "ZMHotFix.h"
#import <WireSyncEngine/WireSyncEngine-Swift.h>

@interface ZMSyncStrategy ()

@property (nonatomic) BOOL didFetchObjects;
@property (nonatomic) NSManagedObjectContext *syncMOC;
@property (nonatomic, weak) NSManagedObjectContext *uiMOC;

@property (nonatomic) id<ZMApplication> application;

@property (nonatomic) ZMUpdateEventsBuffer *eventsBuffer;
@property (nonatomic) ZMChangeTrackerBootstrap *changeTrackerBootStrap;

@property (nonatomic, readwrite) CallingRequestStrategy *callingRequestStrategy;

@property (nonatomic) NSManagedObjectContext *eventMOC;
@property (nonatomic) EventDecoder *eventDecoder;

@property (nonatomic, weak) ApplicationStatusDirectory *applicationStatusDirectory;
@property (nonatomic) NSArray *allChangeTrackers;

@property (nonatomic) NSArray *strategies;
@property (nonatomic) NSArray<ZMObjectSyncStrategy *> *requestStrategies;
@property (nonatomic) NSArray<id<ZMEventConsumer>> *eventConsumers;

@property (atomic) BOOL tornDown;
@property (nonatomic) BOOL contextMergingDisabled;

@property (nonatomic) ZMHotFix *hotFix;
@property (nonatomic) NotificationDispatcher *notificationDispatcher;

@end


@interface ZMSyncStrategy (Registration) <ZMClientRegistrationStatusDelegate>
@end

@interface ZMClientRegistrationStatus (Protocol) <ClientRegistrationDelegate>
@end


@implementation ZMSyncStrategy

ZM_EMPTY_ASSERTING_INIT()


- (instancetype)initWithStoreProvider:(id<LocalStoreProviderProtocol>)storeProvider
              notificationsDispatcher:(NotificationDispatcher *)notificationsDispatcher
           applicationStatusDirectory:(ApplicationStatusDirectory *)applicationStatusDirectory
                          application:(id<ZMApplication>)application
               requestStrategyFactory:(id<RequestStrategyFactoryProtocol>)requestStrategyFactory
{
    self = [super init];
    if (self) {
        self.notificationDispatcher = notificationsDispatcher;
        self.application = application;
        self.syncMOC = storeProvider.contextDirectory.syncContext;
        self.uiMOC = storeProvider.contextDirectory.uiContext;
        self.hotFix = [[ZMHotFix alloc] initWithSyncMOC:self.syncMOC];
        self.eventProcessingTracker = [[EventProcessingTracker alloc] init];

        self.eventMOC = [NSManagedObjectContext createEventContextWithSharedContainerURL:storeProvider.applicationContainer userIdentifier:storeProvider.userIdentifier];
        [self.eventMOC addGroup:self.syncMOC.dispatchGroup];
        self.applicationStatusDirectory = applicationStatusDirectory;

        self.eventDecoder = [[EventDecoder alloc] initWithEventMOC:self.eventMOC syncMOC:self.syncMOC];
        self.eventsBuffer = [[ZMUpdateEventsBuffer alloc] initWithUpdateEventProcessor:self];
        self.strategies = [requestStrategyFactory buildStrategies];
        self.changeTrackerBootStrap = [[ZMChangeTrackerBootstrap alloc] initWithManagedObjectContext:self.syncMOC changeTrackers:self.allChangeTrackers];

        ZM_ALLOW_MISSING_SELECTOR([[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(managedObjectContextDidSave:) name:NSManagedObjectContextDidSaveNotification object:self.syncMOC]);
        ZM_ALLOW_MISSING_SELECTOR([[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(managedObjectContextDidSave:) name:NSManagedObjectContextDidSaveNotification object:storeProvider.contextDirectory.uiContext]);

        [application registerObserverForDidEnterBackground:self selector:@selector(appDidEnterBackground:)];
        [application registerObserverForWillEnterForeground:self selector:@selector(appWillEnterForeground:)];
        [application registerObserverForApplicationWillTerminate:self selector:@selector(appTerminated:)];
    }
    return self;
}

- (void)appDidEnterBackground:(NSNotification *)note
{
    NOT_USED(note);
    BackgroundActivity *activity = [BackgroundActivityFactory.sharedFactory startBackgroundActivityWithName:@"enter background"];
    [self.notificationDispatcher applicationDidEnterBackground];
    [self.syncMOC performGroupedBlock:^{
        self.applicationStatusDirectory.operationStatus.isInBackground = YES;
        [ZMRequestAvailableNotification notifyNewRequestsAvailable:self];

        if (activity) {
            [BackgroundActivityFactory.sharedFactory endBackgroundActivity:activity];
        }
    }];
}

- (void)appWillEnterForeground:(NSNotification *)note
{
    NOT_USED(note);
    BackgroundActivity *activity = [BackgroundActivityFactory.sharedFactory startBackgroundActivityWithName:@"enter foreground"];
    [self.notificationDispatcher applicationWillEnterForeground];
    [self.syncMOC performGroupedBlock:^{
        self.applicationStatusDirectory.operationStatus.isInBackground = NO;
        [ZMRequestAvailableNotification notifyNewRequestsAvailable:self];

        if (activity) {
            [BackgroundActivityFactory.sharedFactory endBackgroundActivity:activity];
        }
    }];
}

- (void)appTerminated:(NSNotification *)note
{
    NOT_USED(note);
    [self.application unregisterObserverForStateChange:self];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (NSManagedObjectContext *)moc
{
    return self.syncMOC;
}

- (void)didEstablishUpdateEventsStream
{
    [self.applicationStatusDirectory.syncStatus pushChannelDidOpen];
}

- (void)didInterruptUpdateEventsStream
{
    [self.applicationStatusDirectory.syncStatus pushChannelDidClose];
}

- (void)applyHotFixes
{
    [self.hotFix applyPatches];
}

- (BOOL)isReadyToProcessEvents
{
    return !self.applicationStatusDirectory.syncStatus.isSyncing;
}

- (void)tearDown
{
    self.tornDown = YES;
    self.applicationStatusDirectory = nil;
    self.changeTrackerBootStrap = nil;
    self.callingRequestStrategy = nil;
    self.eventsBuffer = nil;
    self.allChangeTrackers = nil;
    self.eventDecoder = nil;
    [self.eventMOC performGroupedBlockAndWait:^{
        [self.eventMOC tearDownEventMOC];
    }];
    self.eventMOC = nil;
    [self.application unregisterObserverForStateChange:self];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self appTerminated:nil];

    @autoreleasepool {
        for (id strategy in self.strategies) {
            if ([strategy respondsToSelector:@selector((tearDown))]) {
                [strategy tearDown];
            }
        }
    }
    self.strategies = nil;
    self.requestStrategies = nil;
    [self.notificationDispatcher tearDown];
}

- (void)processAllEventsInBuffer
{
    [self.eventsBuffer processAllEventsInBuffer];
}


#if DEBUG
- (void)dealloc
{
    RequireString(self.tornDown, "Did not tear down %p", (__bridge void *) self);
}
#endif

- (CallingRequestStrategy *)callingRequestStrategy{
    return [self.requestStrategies firstObjectMatchingWithBlock:^BOOL(id obj) {
        if ([obj isKindOfClass:CallingRequestStrategy.self]) {
            return YES;
        }
        
        return NO;
    }];
}

- (ZMMissingUpdateEventsTranscoder *)missingUpdateEventsTranscoder{
    return [self.requestStrategies firstObjectMatchingWithBlock:^BOOL(id obj) {
        if ([obj isKindOfClass:ZMMissingUpdateEventsTranscoder.self]) {
            return YES;
        }
        
        return NO;
    }];
}

- (NSArray *)requestStrategies
{
    if (_requestStrategies == nil) {
        _requestStrategies = [self.strategies filterWithBlock:^BOOL(id strategy) {
            return [strategy respondsToSelector:@selector(nextRequest)];
        
        }];
    }

    return _requestStrategies;
}

- (NSArray *)allChangeTrackers
{
    if (_allChangeTrackers == nil) {
        _allChangeTrackers = [self.strategies flattenWithBlock:^NSArray *(id <ZMObjectStrategy> objectSync) {
            if ([objectSync conformsToProtocol:@protocol(ZMContextChangeTrackerSource)]) {
                return objectSync.contextChangeTrackers;
            } else if ([objectSync conformsToProtocol:@protocol(ZMContextChangeTracker)]) {
                return @[objectSync];
            }
            return nil;
        }];
    }

    return _allChangeTrackers;
}

- (NSArray<id<ZMEventConsumer>> *)eventConsumers
{
    if (_eventConsumers == nil) {
        NSMutableArray<id<ZMEventConsumer>> *eventConsumers = [NSMutableArray array];
        
        for (id<ZMObjectStrategy> objectStrategy in self.strategies) {
            if ([objectStrategy conformsToProtocol:@protocol(ZMEventConsumer)]) {
                [eventConsumers addObject:objectStrategy];
            }
        }
                
        _eventConsumers = eventConsumers;
    }

    return _eventConsumers;
}

- (ZMTransportRequest *)nextRequest
{
    if (!self.didFetchObjects) {
        self.didFetchObjects = YES;
        [self.changeTrackerBootStrap fetchObjectsForChangeTrackers];
    }

    if(self.tornDown) {
        return nil;
    }

    return [self.requestStrategies firstNonNilReturnedFromSelector:@selector(nextRequest)];
}

@end
