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


@import WireTransport;
@import WireCryptobox;

#import "ZMOperationLoop+Background.h"
#import "ZMOperationLoop+Private.h"
#import "ZMSyncStrategy+EventProcessing.h"

#import "ZMSyncStrategy+Internal.h"
#import <WireSyncEngine/WireSyncEngine-Swift.h>

static NSString *ZMLogTag ZM_UNUSED = @"Network";


static NSString * const PushChannelDataKey = @"data";
static NSString * const PushChannelIdentifierKey = @"id";
static NSString * const PushChannelNotificationTypeKey = @"type";

static NSString * const PushNotificationTypeCipher = @"cipher";
static NSString * const PushNotificationTypeNotice = @"notice";



@implementation ZMOperationLoop (Background)


- (void)saveEventsAndSendNotificationForPayload:(NSDictionary *)payload fetchCompletionHandler:(ZMPushResultHandler)completionHandler source:(ZMPushNotficationType)source;
{
    ZMLogDebug(@"----> Received push notification payload: %@, source: %lu", payload, (unsigned long)source);
    [self.syncMOC performGroupedBlock:^{
        
        EventsWithIdentifier *eventsWithID = [self eventsFromPushChannelData:payload];
        BOOL isValidNotification = (nil != eventsWithID) && (eventsWithID.isNotice || eventsWithID.events.count > 0);
        
        if ((source == ZMPushNotficationTypeVoIP) && isValidNotification) {
            [self processNotification:eventsWithID fetchCompletionHandler:completionHandler];
        }
        else if (completionHandler != nil) {
            ZMLogPushKit(@"ZMOperationLoop - calling completionHandler without creating notifications");
            [self.syncMOC.dispatchGroup notifyOnQueue:dispatch_get_main_queue() block:^{
                completionHandler(ZMPushPayloadResultSuccess);
            }];
        }
    }];
}

- (void)processNotification:(EventsWithIdentifier*)eventsWithID fetchCompletionHandler:(ZMPushResultHandler)completionHandler
{
    ZM_WEAK(self);
    [self.backgroundAPNSPingBackStatus didReceiveVoIPNotification:eventsWithID handler:^(ZMPushPayloadResult result, NSArray<ZMUpdateEvent *> *receivedEvents) {
        ZM_STRONG(self);
        
        if (result == ZMPushPayloadResultSuccess) {
            [self forwardEvents:receivedEvents];
        }
        if (completionHandler != nil) {
            [self.syncMOC.dispatchGroup notifyOnQueue:dispatch_get_main_queue() block:^{
                ZMLogPushKit(@"Calling CompletionHandler");
                completionHandler(result);
            }];
        }
    }];
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
    [ZMRequestAvailableNotification notifyNewRequestsAvailable:self];
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
    }
    
    NSDictionary *dataPayload = [decodedData optionalDictionaryForKey:PushChannelDataKey];
    NSUUID *identifier = [dataPayload optionalUuidForKey:PushChannelIdentifierKey];
    NSArray *events = [ZMUpdateEvent eventsArrayFromTransportData:dataPayload source:ZMUpdateEventSourcePushNotification];
    VerifyReturnNil(identifier);

    return [[EventsWithIdentifier alloc] initWithEvents:events identifier:identifier isNotice:NO];
}

@end
