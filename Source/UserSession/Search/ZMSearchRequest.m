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


@import WireSystem;
@import Foundation;
@import WireDataModel;

#import "ZMSearchRequest.h"


@implementation ZMSearchRequest

- (id)copyWithZone:(NSZone *)zone
{
    NOT_USED(zone);
    
    ZMSearchRequest *copy = [[self.class alloc] init];
    
    copy.includeContacts = self.includeContacts;
    copy.includeAddressBookContacts = self.includeAddressBookContacts;
    copy.includeGroupConversations = self.includeGroupConversations;
    copy.includeDirectory = self.includeDirectory;
    copy.includeRemoteResults = self.includeRemoteResults;
    copy.query = self.query;
    copy.filteredConversation = self.filteredConversation;
    
    return copy;
}

- (NSUInteger)hash
{
    NSUInteger result  = 0;
    
    if (self.includeContacts) {
        result += 13 * result + 1;
    }
    
    if (self.includeAddressBookContacts) {
        result += 13 * result + 1;
    }
    
    if (self.includeGroupConversations) {
        result += 13 * result + 1;
    }
    
    if (self.includeDirectory) {
        result += 13 * result + 1;
    }
    
    if (self.includeRemoteResults) {
        result += 13 * result + 1;
    }
    
    if (self.filteredConversation != nil) {
        result += 13 * result + self.filteredConversation.objectID.hash;
    }
    
    if (self.query != nil) {
        result += 13 + result + self.query.hash;
    }
    
    return result;
}

- (BOOL)isEqual:(id)object
{
    if (! [object isKindOfClass:[ZMSearchRequest class]]) {
        return NO;
    }
    
    return [self isEqualToSearchRequest:object];
}

- (BOOL)isEqualToSearchRequest:(ZMSearchRequest *)searchRequest
{
    if (searchRequest == self) {
        return YES;
    }
    
    BOOL isEqual =
    [self.query isEqualToString:searchRequest.query] &&
    self.includeContacts == searchRequest.includeContacts &&
    self.includeAddressBookContacts == searchRequest.includeAddressBookContacts &&
    self.includeGroupConversations == searchRequest.includeGroupConversations &&
    self.includeDirectory == searchRequest.includeDirectory &&
    self.includeRemoteResults == searchRequest.includeRemoteResults &&
    self.filteredConversation == searchRequest.filteredConversation;
    
    return isEqual;
}

- (NSArray *)ignoredIDs
{
    NSMutableArray *ignoredIDs = [NSMutableArray array];
    
    for (ZMUser *participant in self.filteredConversation.otherActiveParticipants) {
        [ignoredIDs addObject:participant.remoteIdentifier];
    }
    
    return ignoredIDs;
}

- (void)setQuery:(NSString *)query
{
    NSUInteger length = MIN(query.length, (unsigned long) 200);
    NSString *croppedString = [query substringWithRange:NSMakeRange(0, length)]; // make sure the request URLs are not getting too long
    _query = croppedString;
}


@end
