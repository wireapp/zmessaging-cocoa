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


@import ZMTransport;
@import Cryptobox;

#import "ZMOperationLoop+Background.h"
#import "ZMOperationLoop+Private.h"

#import "ZMLocalNotificationDispatcher.h"
#import "ZMSyncStrategy+Internal.h"
#import <zmessaging/zmessaging-Swift.h>

static char* const ZMLogTag ZM_UNUSED = "Network";


static NSString * const PushChannelDataKey = @"data";
static NSString * const PushChannelIdentifierKey = @"id";
static NSString * const PushChannelNotificationTypeKey = @"type";

static NSString * const PushNotificationTypeCipher = @"cipher";
static NSString * const PushNotificationTypeNotice = @"notice";



@implementation ZMOperationLoop (Background)


- (void)saveEventsAndSendNotificationForPayload:(NSDictionary *)payload fetchCompletionHandler:(ZMPushResultHandler)completionHandler source:(ZMPushNotficationType)source;
{
    ZMLogDebug(@"----> Received push notification payload: %@, source: %lu", payload, (unsigned long)source);
    ZMBackgroundActivity *activity = [[BackgroundActivityFactory sharedInstance] backgroundActivityWithName:@"send notification for payload"];
    [self.syncMOC performGroupedBlock:^{
        
        EventsWithIdentifier *eventsWithID = [self eventsFromPushChannelData:payload];
        NSArray <ZMUpdateEvent *>*events = eventsWithID.events;
        NSArray <NSUUID *>* preexistingMessageNonces = [self fetchPreexistingMessageNoncesForEvents:events];
        EventsWithIdentifier *filteredEventsWithIdentifier = [eventsWithID filteredWithoutPreexistingNonces:preexistingMessageNonces];
        
        if (events.count > 0) {
            [self forwardEvents:events];
            
            if (source == ZMPushNotficationTypeVoIP && nil != eventsWithID.identifier) {
                [APNSPerformanceTracker trackVOIPNotificationInOperationLoop:eventsWithID analytics:self.syncMOC.analytics];
                
                ZM_WEAK(self);
                [self.backgroundAPNSPingBackStatus didReceiveVoIPNotification:filteredEventsWithIdentifier handler:^(ZMPushPayloadResult result, NSArray<ZMUpdateEvent *> *receivedEvents) {
                    NOT_USED(receivedEvents);
                    ZM_STRONG(self);
                    if (completionHandler != nil) {
                        [self.syncMOC.dispatchGroup notifyOnQueue:dispatch_get_main_queue() block:^{
                            ZMLogPushKit(@"Calling CompletionHandler");
                            completionHandler(result);
                        }];
                    }
                }];
            }
            
            [activity endActivity];
        } else if (filteredEventsWithIdentifier.isNotice && source == ZMPushNotficationTypeVoIP && nil != eventsWithID.identifier) {
            ZM_WEAK(self);
            [APNSPerformanceTracker trackVOIPNotificationInOperationLoop:eventsWithID analytics:self.syncMOC.analytics];
            [self.backgroundAPNSPingBackStatus didReceiveVoIPNotification:filteredEventsWithIdentifier handler:^(ZMPushPayloadResult result, NSArray<ZMUpdateEvent *> *receivedEvents) {
                ZM_STRONG(self);
                [self forwardEvents:receivedEvents];
                if (completionHandler != nil) {
                    [self.syncMOC.dispatchGroup notifyOnQueue:dispatch_get_main_queue() block:^{
                        ZMLogPushKit(@"Calling CompletionHandler");
                        completionHandler(result);
                    }];
                }
            }];
        }
        else if (completionHandler != nil) {
            [APNSPerformanceTracker trackVOIPNotificationInOperationLoopNotCreatingNotification:self.syncMOC.analytics];
            ZMLogPushKit(@"ZMOperationLoop - calling completionHandler without creating notifications");
            [self.syncMOC.dispatchGroup notifyOnQueue:dispatch_get_main_queue() block:^{
                completionHandler(ZMPushPayloadResultSuccess);
                [activity endActivity];
            }]; 
        }
    }];
}

- (NSArray <NSUUID *> *)fetchPreexistingMessageNoncesForEvents:(NSArray <ZMUpdateEvent *>*)events
{
    NSArray <NSData *>* messageNonces = [events mapWithBlock:^NSData *(ZMUpdateEvent *event) {
        return event.messageNonce.data;
    }];
    
    if (messageNonces.count == 0) {
        return @[];
    }
    
    NSPredicate *noncesPredicate = [NSPredicate predicateWithFormat:@"%K IN %@", ZMMessageNonceDataKey, messageNonces];
    NSFetchRequest *messageRequest = [ZMMessage sortedFetchRequestWithPredicate:noncesPredicate];
    NSArray <ZMMessage *>* preexistingMessages = [self.syncMOC executeFetchRequestOrAssert:messageRequest];
    NSArray <NSUUID *>* preexistingNonces = [preexistingMessages mapWithBlock:^NSUUID *(ZMMessage *message) {
        return message.nonce;
    }];
    
    return preexistingNonces;
}

