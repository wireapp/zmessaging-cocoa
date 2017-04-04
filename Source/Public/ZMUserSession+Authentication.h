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
@import WireSystem;

#import <WireSyncEngine/ZMUserSession.h>


@protocol ZMAuthenticationObserver;
@class ZMCredentials;

@protocol ZMAuthenticationObserverToken <NSObject>
@end

@interface ZMUserSession (Authentication)

- (id<ZMAuthenticationObserverToken>)addAuthenticationObserver:(id<ZMAuthenticationObserver>)observer ZM_MUST_USE_RETURN;
- (void)removeAuthenticationObserverForToken:(id<ZMAuthenticationObserverToken>)observerToken;

/// Check whether the user is logged in
- (void)checkIfLoggedInWithCallback:(void(^)(BOOL loggedIn))callback;

///// Attempt to log in with the given credentials
- (void)loginWithCredentials:(ZMCredentials *)loginCredentials;

/// Requires a phone verification code for login. Returns NO if the phone number was invalid
- (BOOL)requestPhoneVerificationCodeForLogin:(NSString *)phoneNumber;

/// This will delete any data stored by WireSyncEngine in the keychain.
+ (void)deleteAllKeychainItems;

/// Delete cookies etc. and exit the app.
/// This is a temporary workaround for QA.
+ (void)resetStateAndExit;

/// This will delete any data stored by WireSyncEngine, but retain the cookies (i.e. keychain)
+ (void)deleteCacheOnRelaunch;

- (BOOL)hadHistoryAtLastLogin;

@end



@protocol ZMAuthenticationObserver <NSObject>
@optional

/// Invoked when requesting a login code for the phone failed
- (void)loginCodeRequestDidFail:(NSError *)error;

/// Invoked when requesting a login code succeded
- (void)loginCodeRequestDidSucceed;

/// Invoked when the authentication failed, or when the cookie was revoked
- (void)authenticationDidFail:(NSError *)error;

/// Invoked when the authentication succeeded and the user now has a valid cookie
- (void)authenticationDidSucceed;

@end

