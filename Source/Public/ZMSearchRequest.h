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


@class ZMConversation;

@import Foundation;

@interface ZMSearchRequest : NSObject <NSCopying>

/// Whether to include contact in the result
@property (nonatomic) BOOL includeContacts;
/// Whether to include address book entries in the result
@property (nonatomic) BOOL includeAddressBookContacts;
/// Whether to include group conversations in the result
@property (nonatomic) BOOL includeGroupConversations;
/// Whether to include directory results (non-connected users from BE) in the result
@property (nonatomic) BOOL includeDirectory;

/// If includeRemoteResults is YES contacts & directory results will be fetched from BE.
@property (nonatomic) BOOL includeRemoteResults;

/// Query by which the search results will be filtered.
@property (nonatomic, copy) NSString *query;

/// If filteredConversation is not nil participants from this conversation will be excluded from the search results.
@property (nonatomic) ZMConversation *filteredConversation;

@end
