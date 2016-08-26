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


#import <ZMCDataModel/ZMBareUser.h>
#import <ZMCDataModel/ZMUser.h>
#import <ZMCDataModel/ZMSearchUser.h>

@class ZMUserSession, ZMAddressBookContact;


@protocol ZMSearchableUser <ZMBareUser>

/// Search for common contacts with this user
- (id<ZMCommonContactsSearchToken>)searchCommonContactsInUserSession:(ZMUserSession *)session withDelegate:(id<ZMCommonContactsSearchDelegate>)delegate;

/// Download the imageMediumData if it doesn't already exist locally.
///
/// For ZMUser:
///  * This is a (cheap) no-op if the data already exists.
///  * It is safe to call this method multiple times.
/// For ZMSearchUser:
///  * If the imageMediumData is already set, no (change) notification will be sent.
- (void)requestMediumProfileImageInUserSession:(ZMUserSession *)userSession;
- (void)requestSmallProfileImageInUserSession:(ZMUserSession *)userSession;


@end


@interface ZMUser (UserSession) <ZMSearchableUser>
@end

@interface ZMSearchUser (UserSession) <ZMSearchableUser>
@end
