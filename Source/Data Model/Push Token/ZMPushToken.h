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


#import <Foundation/Foundation.h>


/// A push token used to register the app with the backend + APNS.
__deprecated
@interface ZMPushToken : NSObject <NSSecureCoding>

- (instancetype _Nonnull)initWithDeviceToken:(NSData * _Nonnull)deviceToken
                         identifier:(NSString * _Nonnull)appIdentifier
                      transportType:(NSString * _Nonnull)transportType
                       isRegistered:(BOOL)isRegistered __deprecated;

@property (nonatomic, copy, readonly, nonnull) NSData *deviceToken __deprecated;
@property (nonatomic, copy, readonly, nonnull) NSString *appIdentifier __deprecated;
@property (nonatomic, copy, readonly, nonnull) NSString *transportType __deprecated;
@property (nonatomic, readonly) BOOL isRegistered __deprecated;
@property (nonatomic, readonly) BOOL isMarkedForDeletion __deprecated;

/// Returns a copy of the receiver with @c isRegistered set to @c NO
- (instancetype _Nonnull)unregisteredCopy __deprecated;

/// Returns a copy of the receiver is @c isMarkedForDeletion set to @c YES or nil if the token is not registered
- (instancetype _Nullable)forDeletionMarkedCopy __deprecated;

@end



@interface NSManagedObjectContext (PushToken)

/// The token used for PushKit based remote push notifications. PushKit also refers to the token as ‘credentials’.
@property (nonatomic, copy, nullable) ZMPushToken *pushKitToken __deprecated;

@end



@interface NSString (ZMPushToken)

- (nullable NSData *)zmDeviceTokenData __deprecated;

@end
