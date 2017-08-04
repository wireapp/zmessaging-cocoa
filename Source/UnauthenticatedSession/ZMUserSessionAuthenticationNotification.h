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


@import Foundation;


#import <WireDataModel/ZMNotifications.h>

NS_ASSUME_NONNULL_BEGIN

@protocol ZMAuthenticationObserverToken;

typedef NS_ENUM(NSUInteger, ZMUserSessionAuthenticationNotificationType) {
    ZMAuthenticationNotificationAuthenticationDidFail = 0,
    ZMAuthenticationNotificationAuthenticationDidSuceeded,
    ZMAuthenticationNotificationLoginCodeRequestDidFail,
    ZMAuthenticationNotificationLoginCodeRequestDidSucceed,
    ZMAuthenticationNotificationDidRegisterClient,
    ZMAuthenticationNotificationDidDetectSelfClientDeletion
};

@interface ZMUserSessionAuthenticationNotification : ZMNotification

@property (nonatomic) ZMUserSessionAuthenticationNotificationType type;
@property (nonatomic, nullable) NSError *error;

/// Notifies all @c ZMAuthenticationObserver that the authentication failed
+ (void)notifyAuthenticationDidFail:(NSError *)error;

/// Notifies all @c ZMAuthenticationObserver that the authentication succeeded
+ (void)notifyAuthenticationDidSucceed;

/// Notifies all @c ZMAuthenticationObserver that the request for the login code failed
+ (void)notifyLoginCodeRequestDidFail:(NSError *)error;

/// Notifies all @c ZMAuthenticationObserver that the request for the login code succeded
+ (void)notifyLoginCodeRequestDidSucceed;

/// Notifies all @c ZMAuthenticationObserver that the self client has been registered succesfully
+ (void)notifyDidRegisterClient;

/// Notifies all @c ZMAuthenticationObserver that the self client has been deleted remotely
+ (void)notifyDidDetectSelfClientDeletion;

+ (id<ZMAuthenticationObserverToken>)addObserverWithBlock:(void(^)(ZMUserSessionAuthenticationNotification *))block ZM_MUST_USE_RETURN;
+ (void)removeObserverForToken:(id<ZMAuthenticationObserverToken>)token;

@end

NS_ASSUME_NONNULL_END
