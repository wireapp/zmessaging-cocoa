//
// Wire
// Copyright (C) 2018 Wire Swiss GmbH
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

#import <Foundation/Foundation.h>
@import WireDataModel;

static NSString * const PushKitTokenKey = @"ZMPushKitToken";
static NSString * const PushKitTokenDataKey = @"ZMPushTokenData";


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
