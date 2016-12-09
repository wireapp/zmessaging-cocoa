//
//  ZMSyncStrategy+EventProcessing.h
//  zmessaging-cocoa
//
//  Created by Sabine Geithner on 08/12/16.
//  Copyright © 2016 Zeta Project Gmbh. All rights reserved.
//

#import "ZMSyncStrategy.h"

@interface ZMSyncStrategy (EventProcessing) <ZMUpdateEventConsumer>

/// Process events that are recevied through the notification stream or the websocket
- (void)processUpdateEvents:(NSArray <ZMUpdateEvent *>*)events ignoreBuffer:(BOOL)ignoreBuffer;

/// Process events that were downloaded as part of the clinet history
- (void)processDownloadedEvents:(NSArray <ZMUpdateEvent *>*)events;


- (NSArray *)conversationIdsThatHaveBufferedUpdatesForCallState;

@end
