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
#import <WireSyncEngine/WireSyncEngine-Swift.h>

static NSString *ZMLogTag ZM_UNUSED = @"Network";

static NSString * const PushChannelDataKey = @"data";
static NSString * const PushChannelIdentifierKey = @"id";
static NSString * const PushChannelNotificationTypeKey = @"type";
static NSString * const PushNotificationTypePlain  = @"plain";
static NSString * const PushNotificationTypeCipher = @"cipher";
static NSString * const PushNotificationTypeNotice = @"notice";

@implementation ZMOperationLoop (Background)

- (void)fetchEventsFromPushChannelPayload:(NSDictionary *)payload completionHandler:(dispatch_block_t)completionHandler
{
    ZMLogDebug(@"----> Received push notification payload: %@", payload);
    
    [self.syncMOC performGroupedBlock:^{
        NSUUID *eventId = [self messageNonceFromFromPushChannelData:payload];
        if (eventId == nil) {
            completionHandler();
            return;
        }
        
        [self.pushNotificationStatus fetchEventId:eventId completionHandler:completionHandler];
    }];
}

- (NSUUID *)messageNonceFromFromPushChannelData:(NSDictionary *)userInfo
{
    NSDictionary *userInfoData = [userInfo optionalDictionaryForKey:PushChannelDataKey];
    if (userInfoData == nil) {
        ZMLogError(@"No data dictionary in notification userInfo payload");
        return nil;
    }
    
    id internalData = userInfoData[PushChannelDataKey];
    NSString *type = [userInfoData optionalStringForKey:PushChannelNotificationTypeKey];
    
    if ([type isEqualToString:PushNotificationTypePlain]) {
        return [internalData optionalUuidForKey:PushChannelIdentifierKey];
    } else if ([type isEqualToString:PushNotificationTypeCipher]) {
        return [self messageNonceFromEncryptedPushChannelData:userInfoData];
    } else if ([type isEqualToString:PushNotificationTypeNotice]) {
        return [internalData optionalUuidForKey:PushChannelIdentifierKey];
    }
    
    return nil;
}

- (NSUUID *)messageNonceFromEncryptedPushChannelData:(NSDictionary *)encryptedPayload
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
    return [dataPayload optionalUuidForKey:PushChannelIdentifierKey];
}

@end
