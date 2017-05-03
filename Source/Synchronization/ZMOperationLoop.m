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


@import WireUtilities;
@import WireSystem;
@import WireTransport;
@import WireCryptobox;
@import WireDataModel;

#import "ZMOperationLoop+Private.h"
#import "ZMSyncStrategy+ManagedObjectChanges.h"
#import "ZMSyncStrategy+EventProcessing.h"

#import "ZMUserTranscoder.h"
#import "ZMUserSession.h"
#import <libkern/OSAtomic.h>
#import <os/activity.h>
#import "WireSyncEngineLogs.h"
#import <WireSyncEngine/WireSyncEngine-Swift.h>

NSString * const ZMPushChannelStateChangeNotificationName = @"ZMPushChannelStateChangeNotification";
NSString * const ZMPushChannelIsOpenKey = @"pushChannelIsOpen";
NSString * const ZMPushChannelResponseStatusKey = @"responseStatus";

static char* const ZMLogTag ZM_UNUSED = "OperationLoop";


@interface ZMOperationLoop ()
{
    int32_t _pendingEnqueueNextCount;
}

@property (nonatomic) NSNotificationQueue *enqueueNotificationQueue;
@property (nonatomic) ZMTransportSession *transportSession;
@property (atomic) BOOL shouldStopEnqueueing;
@property (nonatomic) BOOL ownsSyncStrategy;
@property (nonatomic) BOOL tornDown;
@property (nonatomic) id<ZMApplication> application;

@end


@interface ZMOperationLoop (ZMPushChannel) <ZMPushChannelConsumer>
@end


@interface ZMOperationLoop (NewRequests) <ZMRequestAvailableObserver>
@end


@interface ZMOperationLoop (OperationStatus) <ZMOperationStatusDelegate>
@end


@implementation ZMOperationLoop

- (instancetype)initWithTransportSession:(ZMTransportSession *)transportSession
                                  cookie:(ZMCookie *)cookie
             localNotificationdispatcher:(LocalNotificationDispatcher *)dispatcher
                            mediaManager:(id<AVSMediaManager>)mediaManager
                     onDemandFlowManager:(ZMOnDemandFlowManager *)onDemandFlowManager
                                   uiMOC:(NSManagedObjectContext *)uiMOC
                                 syncMOC:(NSManagedObjectContext *)syncMOC
                       syncStateDelegate:(id<ZMSyncStateDelegate>)syncStateDelegate
                      appGroupIdentifier:(NSString *)appGroupIdentifier
                             application:(id<ZMApplication>)application;
{

    ZMSyncStrategy *syncStrategy = [[ZMSyncStrategy alloc] initWithSyncManagedObjectContextMOC:syncMOC
                                                                        uiManagedObjectContext:uiMOC
                                                                                        cookie:cookie
                                                                                  mediaManager:mediaManager
                                                                           onDemandFlowManager:onDemandFlowManager
                                                                             syncStateDelegate:syncStateDelegate
                                                                  localNotificationsDispatcher:dispatcher
                                                                      taskCancellationProvider:transportSession
                                                                            appGroupIdentifier:appGroupIdentifier
                                                                                   application:application];
    
    self = [self initWithTransportSession:transportSession
                             syncStrategy:syncStrategy
                                    uiMOC:uiMOC
                                  syncMOC:syncMOC];
    self.application = application;
    self.ownsSyncStrategy = YES;
    return self;
}


- (instancetype)initWithTransportSession:(ZMTransportSession *)transportSession
                            syncStrategy:(ZMSyncStrategy *)syncStrategy
                                   uiMOC:(NSManagedObjectContext *)uiMOC
                                 syncMOC:(NSManagedObjectContext *)syncMOC
{
    Check(uiMOC != nil);
    Check(syncMOC != nil);
    
    self = [super init];
    if (self) {
        self.transportSession = transportSession;
        self.syncStrategy = syncStrategy;
        self.syncMOC = syncMOC;
        self.shouldStopEnqueueing = NO;
        self.syncStrategy.applicationStatusDirectory.operationStatus.delegate = self;

        if (uiMOC != nil) {
            [[NSNotificationCenter defaultCenter] addObserver:self
                                                     selector:@selector(userInterfaceContextDidSave:)
                                                         name:NSManagedObjectContextDidSaveNotification
                                                       object:uiMOC];
        }
        if (syncMOC != nil) {
            [[NSNotificationCenter defaultCenter] addObserver:self
                                                     selector:@selector(syncContextDidSave:)
                                                         name:NSManagedObjectContextDidSaveNotification
                                                       object:syncMOC];
        }
        
        [ZMRequestAvailableNotification addObserver:self];
        
        // this is needed to avoid loading from syncMOC on the main queue
        [self.syncMOC performGroupedBlock:^{
            [self.transportSession configurePushChannelWithConsumer:self groupQueue:self.syncMOC];
            [self.transportSession.pushChannel setKeepOpen:syncStrategy.applicationStatusDirectory.operationStatus.operationState == SyncEngineOperationStateForeground];
        }];
    }

    return self;
}

