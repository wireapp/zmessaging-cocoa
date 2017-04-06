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

@import WireRequestStrategy;

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
    
    if (self.applicationStatusDirectory.syncStatus.isSyncing) {
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
        
        for(id obj in self.eventConsumers) {
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

- (NSArray *)eventConsumers {
    return [[self.allTranscoders arrayByAddingObjectsFromArray:self.requestStrategies]
            arrayByAddingObject:self.systemMessageEventConsumer];
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
