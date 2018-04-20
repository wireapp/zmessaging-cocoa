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

@class ZMCredentials;

@interface ZMUserSession (Authentication)

- (void)setEmailCredentials:(ZMEmailCredentials *)emailCredentials;

/// Check whether the user is logged in
- (void)checkIfLoggedInWithCallback:(void(^)(BOOL loggedIn))callback;

/// This will delete user data stored by WireSyncEngine in the keychain.
- (void)deleteUserKeychainItems;

/// Delete cookies etc. and logout the current user.
- (void)closeAndDeleteCookie:(BOOL)deleteCookie;

@end


