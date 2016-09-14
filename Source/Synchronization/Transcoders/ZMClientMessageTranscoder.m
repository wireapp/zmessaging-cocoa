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
@property (nonatomic, weak) BackgroundAPNSConfirmationStatus *apnsConfirmationStatus;

@end


@implementation ZMClientMessageTranscoder

- (instancetype)initWithManagedObjectContext:(NSManagedObjectContext *)moc
                 localNotificationDispatcher:(ZMLocalNotificationDispatcher *)dispatcher
                    clientRegistrationStatus:(ZMClientRegistrationStatus *)clientRegistrationStatus
                      apnsConfirmationStatus:(BackgroundAPNSConfirmationStatus *)apnsConfirmationStatus;
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
        self.apnsConfirmationStatus = apnsConfirmationStatus;
    }
    return self;
}

- (ZMTransportRequest *)requestForInsertingObject:(ZMClientMessage *)message
{
    ZMTransportRequest *request = [self.requestsFactory upstreamRequestForMessage:message forConversationWithId:message.conversation.remoteIdentifier];
    if ([message isKindOfClass:ZMClientMessage.class] && message.genericMessage.hasConfirmation && self.apnsConfirmationStatus.needsToSyncMessages) {
        [request forceToVoipSession]; // we might receive a message while in the background
    }
    return request;
}

- (void)updateInsertedObject:(ZMMessage *)message request:(ZMUpstreamRequest *)upstreamRequest response:(ZMTransportResponse *)response;
{
    [super updateInsertedObject:message request:upstreamRequest response:response];
    [(ZMClientMessage *)message parseUploadResponse:response clientDeletionDelegate:self.clientRegistrationStatus];
    
    // if it's reaction
    if ([message isKindOfClass:[ZMClientMessage class]]){
        ZMClientMessage *clientMessage = (id)message;
        if (clientMessage.genericMessage.hasReaction) {
            [message.managedObjectContext deleteObject:clientMessage];
        }
        if (clientMessage.genericMessage.hasConfirmation) {
            [self.apnsConfirmationStatus didConfirmMessage:clientMessage.nonce];
            [message.managedObjectContext deleteObject:clientMessage]; // we don't need the message anymore
        }
    }
}

- (BOOL)updateUpdatedObject:(ZMAssetClientMessage *)message requestUserInfo:(NSDictionary *)requestUserInfo response:(ZMTransportResponse *)response keysToParse:(NSSet *)keysToParse
{
    BOOL result = [super updateUpdatedObject:message requestUserInfo:requestUserInfo response:response keysToParse:keysToParse];
    
    [message parseUploadResponse:response clientDeletionDelegate:self.clientRegistrationStatus];
    
    return result;
}

- (BOOL)shouldRetryToSyncAfterFailedToUpdateObject:(ZMClientMessage *)message request:(ZMUpstreamRequest *__unused)upstreamRequest response:(ZMTransportResponse *)response keysToParse:(NSSet * __unused)keys
{
    return [message parseUploadResponse:response clientDeletionDelegate:self.clientRegistrationStatus];
}

- (ZMManagedObject *)dependentObjectNeedingUpdateBeforeProcessingObject:(ZMClientMessage *)message;
{
    return message.dependendObjectNeedingUpdateBeforeProcessing;
}

- (ZMMessage *)messageFromUpdateEvent:(ZMUpdateEvent *)event
                       prefetchResult:(ZMFetchRequestBatchResult *)prefetchResult
{
    MessageUpdateResult *updateResult;
    switch (event.type) {
        case ZMUpdateEventConversationClientMessageAdd:
        case ZMUpdateEventConversationOtrMessageAdd:
        case ZMUpdateEventConversationOtrAssetAdd:
            updateResult = [ZMOTRMessage messageUpdateResultFromUpdateEvent:event
                                                     inManagedObjectContext:self.managedObjectContext
                                                             prefetchResult:prefetchResult];
            if ([BackgroundAPNSConfirmationStatus sendDeliveryReceipts]) {
                if (updateResult.needsConfirmation) {
                    ZMClientMessage *confirmation = [updateResult.message confirmReception];
                    if (event.source == ZMUpdateEventSourcePushNotification) {
                        [self.apnsConfirmationStatus needsToConfirmMessage:confirmation.nonce];
                    }
                }
            }
            if (event.source == ZMUpdateEventSourcePushNotification &&
                (updateResult.wasInserted && updateResult.message != nil))
            {
                ZMGenericMessage *genericMessage = [ZMGenericMessage genericMessageFromUpdateEvent:event];
                if (genericMessage != nil) {
                    [self.localNotificationDispatcher processGenericMessage:genericMessage];
                }
                [self.localNotificationDispatcher processMessage:(ZMOTRMessage *)updateResult.message];
            }
            break;
        default:
            return nil;
    }
    
    [updateResult.message markAsSent];
    return updateResult.message;
}


@end
