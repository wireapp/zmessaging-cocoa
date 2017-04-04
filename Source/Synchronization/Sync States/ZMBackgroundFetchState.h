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
#import "ZMSyncState.h"
#import "ZMBackgroundFetch.h"



/// This state implements background fetching.
///
/// The
/// @code
/// -[UIApplication application:performFetchWithCompletionHandler:]
/// @endcode
/// method should be tied up to make the state machine go into this state. The completion handler should be called by the @c fetchCompletionHandler property.
///
/// Make sure to check out Apple’s “Testing Background Fetching” documentation.
/// In Xcode 6.3:
///     To simulate a background fetch, go to Xcode and choose Debug > Simulate Background Fetch.
///     To enable your app to be launched directly into a suspended state, choose Product > Scheme > Edit Scheme, and select the Background Fetch checkbox.
@interface ZMBackgroundFetchState : ZMSyncState

@property (nonatomic, copy) ZMBackgroundFetchHandler fetchCompletionHandler;

@end


@interface ZMBackgroundFetchState (Testing)

@property (nonatomic) NSTimeInterval maximumTimeInState;

@end

