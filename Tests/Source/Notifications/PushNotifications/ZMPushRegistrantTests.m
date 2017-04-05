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
#import <WireSyncEngine/WireSyncEngine-Swift.h>
#import "ZMPushRegistrant.h"
@import PushKit;
@import UIKit;



@interface ZMPushRegistrantTests_PushKit : MessagingTest

@property (nonatomic) id mockRegistry;
@property (nonatomic) PushKitRegistrant *sut;

@property (nonatomic, copy) void(^didUpdateCredentials)(NSData *);
@property (nonatomic, copy) void(^didReceivePayload)(NSDictionary *, void(^)(ZMPushPayloadResult));
@property (nonatomic, copy) dispatch_block_t didInvalidateToken;

@end



@implementation ZMPushRegistrantTests_PushKit

- (void)setUp
{
    [super setUp];

    self.mockRegistry = [OCMockObject mockForClass:PKPushRegistry.class];
}

- (void)createSUT;
{
    self.sut = [[PushKitRegistrant alloc] initWithFakeRegistry:self.mockRegistry didUpdateCredentials:self.didUpdateCredentials didReceivePayload:self.didReceivePayload didInvalidateToken:self.didInvalidateToken];
}

- (void)tearDown
{
    self.sut = nil;
    self.mockRegistry = nil;
    [super tearDown];
}

- (void)testThatItIsCeated
{
    // given
    __block id delegate;
    [(PKPushRegistry *) [self.mockRegistry expect] setDelegate:ZM_ARG_SAVE(delegate)];
    [(PKPushRegistry *) [self.mockRegistry expect] setDesiredPushTypes:[NSSet setWithObject:PKPushTypeVoIP]];
    self.didUpdateCredentials = ^(NSData * ZM_UNUSED data){};
    self.didReceivePayload = ^(NSDictionary * ZM_UNUSED info, void(^result)(ZMPushPayloadResult) ZM_UNUSED){};
    self.didInvalidateToken = ^{};
    
    // when
    [self createSUT];
    
    // then
    XCTAssertNotNil(self.sut);
    XCTAssertEqual(delegate, self.sut);
}

- (id)mockCredentialsWithTokenData:(NSData *)data
{
    id credentials = [OCMockObject mockForClass:PKPushCredentials.class];
    (void)[(PKPushCredentials *) [[credentials stub] andReturn:data] token];
    (void)[(PKPushCredentials *) [[credentials stub] andReturn:PKPushTypeVoIP] type];
    return credentials;
}

- (void)testThatItForwardsCredentials;
{
    // given
    [(PKPushRegistry *) [self.mockRegistry stub] setDelegate:OCMOCK_ANY];
    [(PKPushRegistry *) [self.mockRegistry expect] setDesiredPushTypes:OCMOCK_ANY];
    XCTestExpectation *e = [self expectationWithDescription:@"credentials"];
    __block NSData *receivedData;
    self.didUpdateCredentials = ^(NSData * d){
        receivedData = d;
        [e fulfill];
    };
    ZM_WEAK(self);
    self.didReceivePayload = ^(NSDictionary * ZM_UNUSED info, void(^result)(ZMPushPayloadResult) ZM_UNUSED){
        ZM_STRONG(self);
        XCTFail();
    };
    self.didInvalidateToken = ^{
        ZM_STRONG(self);
        XCTFail();
    };
    NSData *token = [NSData dataWithBytes:"1234" length:4];
    
    // when
    [self createSUT];
    [self.sut pushRegistry:self.mockRegistry didUpdatePushCredentials:[self mockCredentialsWithTokenData:token] forType:PKPushTypeVoIP];
    
    // expect
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.1]);
    
    // then
    XCTAssertEqualObjects(receivedData, token);
}

- (id)mockPayloadWithInfo:(NSDictionary *)info;
{
    id credentials = [OCMockObject mockForClass:PKPushPayload.class];
    (void)[(PKPushPayload *) [[credentials stub] andReturn:info] dictionaryPayload];
    (void)[(PKPushPayload *) [[credentials stub] andReturn:PKPushTypeVoIP] type];
    return credentials;
}