- (void)tearDown;
{
    self.tornDown = YES;
    self.shouldStopEnqueueing = true;
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [ZMRequestAvailableNotification removeObserver:self];
    
    ZMSyncStrategy *strategy = self.syncStrategy;
    self.syncStrategy = nil;
    if(self.ownsSyncStrategy) {
        [strategy tearDown];
    }
    
    RequireString([NSOperationQueue mainQueue] == [NSOperationQueue currentQueue],
                  "Must call be called on the main queue.");
    __block BOOL didStop = NO;
    [self.syncMOC.dispatchGroup notifyOnQueue:dispatch_get_main_queue() block:^{
        didStop = YES;
    }];
    while (!didStop) {
        if (! [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.002]]) {
            [NSThread sleepForTimeInterval:0.002];
        }
    }
}

#if DEBUG
- (void)dealloc
{
    RequireString(self.tornDown, "Did not call tearDown %p", (__bridge void *) self);
}
#endif


- (APSSignalingKeysStore *)apsSignalKeyStore
{
    if (_apsSignalKeyStore == nil) {
        ZMUser *selfUser = [ZMUser selfUserInContext:self.syncMOC];
        if (selfUser.selfClient != nil) {
            _apsSignalKeyStore = [[APSSignalingKeysStore alloc] initWithUserClient:selfUser.selfClient];
        }
    }
    return _apsSignalKeyStore;
}

+ (NSSet *)objectIDsetFromObject:(NSSet *)objects
{
    NSMutableSet *objectIds = [NSMutableSet set];
    for(NSManagedObject* obj in objects) {
        [objectIds addObject:obj.objectID];
    }
    return objectIds;
}

+ (NSSet *)objectSetFromObjectIDs:(NSSet *)objectIDs inContext:(NSManagedObjectContext *)moc
{
    NSMutableSet *objects = [NSMutableSet set];
    for(NSManagedObjectID *objId in objectIDs) {
        NSManagedObject *obj = [moc objectWithID:objId];
        if(obj) {
            [objects addObject:obj];
        }
    }
    return objects;
}

- (void)userInterfaceContextDidSave:(NSNotification *)note
{
    NSSet *insertedObjectsIDs = [ZMOperationLoop objectIDsetFromObject:note.userInfo[NSInsertedObjectsKey]];
    NSSet *updatedObjectsIDs = [ZMOperationLoop objectIDsetFromObject:note.userInfo[NSUpdatedObjectsKey]];
    
    // We need to proceed even if those to sets are empty because the metadata might have been updated.
    
    ZM_WEAK(self);
    [self.syncMOC performGroupedBlock:^{
        ZM_STRONG(self);
        NSSet *syncInsertedObjects = [ZMOperationLoop objectSetFromObjectIDs:insertedObjectsIDs inContext:self.syncStrategy.syncMOC];
        NSSet *syncUpdatedObjects = [ZMOperationLoop objectSetFromObjectIDs:updatedObjectsIDs inContext:self.syncStrategy.syncMOC];
        
        [self.syncStrategy processSaveWithInsertedObjects:syncInsertedObjects updateObjects:syncUpdatedObjects];
        [ZMRequestAvailableNotification notifyNewRequestsAvailable:self];
    }];
}

- (void)syncContextDidSave:(NSNotification *)note
{
    //
    // N.B.: We don't need to do any context / queue switching here, since we're on the sync context's queue.
    //
    
    NSSet *syncInsertedObjects = note.userInfo[NSInsertedObjectsKey];
    NSSet *syncUpdatedObjects = note.userInfo[NSUpdatedObjectsKey];
    
    if (syncInsertedObjects.count == 0 && syncUpdatedObjects.count == 0) {
        return;
    }
    
    [self.syncStrategy processSaveWithInsertedObjects:syncInsertedObjects updateObjects:syncUpdatedObjects];
    [ZMRequestAvailableNotification notifyNewRequestsAvailable:self];
}

