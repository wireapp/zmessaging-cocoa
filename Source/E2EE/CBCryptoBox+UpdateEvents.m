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
@import ZMUtilities;

#import "CBCryptoBox+UpdateEvents.h"
#import <zmessaging/zmessaging-Swift.h>


NSString * CBErrorCodeToString(CBoxResult errorCode);

@implementation EncryptionSessionsDirectory (UpdateEvent)

- (BOOL)isEvent:(ZMUpdateEvent *)event forSelfClient:(UserClient *)selfClient
{
    NSString *recipient = [[event.payload.asDictionary optionalDictionaryForKey:@"data"] optionalStringForKey:@"recipient"];
    return recipient != nil && [recipient isEqualToString:selfClient.remoteIdentifier];
}

- (ZMUpdateEvent *)decryptUpdateEventAndAddClient:(ZMUpdateEvent *)event managedObjectContext:(NSManagedObjectContext *)moc
{
    VerifyReturnNil(event != nil);
    
    // check if decrypted already
    ZMUpdateEvent *decryptedEvent;
    if (event.wasDecrypted) {
        return event;
    }
    
    // is it for the current client?
    ZMUser *selfUser = [ZMUser selfUserInContext:moc];
    BOOL checkRecipient = event.type == ZMUpdateEventConversationOtrMessageAdd || event.type == ZMUpdateEventConversationOtrAssetAdd;
    if(checkRecipient && ![self isEvent:event forSelfClient:selfUser.selfClient]) {
        return nil;
    }
    
    // decrypt
    NSString *newSessionId;
    NSError *error = nil;
    if (event.type == ZMUpdateEventConversationOtrMessageAdd) {
        decryptedEvent = [self decryptOTRClientMessageUpdateEvent:event newSessionId:&newSessionId error:&error];
    } else if (event.type == ZMUpdateEventConversationOtrAssetAdd) {
        decryptedEvent = [self decryptOTRAssetUpdateEvent:event newSessionId:&newSessionId error:&error];
    } else {
        return event;
    }
    
    // new client discovered?
    if (newSessionId != nil) {
        NSUUID *userID = [event.payload.asDictionary optionalUuidForKey:@"from"];
        [self didDiscoverNewClientWithSessionId:newSessionId senderId:userID moc:moc];
    }
    
    // failure?
    if (decryptedEvent == nil) {
        [self appendFailedToDecryptMessageForEvent:event error:error managedObjectContext:moc];
    }
    [decryptedEvent appendDebugInformation:event.debugInformation];
    return decryptedEvent;
}

/// Appends a system message for a failed decryption
- (void)appendFailedToDecryptMessageForEvent:(ZMUpdateEvent *)event
                                       error:(NSError *)error
                        managedObjectContext:(NSManagedObjectContext *)managedObjectContext
{
    BOOL didFailBecauseDuplicated = error != nil
    && (error.code == CBOX_OUTDATED_MESSAGE || error.code == CBOX_DUPLICATE_MESSAGE);
    
    // do not notify user if it's just a duplicated one
    if(didFailBecauseDuplicated) {
        return;
    }
    NSMutableDictionary *userInfoDictionary = [NSMutableDictionary dictionaryWithDictionary:@{@"cause" : CBErrorCodeToString((CBoxResult)error.code)}];
    
    NSString *senderClientID = [[event.payload.asDictionary optionalDictionaryForKey:@"data"] optionalStringForKey:@"sender"];
    
    if (event.conversationUUID != nil && event.senderUUID != nil && senderClientID != nil) {
        ZMConversation *conversation = [ZMConversation conversationWithRemoteID:event.conversationUUID createIfNeeded:NO inContext:managedObjectContext];
        ZMUser *sender = [ZMUser userWithRemoteID:event.senderUUID createIfNeeded:NO inContext:managedObjectContext];
        UserClient *client = [UserClient fetchUserClientWithRemoteId:senderClientID forUser:sender createIfNeeded:NO];
        if (client != nil) {
            userInfoDictionary[@"deviceClass"] = client.deviceClass;
            ZMLogError(@"Unable to decrypt event %@, client: %@", event, client.description);
        } else {
            ZMLogError(@"Unable to decrypt event %@, unknown client for user: %@", event, sender.name);
        }
        if (conversation != nil && sender != nil) {
            [conversation appendDecryptionFailedSystemMessageAtTime:event.timeStamp sender:sender client:client errorCode:error.code];
        }
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:ZMConversationFailedToDecryptMessageNotificationName object:self userInfo:userInfoDictionary];
}

- (ZMUpdateEvent *)decryptOTRClientMessageUpdateEvent:(ZMUpdateEvent *)event newSessionId:(NSString *__autoreleasing *)newSessionId error:(NSError **)error
{
    NSData *decryptedData = [self decryptOTRMessageUpdateEvent:event valueForKey:@"text" newSessionId:newSessionId error:error];
    VerifyReturnNil(decryptedData != nil);

    NSMutableDictionary *payload = [event.payload.asDictionary mutableCopy];
    NSMutableDictionary *eventData = [[event.payload.asDictionary optionalDictionaryForKey:@"data"] mutableCopy];
    if ([eventData.allKeys containsObject:@"data"]) {
        NSString *inlineData = [eventData optionalStringForKey:@"data"];
        VerifyReturnNil(nil != inlineData);
        payload[@"external"] = inlineData;
    }

    eventData[@"text"] = decryptedData.base64String;
    payload[@"data"] = eventData;

    return [ZMUpdateEvent decryptedUpdateEventFromEventStreamPayload:payload uuid:event.uuid source:event.source];
}

