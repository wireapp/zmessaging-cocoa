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

#import "MessagingTest.h"
#import "ZMUpdateEventsBuffer.h"

@interface ZMUpdateEventsBufferTests : MessagingTest

@property (nonatomic, readonly) ZMUpdateEventsBuffer *sut;
@property (nonatomic, readonly) id<ZMUpdateEventConsumer> consumer;

@end

@implementation ZMUpdateEventsBufferTests

- (void)setUp {
    [super setUp];
    _consumer = [OCMockObject mockForProtocol:@protocol(ZMUpdateEventConsumer)];
    [self verifyMockLater:_consumer];
    
    _sut = [[ZMUpdateEventsBuffer alloc] initWithUpdateEventConsumer:self.consumer];
}

- (void)tearDown {

    _sut = nil;
    _consumer = nil;
    [super tearDown];
}

- (ZMUpdateEvent *)dummyEvent
{
    id event = [OCMockObject niceMockForClass:ZMUpdateEvent.class];
    [(ZMUpdateEvent *)[[event stub] andReturn:[NSUUID createUUID]] uuid];
    return event;
}



- (void)testThatItDoesNotSendEventsToConsumerWithoutAFlush
{
    // given
    ZMUpdateEvent *event = [self dummyEvent];
    
    // expect
    [[(id)self.consumer reject] consumeUpdateEvents:OCMOCK_ANY];
    
    // when
    [self.sut addUpdateEvent:event];
}

- (void)testThatItDoesSendEventsToConsumerWhenFlushing
{
    // given
    ZMUpdateEvent *event1 = [self dummyEvent];
    ZMUpdateEvent *event2 = [self dummyEvent];
    [self.sut addUpdateEvent:event1];
    [self.sut addUpdateEvent:event2];
    
    // expect
    [[(id)self.consumer expect] consumeUpdateEvents:@[event1, event2]];
    
    // when
    [self.sut processAllEventsInBuffer];

}

- (void)testThatItDiscardsAllEvents
{
    // given
    ZMUpdateEvent *event1 = [self dummyEvent];
    ZMUpdateEvent *event2 = [self dummyEvent];
    [self.sut addUpdateEvent:event1];
    [self.sut addUpdateEvent:event2];
    
    // expect
    [[(id)self.consumer expect] consumeUpdateEvents:@[]];
    
    // when
    [self.sut discardAllUpdateEvents];
    [self.sut processAllEventsInBuffer];
    
}

- (void)testThatItDiscardsASpecificEvent
{
    // given
    ZMUpdateEvent *event1 = [self dummyEvent];
    ZMUpdateEvent *event2 = [self dummyEvent];
    [self.sut addUpdateEvent:event1];
    [self.sut addUpdateEvent:event2];
    
    // expect
    [[(id)self.consumer expect] consumeUpdateEvents:@[event1]];
    [[(id)self.consumer reject] consumeUpdateEvents:@[event2]];
    
    // when
    [self.sut discardUpdateEventWithIdentifier:event2.uuid];
    [self.sut processAllEventsInBuffer];
    
}

@end
