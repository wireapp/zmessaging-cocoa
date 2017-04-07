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
@import WireDataModel;

#import "ZMCommonContactsSearchDelegate.h"


@class ZMTransportSession;



@interface ZMCommonContactsSearchCachedEntry : NSObject

@property (nonatomic, readonly) NSDate *expirationDate;
@property (nonatomic, readonly) NSUInteger commonConnectionCount;

- (instancetype)initWithExpirationDate:(NSDate *)expirationDate commonConnectionCount:(NSUInteger)commonConnectionCount;

@end



@interface ZMCommonContactsSearch : NSObject

@property (nonatomic, readonly) id<ZMCommonContactsSearchToken> searchToken;

+ (void)startSearchWithTransportSession:(ZMTransportSession *)transportSession
                                 userID:(NSUUID *)userID
                                  token:(id<ZMCommonContactsSearchToken>)token
                                syncMOC:(NSManagedObjectContext *)syncMoc
                                  uiMOC:(NSManagedObjectContext *)uiMOC
                         searchDelegate:(id<ZMCommonContactsSearchDelegate>)delegate
                           resultsCache:(NSCache *)resultsCache;

@end
