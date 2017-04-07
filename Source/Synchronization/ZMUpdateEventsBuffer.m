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

@import WireTransport;
#import "ZMUpdateEventsBuffer.h"

@interface ZMUpdateEventsBuffer ()

@property (nonatomic, readonly, weak) id<ZMUpdateEventConsumer> consumer;
@property (nonatomic, readonly) NSMutableArray *bufferedEvents;

@end




@implementation ZMUpdateEventsBuffer

- (instancetype)initWithUpdateEventConsumer:(id<ZMUpdateEventConsumer>)eventConsumer
{
    self = [super self];
    if(self) {
        _bufferedEvents = [NSMutableArray array];
        _consumer = eventConsumer;
    }
    return self;
}

- (void)addUpdateEvent:(ZMUpdateEvent *)event
{
    [self.bufferedEvents addObject:event];
}

- (void)processAllEventsInBuffer
{
    [self.consumer consumeUpdateEvents:self.bufferedEvents];
    [self.bufferedEvents removeAllObjects];
}

- (void)discardAllUpdateEvents
{
    [self.bufferedEvents removeAllObjects];
}

- (void)discardUpdateEventWithIdentifier:(NSUUID *)eventIdentifier
{
    NSUInteger index = [self.bufferedEvents indexOfObjectPassingTest:^BOOL(ZMUpdateEvent *obj, NSUInteger __unused idx, BOOL * __unused stop) {
        return [obj.uuid isEqual:eventIdentifier];
    }];
    if(index != NSNotFound) {
        [self.bufferedEvents removeObjectAtIndex:index];
    }
}

- (NSArray *)updateEvents
{
    return self.bufferedEvents;
}

@end