- (ZMTransportRequestGenerator)requestGenerator {
    
    ZM_WEAK(self);
    return ^ZMTransportRequest *(void) {
        ZM_STRONG(self);
        if (self == nil) {
            return nil;
        }
        
        ZMStartActivity("Generating next request");
        ZMTransportRequest *request = [self.syncStrategy nextRequest];
        [request addCompletionHandler:[ZMCompletionHandler handlerOnGroupQueue:self.syncMOC block:^(ZMTransportResponse *response) {
            ZM_STRONG(self);
            
            [self.syncStrategy.syncMOC enqueueDelayedSaveWithGroup:response.dispatchGroup];
            
            // Check if there is something to do now and when the save completes
            [ZMRequestAvailableNotification notifyNewRequestsAvailable:self];
            
            [self.syncStrategy.syncMOC.dispatchGroup notifyOnQueue:dispatch_get_global_queue(0, 0) block:^{
                [ZMRequestAvailableNotification notifyNewRequestsAvailable:self];
            }];
        }]];
        
        return request;
    };
    
}

- (void)executeNextOperation
{    
    if (self.shouldStopEnqueueing) {
        return;
    }
    
    // this generates the request
    ZMTransportRequestGenerator generator = [self requestGenerator];
    
    ZMBackgroundActivity * const enqueueActivity = [[BackgroundActivityFactory sharedInstance] backgroundActivityWithName:@"executeNextOperation"];
    ZM_WEAK(self);
    [self.syncMOC performGroupedBlock:^{
        ZM_STRONG(self);
        BOOL enqueueMore = YES;
        while (self && enqueueMore && !self.shouldStopEnqueueing) {
            ZMTransportEnqueueResult *result = [self.transportSession attemptToEnqueueSyncRequestWithGenerator:generator];
            enqueueMore = result.didGenerateNonNullRequest && result.didHaveLessRequestThanMax;
        }
        [enqueueActivity endActivity];
    }];
}

- (void)accessTokenDidChangeWithToken:(NSString *)token ofType:(NSString *)type;
{
    [self.syncStrategy transportSessionAccessTokenDidSucceedWithToken:token ofType:type];
}

- (BackgroundAPNSPingBackStatus *)backgroundAPNSPingBackStatus
{
    return self.syncStrategy.applicationStatusDirectory.pingBackStatus;
}

@end


@implementation ZMOperationLoop (NewRequests)

- (void)newRequestsAvailable
{
    [self executeNextOperation];
}

@end


@implementation ZMOperationLoop (ZMPushChannel)

- (void)pushChannel:(ZMPushChannelConnection *)channel didReceiveTransportData:(id<ZMTransportData>)data;
{
    NOT_USED(channel);
    
    ZMLogWithLevelAndTag(ZMLogLevelInfo, ZMTAG_NETWORK, @"---> Push channel: %@", data);
    
    NSArray *events = [ZMUpdateEvent eventsArrayFromPushChannelData:data];
    
    for(ZMUpdateEvent *event in events) {
        [event appendDebugInformation:@"From push channel (web socket)"];
    }
    
    if(events.count > 0u) {
        [self.syncStrategy processUpdateEvents:events ignoreBuffer:NO];
    }
}

- (void)pushChannelDidClose:(ZMPushChannelConnection *)channel withResponse:(NSHTTPURLResponse *)response;
{
    NOT_USED(response);
    [[NSNotificationCenter defaultCenter] postNotificationName:ZMPushChannelStateChangeNotificationName object:self userInfo:@{ZMPushChannelIsOpenKey : @(NO), ZMPushChannelResponseStatusKey : @(response.statusCode)}];
    [self.syncStrategy didInterruptUpdateEventsStream];
    [ZMRequestAvailableNotification notifyNewRequestsAvailable:channel];
}

- (void)pushChannelDidOpen:(ZMPushChannelConnection *)channel withResponse:(NSHTTPURLResponse *)response;
{
    [[NSNotificationCenter defaultCenter] postNotificationName:ZMPushChannelStateChangeNotificationName object:self userInfo:@{ZMPushChannelIsOpenKey : @(YES), ZMPushChannelResponseStatusKey : @(response.statusCode)}];
    [self.syncStrategy didEstablishUpdateEventsStream];
    [ZMRequestAvailableNotification notifyNewRequestsAvailable:channel];
}

@end

@implementation ZMOperationLoop (OperationStatus)

- (void)operationStatusDidChangeState:(enum SyncEngineOperationState)state
{
    self.transportSession.pushChannel.keepOpen = state == SyncEngineOperationStateForeground || state == SyncEngineOperationStateBackgroundCall;
}

@end
