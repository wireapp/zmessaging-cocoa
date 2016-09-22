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


@import ZMCSystem;
@import ZMTransport;

#import "ZMPushTokenTranscoder.h"

#import "ZMPushToken.h"
#import "ZMClientRegistrationStatus.h"
#import <zmessaging/zmessaging-Swift.h>

static NSString * const VoIPIdentifierSuffix = @"-voip";
static NSString * const TokenKey = @"token";
static NSString * const PushTokenPath = @"/push/tokens";


@interface ZMPushTokenTranscoder ()

@property (nonatomic) ZMSingleRequestSync *applicationTokenSync;
@property (nonatomic) ZMSingleRequestSync *pushKitTokenSync;
@property (nonatomic) ZMSingleRequestSync *pushKitTokenDeletionSync;
@property (nonatomic) ZMSingleRequestSync *pushTokenDeletionSync;

@property (nonatomic, weak) ZMClientRegistrationStatus *clientRegistrationStatus;
@end



@interface ZMPushTokenTranscoder (Transcoder) <ZMSingleRequestTranscoder>
@end



@implementation ZMPushTokenTranscoder

- (instancetype)initWithManagedObjectContext:(NSManagedObjectContext *)moc clientRegistrationStatus:(ZMClientRegistrationStatus *)clientRegistrationStatus;
{
    self = [super initWithManagedObjectContext:moc];
    if (self != nil) {
        self.applicationTokenSync = [[ZMSingleRequestSync alloc] initWithSingleRequestTranscoder:self managedObjectContext:self.managedObjectContext];
        self.pushKitTokenSync = [[ZMSingleRequestSync alloc] initWithSingleRequestTranscoder:self managedObjectContext:self.managedObjectContext];
        self.pushKitTokenDeletionSync = [[ZMSingleRequestSync alloc] initWithSingleRequestTranscoder:self managedObjectContext:self.managedObjectContext];
        self.pushTokenDeletionSync = [[ZMSingleRequestSync alloc] initWithSingleRequestTranscoder:self managedObjectContext:self.managedObjectContext];
        self.clientRegistrationStatus = clientRegistrationStatus;
    }
    return self;
}

- (BOOL)isSlowSyncDone;
{
    return YES;
}

- (NSArray *)contextChangeTrackers;
{
    return @[self];
}

- (void)setNeedsSlowSync;
{
    // no-op
}

- (NSArray *)requestGenerators;
{
    if (self.clientRegistrationStatus.currentPhase != ZMClientRegistrationPhaseRegistered) {
        return @[];
    }
    return @[self.applicationTokenSync, self.pushKitTokenSync, self.pushKitTokenDeletionSync, self.pushTokenDeletionSync];
}

- (void)processEvents:(NSArray<ZMUpdateEvent *> *)events
           liveEvents:(BOOL)liveEvents
       prefetchResult:(__unused ZMFetchRequestBatchResult *)prefetchResult;
{
    if(!liveEvents) {
        return;
    }
    
    for(ZMUpdateEvent *event in events) {
        [self processUpdateEvent:event];
    }
}

- (void)processUpdateEvent:(ZMUpdateEvent *)event;
{
    if (event.type != ZMUpdateEventUserPushRemove) {
        return;
    }
    
    // expected payload:
    // { "type: "user.push-remove",
    //   "token":
    //    { "transport": "APNS",
    //            "app": "name of the app",
    //          "token": "the token you get from apple"
    //    }
    // }

    // we ignore the payload and reregister both tokens whenever we receive a user.push-remove event
    
    self.managedObjectContext.pushToken = [self.managedObjectContext.pushToken unregisteredCopy];
    self.managedObjectContext.pushKitToken = [self.managedObjectContext.pushKitToken unregisteredCopy];
}

- (NSFetchRequest *)fetchRequestForTrackedObjects
{
    return nil;
}

- (void)addTrackedObjects:(NSSet *)objects;
{
    NOT_USED(objects);
}

- (void)objectsDidChange:(NSSet *)objects
{
    NOT_USED(objects);
    ZMPushToken *token = self.managedObjectContext.pushToken;
    if (token != nil) {
        if (token.isMarkedForDeletion) {
            if (self.pushTokenDeletionSync.status != ZMSingleRequestInProgress) {
                [self.pushTokenDeletionSync readyForNextRequest];
                [ZMRequestAvailableNotification notifyNewRequestsAvailable:self];
            }
        }
        else if(!token.isRegistered && (self.applicationTokenSync.status != ZMSingleRequestInProgress)) {
            [self.applicationTokenSync readyForNextRequest];
            [ZMRequestAvailableNotification notifyNewRequestsAvailable:self];
        }
    }
    
    token = self.managedObjectContext.pushKitToken;
    if (token != nil) {
        if (token.isMarkedForDeletion){
            if(self.pushKitTokenDeletionSync.status != ZMSingleRequestInProgress) {
                [self.pushKitTokenDeletionSync readyForNextRequest];
                [ZMRequestAvailableNotification notifyNewRequestsAvailable:self];
            }
        }
        else if( (! token.isRegistered) && (self.pushKitTokenSync.status != ZMSingleRequestInProgress)) {
            [self.pushKitTokenSync readyForNextRequest];
            [ZMRequestAvailableNotification notifyNewRequestsAvailable:self];
        }
    }
}