- (void)testThatItForwardsPushPayload;
{
    // given
    [(PKPushRegistry *) [self.mockRegistry stub] setDelegate:OCMOCK_ANY];
    [(PKPushRegistry *) [self.mockRegistry expect] setDesiredPushTypes:OCMOCK_ANY];
    XCTestExpectation *e = [self expectationWithDescription:@"payload"];
    ZM_WEAK(self);
    self.didUpdateCredentials = ^(NSData * ZM_UNUSED d){
        ZM_STRONG(self);
        XCTFail();
    };
    __block NSDictionary *receivedPayload;
    self.didReceivePayload = ^(NSDictionary *p, void(^result)(ZMPushPayloadResult)){
        receivedPayload = p;
        result(ZMPushPayloadResultSuccess);
        [e fulfill];
    };
    self.didInvalidateToken = ^{
        ZM_STRONG(self);
        XCTFail();
    };
    NSDictionary *payload = @{@"foo": @42};
    
    // when
    [self createSUT];
    [self.sut pushRegistry:self.mockRegistry didReceiveIncomingPushWithPayload:[self mockPayloadWithInfo:payload] forType:PKPushTypeVoIP];
    
    // expect
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.1]);
    
    // then
    XCTAssertEqualObjects(receivedPayload, payload);
}

@end



#pragma mark -


@interface ZMPushRegistrantTests_AppDelegate : MessagingTest

@property (nonatomic) ApplicationRemoteNotification *sut;

@property (nonatomic, copy) void(^didUpdateCredentials)(NSData *);
@property (nonatomic, copy) void(^didReceivePayload)(NSDictionary *, void(^)(ZMPushPayloadResult));
@property (nonatomic, copy) dispatch_block_t didInvalidateToken;

@end



@implementation ZMPushRegistrantTests_AppDelegate

- (void)setUp
{
    [super setUp];
}

- (void)createSUT;
{
    self.sut = [[ApplicationRemoteNotification alloc] initWithDidUpdateCredentials:self.didUpdateCredentials didReceivePayload:self.didReceivePayload didInvalidateToken:self.didInvalidateToken];
}

- (void)tearDown
{
    self.sut = nil;
    [super tearDown];
}

- (void)testThatItForwardsCredentials;
{
    // given
    XCTestExpectation *e = [self expectationWithDescription:@"credentials"];
    __block NSData *receivedData;
    self.didUpdateCredentials = ^(NSData * d){
        receivedData = d;
        [e fulfill];
    };
    ZM_WEAK(self);
    self.didReceivePayload = ^(NSDictionary * ZM_UNUSED info, void(^result)(ZMPushPayloadResult) ZM_UNUSED){
        ZM_STRONG(self);
        XCTFail();
    };
    self.didInvalidateToken = ^{
        ZM_STRONG(self);
        XCTFail();
    };
    NSData *token = [NSData dataWithBytes:"1234" length:4];
    
    // when
    [self createSUT];
    [self.sut application:self.application didRegisterForRemoteNotificationsWithDeviceToken:token];
    
    // expect
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.1]);
    
    // then
    XCTAssertEqualObjects(receivedData, token);
}

- (void)testThatItForwardsPushPayload;
{
    // given
    XCTestExpectation *e = [self expectationWithDescription:@"payload"];
    ZM_WEAK(self);
    self.didUpdateCredentials = ^(NSData * ZM_UNUSED d){
        ZM_STRONG(self);
        XCTFail();
    };
    __block NSDictionary *receivedPayload;
    self.didReceivePayload = ^(NSDictionary *p, void(^result)(ZMPushPayloadResult)){
        receivedPayload = p;
        result(ZMPushPayloadResultSuccess);
        [e fulfill];
    };
    self.didInvalidateToken = ^{
        ZM_STRONG(self);
        XCTFail();
    };
    NSDictionary *payload = @{@"foo": @42};
    
    // when
    [self createSUT];
    XCTestExpectation *e2 = [self expectationWithDescription:@"fetch complete"];
    [self.sut application:self.application didReceiveRemoteNotification:payload fetchCompletionHandler:^(UIBackgroundFetchResult r) {
        XCTAssertEqual(r, UIBackgroundFetchResultNewData);
        [e2 fulfill];
    }];
    
    // expect
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.1]);
    
    // then
    XCTAssertEqualObjects(receivedPayload, payload);
}

@end
