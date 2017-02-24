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


#import "MessagingTest.h"
#import "ZMCallStateLogger.h"
#import "ZMCallFlowRequestStrategy.h"
#import "ZMUserSession+Internal.h"

@interface ZMCallStateLoggerTests : MessagingTest

@property (nonatomic) ZMCallStateLogger *sut;
@property (nonatomic) id mockFlowSync;

@end

@implementation ZMCallStateLoggerTests

- (void)setUp {
    [super setUp];
    self.mockFlowSync = [OCMockObject niceMockForClass:[ZMCallFlowRequestStrategy class]];
    [self verifyMockLater:self.mockFlowSync];
    
    self.sut = [[ZMCallStateLogger alloc] initWithFlowSync:self.mockFlowSync];
}

- (void)tearDown {
    [self.mockFlowSync stopMocking];
    self.mockFlowSync = nil;
    self.sut = nil;
    [super tearDown];
}


- (void)testThatItDoesNotAddLoggsWithoutSpecifiedConversationID
{
    // given
    NSString *message = @"Add This to the Log";
    
    // expect
    [[self.mockFlowSync reject] appendLogForConversationID:nil message:message];
    
    // when
    [[NSNotificationCenter defaultCenter] postNotificationName:ZMAppendAVSLogNotificationName object:nil userInfo:@{@"message": message}];
}



@end