@end



@implementation ZMPushTokenTranscoder (Transcoder)

- (ZMPushToken *)tokenForSingleRequestSync:(ZMSingleRequestSync *)sync;
{
    if (sync == self.applicationTokenSync || sync == self.pushTokenDeletionSync) {
        return self.managedObjectContext.pushToken;
    } else if (sync == self.pushKitTokenSync || sync == self.pushKitTokenDeletionSync) {
        return self.managedObjectContext.pushKitToken;
    } else {
        Require(NO);
        return nil;
    }
}

- (void)setToken:(ZMPushToken *)token forSingleRequestSync:(ZMSingleRequestSync *)sync;
{
    if (sync == self.applicationTokenSync || sync == self.pushTokenDeletionSync) {
        self.managedObjectContext.pushToken = token;
    } else if (sync == self.pushKitTokenSync || sync == self.pushKitTokenDeletionSync) {
        self.managedObjectContext.pushKitToken = token;
    } else {
        Require(NO);
    }
}

- (ZMTransportRequest *)requestForSingleRequestSync:(ZMSingleRequestSync *)sync;
{
    ZMPushToken *token = [self tokenForSingleRequestSync:sync];
    if ((token == nil) || (token.isRegistered && !token.isMarkedForDeletion)) {
        [sync resetCompletionState];
        return nil;
    }
    if ((token.deviceToken == nil) || (token.appIdentifier == nil) || (token.transportType == nil)) {
        [self setToken:nil forSingleRequestSync:sync];
        [sync resetCompletionState];
        return nil;
    }
    
    // hex encode the token:
    NSMutableString *encodedToken = [NSMutableString stringWithCapacity:token.deviceToken.length * 2];
    [token.deviceToken enumerateByteRangesUsingBlock:^(const void *bytes, NSRange byteRange, BOOL *stop) {
        NOT_USED(stop);
        for (size_t i = 0; i < byteRange.length; ++i) {
            [encodedToken appendFormat:@"%02x", ((uint8_t const *) bytes)[i]];
        }
    }];
    
    if (encodedToken.length == 0) {
        return nil;
    }
    
    if (token.isMarkedForDeletion) {
        if (sync == self.pushKitTokenDeletionSync || sync == self.pushTokenDeletionSync) {
            NSString *path = [NSString pathWithComponents:@[PushTokenPath, encodedToken]];
            return [ZMTransportRequest requestWithPath:path method:ZMMethodDELETE payload:nil];
        }
    } else {
        NSMutableDictionary *payload = [NSMutableDictionary dictionary];
        payload[@"token"] =  encodedToken;
        payload[@"app"] = token.appIdentifier;
        payload[@"transport"] = token.transportType;

        if (nil != token.fallback) {
            payload[@"fallback"] = token.fallback;
        }
        
        ZMUser *selfUser = [ZMUser selfUserInContext:self.managedObjectContext];
        NSString *userClientID = selfUser.selfClient.remoteIdentifier;
        if (userClientID !=  nil) {
            payload[@"client"] = userClientID;
        }
        return [ZMTransportRequest requestWithPath:PushTokenPath method:ZMMethodPOST payload:payload];
    }
    return nil;
}


- (void)didReceiveResponse:(ZMTransportResponse *)response forSingleRequest:(ZMSingleRequestSync *)sync
{
    if (sync == self.pushKitTokenDeletionSync || sync == self.pushTokenDeletionSync) {
        if (response.result == ZMTransportResponseStatusSuccess) {
            ZMPushToken *token = [self tokenForSingleRequestSync:sync];
            if (token.isMarkedForDeletion) {
                [self setToken:nil forSingleRequestSync:sync];
            }
        } else if (response.result == ZMTransportResponseStatusPermanentError) {
            [self setToken:nil forSingleRequestSync:sync];
        }
    }
    else if (response.result == ZMTransportResponseStatusSuccess) {
        [self setPushTokenWithResponse:response forSync:sync];
    } else {
        [self setToken:nil forSingleRequestSync:sync];
    }
    
    // Need to call -save: to force a save, since nothing in the context will change:
    NSError *error = nil;
    if (! [self.managedObjectContext save:&error]) {
        ZMLogError(@"Failed to save push token: %@", error);
    }
    
    [sync resetCompletionState];
}

- (void)setPushTokenWithResponse:(ZMTransportResponse *)response forSync:(ZMSingleRequestSync *)sync
{
    NSDictionary *payloadDictionary = [response.payload asDictionary];
    NSString *encodedToken = [payloadDictionary stringForKey:@"token"];
    NSData *deviceToken = [encodedToken zmDeviceTokenData];
    NSString *identifier = [payloadDictionary stringForKey:@"app"];
    NSString *transportType = [payloadDictionary stringForKey:@"transport"];
    NSString *fallback = [payloadDictionary optionalStringForKey:@"fallback"];

    if ((deviceToken != nil) && (identifier != nil) && (transportType != nil)) {
        ZMPushToken *t = [[ZMPushToken alloc] initWithDeviceToken:deviceToken identifier:identifier transportType:transportType fallback:fallback isRegistered:YES];
        [self setToken:t forSingleRequestSync:sync];
        [self.managedObjectContext forceSaveOrRollback];
    }
}

@end
