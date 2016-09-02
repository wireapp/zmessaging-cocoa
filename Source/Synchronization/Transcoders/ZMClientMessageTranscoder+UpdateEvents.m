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


@import ZMProtos;
@import ZMTransport;
@import Cryptobox;
@import ZMCDataModel;

#import "ZMClientMessageTranscoder+UpdateEvents.h"
#import "ZMClientMessageTranscoder+Internal.h"
#import <zmessaging/zmessaging-Swift.h>


@interface ZMUpdateEventWithNonce : NSObject

@property (nonatomic) ZMUpdateEvent *event;
@property (nonatomic) NSUUID *nonce;

- (instancetype)initWithEvent:(ZMUpdateEvent *)event nonce:(NSUUID *)nonce;

@end


@implementation ZMUpdateEventWithNonce

- (instancetype)initWithEvent:(ZMUpdateEvent *)event nonce:(NSUUID *)nonce
{
    self = [super init];
    if (self) {
        self.event = event;
        self.nonce = nonce;
    }
    return self;
}

@end



@implementation ZMClientMessageTranscoder (UpdateEvents)

- (NSArray<ZMMessage *> *)createMessagesFromEvents:(NSArray<ZMUpdateEvent *> *)events
                                    prefetchResult:(ZMFetchRequestBatchResult *)prefetchResult
{
    NSMutableArray *createdMessages = [NSMutableArray array];
    for(ZMUpdateEvent* event in events) {
        ZMMessage *msg = [self messageFromUpdateEvent:event prefetchResult:prefetchResult];
        if(msg != nil) {
            [createdMessages addObject:msg];
        }
    }
    return createdMessages;
}

- (NSSet <NSUUID *>*)messageNoncesToPrefetchToProcessEvents:(NSArray<ZMUpdateEvent *> *)events
{
    NSArray <ZMUpdateEventWithNonce*>* genericMessageUpdateEvents = [self noncesForUpdateEvents:events];
    
    return [genericMessageUpdateEvents mapWithBlock:^NSUUID *(ZMUpdateEventWithNonce *eventWithNonce) {
        return eventWithNonce.nonce;
    }].set;
}

/// Returns an array of generic messages that are parsed from the given events
- (NSArray <ZMUpdateEventWithNonce*>*)noncesForUpdateEvents:(NSArray<ZMUpdateEvent *> *)events
{
    NSMutableArray *noncesForUpdateEvents = [NSMutableArray array];
    
    for (ZMUpdateEvent *event in events) {
        
        NSUUID *nonce;
        switch (event.type) {
            case ZMUpdateEventConversationClientMessageAdd:
            case ZMUpdateEventConversationOtrMessageAdd:
            case ZMUpdateEventConversationOtrAssetAdd:
                nonce = event.messageNonce;
                break;
                
            default:
                break;
        }
        
        if (nil != event && nil != nonce) {
            ZMUpdateEventWithNonce *tuple = [[ZMUpdateEventWithNonce alloc] initWithEvent:event nonce:nonce];
            [noncesForUpdateEvents addObject:tuple];
        }
    }
    
    return noncesForUpdateEvents;
}


@end