- (void)forwardEvents:(NSArray *)events
{
    if (events.count == 0) {
        return;
    }
    
    NSArray *nonFlowEvents = [events filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(ZMUpdateEvent *event, NSDictionary<NSString *,id> * _Nullable ZM_UNUSED bindings) {
        return !event.isFlowEvent;
    }]];
                              
    [self.syncStrategy consumeUpdateEvents:nonFlowEvents];
    [self.syncMOC saveOrRollback];
    [self.syncStrategy updateBadgeCount];
    [ZMOperationLoop notifyNewRequestsAvailable:self];
}

- (EventsWithIdentifier *)eventsFromPushChannelData:(NSDictionary *)userInfo
{
    NSDictionary *userInfoData = [userInfo optionalDictionaryForKey:PushChannelDataKey];
    if (userInfoData == nil) {
        ZMLogError(@"No data dictionary in notification userInfo payload");
        return nil;
    }
    
    NSArray <ZMUpdateEvent *>* events;
    NSUUID *identifier;
    
    id internalData = userInfoData[PushChannelDataKey];
    NSString *type = [userInfoData optionalStringForKey:PushChannelNotificationTypeKey];
    
    if (![internalData isKindOfClass:[NSDictionary class]]) {
        if (![internalData isKindOfClass:[NSString class]]) {
            events = [ZMUpdateEvent eventsArrayFromTransportData:userInfoData source:ZMUpdateEventSourcePushNotification];
            identifier = [userInfoData optionalUuidForKey:PushChannelIdentifierKey];
            return [[EventsWithIdentifier alloc] initWithEvents:events identifier:identifier isNotice:NO];
        }

        if (![type isEqualToString:PushNotificationTypeCipher]) {
            ZMLogError(@"Unknown payload type: %@", type);
            return nil;
        }
        
        return [self eventArrayFromEncryptedMessage:userInfoData];
    }
    
    BOOL isNotice = [type isEqualToString:PushNotificationTypeNotice];
    if (!isNotice) {
        events = [ZMUpdateEvent eventsArrayFromTransportData:internalData source:ZMUpdateEventSourcePushNotification];
    }

    identifier = [internalData optionalUuidForKey:PushChannelIdentifierKey];
    return [[EventsWithIdentifier alloc] initWithEvents:events identifier:identifier isNotice:isNotice];
}

- (EventsWithIdentifier *)eventArrayFromEncryptedMessage:(NSDictionary *)encryptedPayload
{
    VerifyStringReturnNil(self.apsSignalKeyStore != nil, "Could not initiate APSSignalingKeystore");
    VerifyStringReturnNil(self.cryptoBox != nil, "Could not instantiate Cryptobox");
    
    //    @"aps" : @{ @"alert": @{@"loc-args": @[],
    //                          @"loc-key"   : @"push.notification.new_message"}
    //              },
    //    @"data": @{ @"data" : @"SomeEncryptedBase64EncodedString",
    //                @"mac"  : @"someMacHashToVerifyTheIntegrityOfTheEncodedPayload",
    //                @"type" : @"cipher"
    //              }
    
    NSDictionary *decodedData = [self.apsSignalKeyStore decryptDataDictionary:encryptedPayload];
    
    if (nil == decodedData) {
        ZMLogError(@"Failed to decrypt data dictionary from push payload: %@", encryptedPayload);
        [APNSPerformanceTracker trackAPNSPayloadDecryptionFailure:self.syncMOC.analytics];
    }
    
    NSDictionary *dataPayload = [decodedData optionalDictionaryForKey:PushChannelDataKey];
    NSUUID *identifier = [dataPayload optionalUuidForKey:PushChannelIdentifierKey];
    NSArray *events = [ZMUpdateEvent eventsArrayFromTransportData:dataPayload source:ZMUpdateEventSourcePushNotification];
    
    NSArray *decryptedEvents = [events mapWithBlock:^id(ZMUpdateEvent *event) {
        return [self.cryptoBox decryptUpdateEventAndAddClient:event managedObjectContext:self.syncMOC];
    }];
    
    if(decryptedEvents.count == 0) {
        return nil;
    }
    
    return [[EventsWithIdentifier alloc] initWithEvents:decryptedEvents identifier:identifier isNotice:NO];
}

- (void)startBackgroundFetchWithCompletionHandler:(ZMBackgroundFetchHandler)handler;
{
    [self.syncMOC performGroupedBlock:^(){
        [self.syncStrategy startBackgroundFetchWithCompletionHandler:handler];
    }];
}

- (void)startBackgroundTaskWithCompletionHandler:(ZMBackgroundTaskHandler)handler;
{
    [self.syncMOC performGroupedBlock:^(){
        [self.syncStrategy startBackgroundTaskWithCompletionHandler:handler];
    }];
}


@end
