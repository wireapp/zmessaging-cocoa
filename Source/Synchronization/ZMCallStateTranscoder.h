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
@import CoreData;
@import WireRequestStrategy;
#import "ZMObjectStrategyDirectory.h"

@class ZMConversation;
@class ZMGSMCallHandler;

typedef NS_ENUM(uint8_t, ZMCallEventSource) {
    ZMCallEventSourcePushChannel = 0,
    ZMCallEventSourceDownstream,
    ZMCallEventSourceUpstream,
};



@interface ZMCallStateTranscoder : ZMObjectSyncStrategy <ZMObjectStrategy>

- (instancetype)initWithSyncManagedObjectContext:(NSManagedObjectContext *)syncMOC
                          uiManagedObjectContext:(NSManagedObjectContext *)uiMOC
                         objectStrategyDirectory:(id<ZMObjectStrategyDirectory>)directory;

- (NSNumber *)lastSequenceForConversation:(ZMConversation *)conversation;

@end




@interface ZMCallStateTranscoder (Testing)

- (instancetype)initWithSyncManagedObjectContext:(NSManagedObjectContext *)syncMOC
                          uiManagedObjectContext:(NSManagedObjectContext *)uiMOC
                         objectStrategyDirectory:(id<ZMObjectStrategyDirectory>)directory
                                  gsmCallHandler:(ZMGSMCallHandler *)gsmCallHandler;

@property (nonatomic, readonly) ZMGSMCallHandler *gsmCallHandler;

@end