- (ZMUpdateEvent *)decryptOTRAssetUpdateEvent:(ZMUpdateEvent *)event newSessionId:(NSString *__autoreleasing *)newSessionId error:(NSError **)error
{
    NSData *decryptedData = [self decryptOTRMessageUpdateEvent:event valueForKey:@"key" newSessionId:newSessionId error:error];
    VerifyReturnNil(decryptedData != nil);

    NSMutableDictionary *payload = [event.payload.asDictionary mutableCopy];
    NSMutableDictionary *eventData = [[event.payload.asDictionary optionalDictionaryForKey:@"data"] mutableCopy];
    eventData[@"info"] = [decryptedData base64EncodedStringWithOptions:0];
    payload[@"data"] = eventData;

    return [ZMUpdateEvent decryptedUpdateEventFromEventStreamPayload:payload uuid:event.uuid source:event.source];
}

- (NSData *)decryptOTRMessageUpdateEvent:(ZMUpdateEvent *)event valueForKey:(NSString *)dataKey newSessionId:(NSString *__autoreleasing *)newSessionId error:(NSError **)error
{
    NSDictionary *eventData = [event.payload.asDictionary optionalDictionaryForKey:@"data"];
    NSString *senderClientId = [eventData optionalStringForKey:@"sender"];
    NSString *dataString = [eventData optionalStringForKey:dataKey];
    VerifyReturnNil(dataString != nil);

    if([dataString isEqualToString:[ZMFailedToCreateEncryptedMessagePayloadString dataUsingEncoding:NSUTF8StringEncoding].base64String]) {
        ZMLogError(@"Received a message with a \"failed to encrypt for your client\" special payload. Current device might have invalid prekeys on the BE.");
        return nil;
    }
    NSData *data = [[NSData alloc] initWithBase64EncodedString:dataString options:0];
    
    
    VerifyReturnNil(senderClientId != nil);
    VerifyReturnNil(data != nil);
    
    NSData *decryptedData;
    if (![self hasSessionForID:senderClientId]) {
        decryptedData = [self createClientSessionAndReturnPlaintext:senderClientId prekeyMessage:data error:error];
        *newSessionId = senderClientId;
        if (nil == decryptedData) {
            ZMLogError(@"Failed to decrypt message with session info <%@>: %@, update Event: %@", CBErrorCodeToString((CBoxResult)(*error).code), *error, event.debugInformation);
        }
    } else {
        decryptedData = [self decrypt:data senderClientId:senderClientId error:error];
        if (nil == decryptedData) {
            ZMLogError(@"Failed to decrypt message <%@>: %@, update Event: %@", CBErrorCodeToString((CBoxResult)(*error).code), *error, event.debugInformation);
        }
    }
    return decryptedData;
}

- (UserClient *)didDiscoverNewClientWithSessionId:(NSString *)sessionId senderId:(NSUUID *)senderUserId moc:(NSManagedObjectContext *)moc {
    
    if (sessionId != nil && senderUserId != nil) {
        ZMUser *selfUser = [ZMUser selfUserInContext:moc];
        [selfUser.selfClient decrementNumberOfRemainingKeys];
        
        //create user+client and do not trust it
        //user probably will be already created due to preceding member-join event
        //but client will be created only when message from this client is received
        ZMUser *user = [ZMUser userWithRemoteID:senderUserId createIfNeeded:YES inContext:moc];
        if (user != nil) {
            UserClient *newClient = [UserClient fetchUserClientWithRemoteId:sessionId forUser:user createIfNeeded:YES];
            [selfUser.selfClient addNewClientsToIgnored:[NSSet setWithObject:newClient] causedBy:nil];
            return newClient;
        }
    }
    return nil;
}

@end

NSString *
CBErrorCodeToString(CBoxResult errorCode)
{
    switch (errorCode) {
        case CBOX_STORAGE_ERROR:
            return @"CBErrorCodeStorageError";
        case CBOX_SESSION_NOT_FOUND:
            return @"CBErrorCodeNoSession";
        case CBOX_PREKEY_NOT_FOUND:
            return @"CBErrorCodeNoPreKey";
        case CBOX_DECODE_ERROR:
            return @"CBErrorCodeDecodeError";
        case CBOX_REMOTE_IDENTITY_CHANGED:
            return @"CBErrorCodeRemoteIdentityChanged";
        case CBOX_IDENTITY_ERROR:
            return @"CBErrorCodeInvalidIdentity";
        case CBOX_INVALID_SIGNATURE:
            return @"CBErrorCodeInvalidSignature";
        case CBOX_INVALID_MESSAGE:
            return @"CBErrorCodeInvalidMessage";
        case CBOX_DUPLICATE_MESSAGE:
            return @"CBErrorCodeDuplicateMessage";
        case CBOX_TOO_DISTANT_FUTURE:
            return @"CBErrorCodeTooDistantFuture";
        case CBOX_OUTDATED_MESSAGE:
            return @"CBErrorCodeOutdatedMessage";
        case CBOX_UTF8_ERROR:
            return @"CBErrorCodeUTF8Error";
        case CBOX_NUL_ERROR:
            return @"CBErrorCodeNULError";
        case CBOX_ENCODE_ERROR:
            return @"CBErrorCodeEncodeError";
        case CBOX_PANIC:
            return @"CBErrorCodePanic";
        default:
            return [NSString stringWithFormat:@"Unknown error code: %lu", (long)errorCode];
    }

}
