//
// Wire
// Copyright (C) 2017 Wire Swiss GmbH
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
#import <WireSyncEngine/WireSyncEngine-Swift.h>

@implementation ZMSyncStrategy (EventProcessing)

- (void)processUpdateEvents:(NSArray *)events ignoreBuffer:(BOOL)ignoreBuffer;
{
    if (ignoreBuffer || !self.applicationStatusDirectory.syncStatus.isSyncing) {
        [self consumeUpdateEvents:events];
        return;
    }
    
    for (ZMUpdateEvent *event in events) {
        [self.eventsBuffer addUpdateEvent:event];
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
        
        for (id<ZMEventConsumer> eventConsumer in self.eventConsumers) {
            @autoreleasepool {
                [eventConsumer processEvents:decryptedEvents liveEvents:YES prefetchResult:prefetchResult];
            }
        }
        LocalNotificationDispatcher *dispatcher = self.localNotificationDispatcher;
        [dispatcher processEvents:decryptedEvents liveEvents:YES prefetchResult:nil];
        [self.syncMOC enqueueDelayedSave];
    }];
}

@end
