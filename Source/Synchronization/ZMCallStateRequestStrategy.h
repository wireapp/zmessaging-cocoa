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
@import WireMessageStrategy;
#import "ZMObjectStrategyDirectory.h"

@class ZMConversation;
@class ZMGSMCallHandler;

typedef NS_ENUM(uint8_t, ZMCallEventSource) {
    ZMCallEventSourcePushChannel = 0,
    ZMCallEventSourceDownstream,
    ZMCallEventSourceUpstream,
};



@interface ZMCallStateRequestStrategy : ZMAbstractRequestStrategy <ZMEventConsumer, ZMContextChangeTrackerSource>

- (instancetype)initWithManagedObjectContext:(NSManagedObjectContext *)moc
                           applicationStatus:(id<ZMApplicationStatus>)applicationStatus NS_UNAVAILABLE;

- (instancetype)initWithManagedObjectContext:(NSManagedObjectContext *)managedObjectContext
                           applicationStatus:(id<ZMApplicationStatus>)applicationStatus
                     callFlowRequestStrategy:(ZMCallFlowRequestStrategy *)callFlowRequestStrategy;

- (NSNumber *)lastSequenceForConversation:(ZMConversation *)conversation;

@end




@interface ZMCallStateRequestStrategy (Testing)

- (instancetype)initWithManagedObjectContext:(NSManagedObjectContext *)managedObjectContext
                           applicationStatus:(id<ZMApplicationStatus>)applicationStatus
                     callFlowRequestStrategy:(ZMCallFlowRequestStrategy *)callFlowRequestStrategy
                              gsmCallHandler:(ZMGSMCallHandler *)gsmCallHandler;

@property (nonatomic, readonly) ZMGSMCallHandler *gsmCallHandler;

@end

