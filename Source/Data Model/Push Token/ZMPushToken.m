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


@import WireDataModel;
#import "ZMPushToken.h"

#import <stdio.h>
#import <xlocale.h>



static NSString * const DeviceTokenKey = @"deviceToken";
static NSString * const IdentifierKey = @"identifier";
static NSString * const TransportKey = @"transportType";
static NSString * const IsRegisteredKey = @"isRegistered";
static NSString * const IsMarkedForDeletionKey = @"isMarkedForDeletion";

static NSString * const PushKitTokenKey = @"ZMPushKitToken";
static NSString * const PushKitTokenDataKey = @"ZMPushTokenData";



@interface ZMPushToken ()

@property (nonatomic, copy) NSData *deviceToken;
@property (nonatomic, copy) NSString *appIdentifier;
@property (nonatomic, copy) NSString *transportType;

@property (nonatomic) BOOL isRegistered;
@property (nonatomic) BOOL isMarkedForDeletion;

@end



@implementation ZMPushToken

- (instancetype)initWithDeviceToken:(NSData *)deviceToken identifier:(NSString *)appIdentifier transportType:(NSString *)transportType isRegistered:(BOOL)isRegistered
{
    return [self initWithDeviceToken:deviceToken identifier:appIdentifier transportType:transportType isRegistered:isRegistered isMarkedForDeletion:NO];
}

- (instancetype)initWithDeviceToken:(NSData *)deviceToken identifier:(NSString *)appIdentifier transportType:(NSString *)transportType isRegistered:(BOOL)isRegistered isMarkedForDeletion:(BOOL)isMarkedForDeletion;
{
    self = [super init];
    if (self) {
        self.deviceToken = deviceToken;
        self.appIdentifier = appIdentifier;
        self.transportType = transportType;
        self.isRegistered = isRegistered;
        self.isMarkedForDeletion = isMarkedForDeletion;
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder;
{
    if (self.deviceToken != nil) {
        [coder encodeObject:self.deviceToken forKey:DeviceTokenKey];
    }
    if (self.appIdentifier != nil) {
        [coder encodeObject:self.appIdentifier forKey:IdentifierKey];
    }
    if (self.transportType != nil) {
        [coder encodeObject:self.transportType forKey:TransportKey];
    }
    [coder encodeBool:self.isRegistered forKey:IsRegisteredKey];
    [coder encodeBool:self.isMarkedForDeletion forKey:IsMarkedForDeletionKey];
}

- (BOOL)isEqual:(id)object;
{
    if (! [object isKindOfClass:ZMPushToken.class]) {
        return NO;
    }
    ZMPushToken *other = object;
    return (((self.deviceToken == other.deviceToken) || [self.deviceToken isEqual:other.deviceToken]) &&
            ((self.appIdentifier == other.appIdentifier) || [self.appIdentifier isEqualToString:other.appIdentifier]) &&
            ((self.transportType == other.transportType) || [self.transportType isEqualToString:other.transportType]) &&
            (self.isMarkedForDeletion == other.isMarkedForDeletion));
}

- (id)initWithCoder:(NSCoder *)coder;
{
    self = [self init];
    if (self != nil) {
        self.deviceToken = [coder decodeObjectOfClass:NSData.class forKey:DeviceTokenKey];
        self.appIdentifier = [coder decodeObjectOfClass:NSString.class forKey:IdentifierKey];
        self.transportType = [coder decodeObjectOfClass:NSString.class forKey:TransportKey];
        self.isRegistered = [coder decodeBoolForKey:IsRegisteredKey];
        self.isMarkedForDeletion = [coder decodeBoolForKey:IsMarkedForDeletionKey];
    }
    return self;
}

- (NSString *)description;
{
    return [NSString stringWithFormat:@"<%@: %p> %@, %@ \"%@\" - %@ - device token: %@",
            self.class, self,
            self.isRegistered ? @"registered" : @"not registered",
            self.isMarkedForDeletion ? @"markedForDeletion" : @"valid",
            self.appIdentifier,
            self.transportType,
            self.deviceToken];
}

+ (BOOL)supportsSecureCoding;
{
    return YES;
}

- (instancetype)unregisteredCopy;
{
    return [[self.class alloc] initWithDeviceToken:self.deviceToken identifier:self.appIdentifier transportType:self.transportType isRegistered:NO];
}

- (instancetype)forDeletionMarkedCopy
{
    if (!self.isRegistered) {
        return nil;
    }
    return [[self.class alloc] initWithDeviceToken:self.deviceToken identifier:self.appIdentifier transportType:self.transportType isRegistered:YES isMarkedForDeletion:YES];
}

@end



@implementation NSManagedObjectContext (PushToken)

- (ZMPushToken *)pushKitToken;
{
    NSData *data = [self persistentStoreMetadataForKey:PushKitTokenKey];
    if (data == nil) {
        return nil;
    }
    if (! [data isEqualToData:self.userInfo[PushKitTokenDataKey]]) {
        [self.userInfo removeObjectForKey:PushKitTokenKey];
    } else {
        ZMPushToken *token = self.userInfo[PushKitTokenKey];
        if (token != nil) {
            return token;
        }
    }
    NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:data];
    unarchiver.requiresSecureCoding = YES;
    ZMPushToken *token = [unarchiver decodeObjectOfClass:ZMPushToken.class forKey:PushKitTokenKey];
    
    self.userInfo[PushKitTokenDataKey] = data;
    self.userInfo[PushKitTokenKey] = token;
    
    return token;
}

- (void)setPushKitToken:(ZMPushToken *)pushToken;
{
    NSData *data;
    if (pushToken != nil) {
        NSMutableData *archive = [NSMutableData data];
        NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:archive];
        archiver.requiresSecureCoding = YES;
        [archiver encodeObject:pushToken forKey:PushKitTokenKey];
        [archiver finishEncoding];
        data = archive;
    }
    [self setPersistentStoreMetadata:data forKey:PushKitTokenKey];
    
    if ((data != nil) && (pushToken != nil)) {
        self.userInfo[PushKitTokenDataKey] = data;
        self.userInfo[PushKitTokenKey] = pushToken;
    } else {
        [self.userInfo removeObjectForKey:PushKitTokenDataKey];
        [self.userInfo removeObjectForKey:PushKitTokenKey];
    }
}

@end



@implementation NSString (ZMPushToken)

- (NSData *)zmDeviceTokenData;
{
    NSData *deviceToken = nil;
    if (self.length % 2 == 0) {
        NSData *encodedTokenData = [self dataUsingEncoding:NSUTF8StringEncoding];
        NSMutableData *mutableToken = [NSMutableData dataWithCapacity:self.length / 2];
        locale_t locale = newlocale(LC_ALL, "POSIX", NULL);
        for (size_t i = 0; i + 1 < encodedTokenData.length; i += 2) {
            char s[3];
            [encodedTokenData getBytes:s range:NSMakeRange(i, 2)];
            s[2] = 0;
            unsigned int value = 0;
            int r = sscanf_l(s, locale, "%x", &value);
            if (r != 1) {
                mutableToken = nil;
                break;
            }
            [mutableToken appendBytes:(uint8_t const []){(uint8_t) value} length:1];
        }
        deviceToken = mutableToken;
    }
    return deviceToken;
}

@end
