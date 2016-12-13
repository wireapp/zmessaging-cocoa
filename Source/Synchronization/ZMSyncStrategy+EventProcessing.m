//
//  ZMSyncStrategy+EventProcessing.m
//  zmessaging-cocoa
//
//  Created by Sabine Geithner on 08/12/16.
//  Copyright © 2016 Zeta Project Gmbh. All rights reserved.
//

#import "ZMSyncStrategy+EventProcessing.h"
#import "ZMSyncStrategy+Internal.h"
#import "ZMSyncStateMachine.h"


@implementation ZMSyncStrategy (EventProcessing)

- (void)processUpdateEvents:(NSArray *)events ignoreBuffer:(BOOL)ignoreBuffer;
{
    if(ignoreBuffer) {
        [self consumeUpdateEvents:events];
        return;
    }
    
    NSArray *flowEvents = [events filterWithBlock:^BOOL(ZMUpdateEvent* event) {
        return event.isFlowEvent;
    }];
    if(flowEvents.count > 0) {
        [self consumeUpdateEvents:flowEvents];
    }
    NSArray *callstateEvents = [events filterWithBlock:^BOOL(ZMUpdateEvent* event) {
        return event.type == ZMUpdateEventCallState;
    }];
    NSArray *notFlowEvents = [events filterWithBlock:^BOOL(ZMUpdateEvent* event) {
        return !event.isFlowEvent;
    }];
    
    if (self.syncStatus.isSyncing) {
        for(ZMUpdateEvent *event in notFlowEvents) {
            [self.eventsBuffer addUpdateEvent:event];
        }
    }
    else {
        switch(self.stateMachine.updateEventsPolicy) {
            case ZMUpdateEventPolicyIgnore: {
                if(callstateEvents.count > 0) {
                    [self consumeUpdateEvents:callstateEvents];
                }
                break;
            }
            case ZMUpdateEventPolicyBuffer: {
                for(ZMUpdateEvent *event in notFlowEvents) {
                    [self.eventsBuffer addUpdateEvent:event];
                }
                break;
            }
            case ZMUpdateEventPolicyProcess: {
                if(notFlowEvents.count > 0) {
                    [self consumeUpdateEvents:notFlowEvents];
                }
                break;
            }
        }
    }
}

- (void)consumeUpdateEvents:(NSArray<ZMUpdateEvent *>*)events
{
    ZM_WEAK(self);
    [self.eventDecoder processEvents:events block:^(NSArray<ZMUpdateEvent *> * decryptedEvents) {
        ZM_STRONG(self);
        if (self == nil){
            return;
        }
        
        ZMFetchRequestBatch *fetchRequest = [self fetchRequestBatchForEvents:decryptedEvents];
        ZMFetchRequestBatchResult *prefetchResult = [self.syncMOC executeFetchRequestBatchOrAssert:fetchRequest];
        NSArray *allObjectStrategies = [self.allTranscoders arrayByAddingObjectsFromArray:self.requestStrategies];
        
        for(id obj in allObjectStrategies) {
            @autoreleasepool {
                if ([obj conformsToProtocol:@protocol(ZMEventConsumer)]) {
                    [obj processEvents:decryptedEvents liveEvents:YES prefetchResult:prefetchResult];
                }
            }
        }
        [self.localNotificationDispatcher processEvents:decryptedEvents liveEvents:YES prefetchResult:nil];
        [self.syncMOC enqueueDelayedSave];
    }];
}

- (void)processDownloadedEvents:(NSArray <ZMUpdateEvent *>*)events;
{
    ZM_WEAK(self);
    [self.eventDecoder processEvents:events block:^(NSArray<ZMUpdateEvent *> * decryptedEvents) {
        ZM_STRONG(self);
        if (self  == nil){
            return;
        }
        
        ZMFetchRequestBatch *fetchRequest = [self fetchRequestBatchForEvents:decryptedEvents];
        ZMFetchRequestBatchResult *prefetchResult = [self.moc executeFetchRequestBatchOrAssert:fetchRequest];
        
        NSArray *allEventConsumers = [self.allTranscoders arrayByAddingObjectsFromArray:self.requestStrategies];
        for(id<ZMEventConsumer> obj in allEventConsumers) {
            @autoreleasepool {
                if ([obj conformsToProtocol:@protocol(ZMEventConsumer)]) {
                    ZMSTimePoint *tp = [ZMSTimePoint timePointWithInterval:5 label:[NSString stringWithFormat:@"Processing downloaded events in %@", [obj class]]];
                    [obj processEvents:decryptedEvents liveEvents:NO prefetchResult:prefetchResult];
                    [tp warnIfLongerThanInterval];
                }
            }
        }
    }];
}

- (NSArray *)conversationIdsThatHaveBufferedUpdatesForCallState;
{
    return [[self.eventsBuffer updateEvents] mapWithBlock:^id(ZMUpdateEvent *event) {
        if (event.type == ZMUpdateEventCallState) {
            return event.conversationUUID;
        }
        return nil;
    }];
}

@end
