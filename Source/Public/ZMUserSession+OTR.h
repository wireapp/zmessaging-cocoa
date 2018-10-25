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


#import <WireSyncEngine/WireSyncEngine.h>

@class UserClient;

NS_ASSUME_NONNULL_BEGIN

@protocol ZMClientUpdateObserver <NSObject>

- (void)finishedFetchingClients:(NSArray<UserClient *>*)userClients;
- (void)failedToFetchClientsWithError:(NSError *)error;
- (void)finishedDeletingClients:(NSArray<UserClient *>*)remainingClients;
- (void)failedToDeleteClientsWithError:(NSError *)error;

@end


@interface ZMUserSession (OTR)

/// Fetch all selfUser clients to manage them from the settings screen
/// The current client must be already registered
/// Calling this method without a registered client will throw an error
- (void)fetchAllClients;

/// Deletes selfUser clients from the BE when managing them from the settings screen
- (void)deleteClient:(UserClient *)client withCredentials:(nullable ZMEmailCredentials *)emailCredentials;

/// Adds an observer that is notified when the selfUser clients were successfully fetched and deleted
/// Returns a token that needs to be stored as long the observer should be active.
- (id)addClientUpdateObserver:(id<ZMClientUpdateObserver>)observer;

@end

NS_ASSUME_NONNULL_END
