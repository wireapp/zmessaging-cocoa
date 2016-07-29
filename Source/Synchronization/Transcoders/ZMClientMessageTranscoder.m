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

@import ZMCDataModel;

#import "ZMClientMessageTranscoder+Internal.h"
#import "ZMMessageTranscoder+Internal.h"
#import "ZMUpstreamInsertedObjectSync.h"
#import "ZMMessageExpirationTimer.h"
#import "ZMUpstreamTranscoder.h"

#import "ZMClientRegistrationStatus.h"
#import "ZMLocalNotificationDispatcher.h"

#import "CBCryptoBox+UpdateEvents.h"
#import <zmessaging/zmessaging-Swift.h>
#import "ZMOperationLoop.h"


@interface ZMClientMessageTranscoder()

@property (nonatomic) ClientMessageRequestFactory *requestsFactory;
@property (nonatomic, weak) ZMClientRegistrationStatus *clientRegistrationStatus;

@end


@implementation ZMClientMessageTranscoder

- (instancetype)initWithManagedObjectContext:(NSManagedObjectContext *)moc
                 localNotificationDispatcher:(ZMLocalNotificationDispatcher *)dispatcher
                    clientRegistrationStatus:(ZMClientRegistrationStatus *)clientRegistrationStatus;
{
    ZMUpstreamInsertedObjectSync *clientTextMessageUpstreamSync = [[ZMUpstreamInsertedObjectSync alloc] initWithTranscoder:self entityName:[ZMClientMessage entityName] filter:nil managedObjectContext:moc];
    ZMMessageExpirationTimer *messageTimer = [[ZMMessageExpirationTimer alloc] initWithManagedObjectContext:moc entityName:[ZMClientMessage entityName] localNotificationDispatcher:dispatcher filter:nil];
    
    self = [super initWithManagedObjectContext:moc
                    upstreamInsertedObjectSync:clientTextMessageUpstreamSync
                   localNotificationDispatcher:dispatcher
                        messageExpirationTimer:messageTimer];
    if (self) {
        self.requestsFactory = [ClientMessageRequestFactory new];
        self.clientRegistrationStatus = clientRegistrationStatus;
    }
    return self;
}

- (ZMTransportRequest *)requestForInsertingObject:(ZMClientMessage *)message
{
    ZMTransportRequest *request = [self.requestsFactory upstreamRequestForMessage:message forConversationWithId:message.conversation.remoteIdentifier];
    return request;
}

- (void)updateInsertedObject:(ZMMessage *)message request:(ZMUpstreamRequest *)upstreamRequest response:(ZMTransportResponse *)response;
{
    [super updateInsertedObject:message request:upstreamRequest response:response];
    [(ZMClientMessage *)message parseUploadResponse:response clientDeletionDelegate:self.clientRegistrationStatus];
}

- (ZMManagedObject *)dependentObjectNeedingUpdateBeforeProcessingObject:(ZMClientMessage *)message;
{
    return message.dependendObjectNeedingUpdateBeforeProcessing;
}

- (ZMMessage *)messageFromUpdateEvent:(ZMUpdateEvent *)event
                       prefetchResult:(ZMFetchRequestBatchResult *)prefetchResult
{
    CBCryptoBox *box = [self.managedObjectContext zm_cryptKeyStore].box;
    ZMUpdateEvent *decryptedEvent = [box decryptUpdateEventAndAddClient:event managedObjectContext:self.managedObjectContext];
    
    if (decryptedEvent == nil) {
        return nil;
    }
    
    ZMMessage *message;
    switch (event.type) {
        case ZMUpdateEventConversationClientMessageAdd:
        case ZMUpdateEventConversationOtrMessageAdd:
        case ZMUpdateEventConversationOtrAssetAdd:
            message = [ZMOTRMessage createOrUpdateMessageFromUpdateEvent:decryptedEvent
                                                  inManagedObjectContext:self.managedObjectContext
                                                          prefetchResult:prefetchResult];
            break;
        default:
            return nil;
    }
    
    [message markAsDelivered];
    return message;
}

@end
