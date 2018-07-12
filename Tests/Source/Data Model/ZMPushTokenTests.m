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
#import <WireSyncEngine/WireSyncEngine.h>
#import "WireSyncEngine_iOS_Tests-Swift.h"

@import WireDataModel;
@import WireSyncEngine;

@interface ZMPushTokenTests : MessagingTest
@property (nonatomic) NSString *identifier;
@property (nonatomic) NSString *transportType;
@end



@implementation ZMPushTokenTests

- (void)setUp
{
    [super setUp];
    self.identifier = @"foo-bar.baz";
    self.transportType = @"apns";
}

- (void)tearDown
{
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (BOOL)shouldUseInMemoryStore;
{
    return NO;
}

- (void)testThatItCanBeStoredInsideAManagedObjectContext;
{
    NSData * const deviceToken = [NSData dataWithBytes:(uint8_t[]){1, 0, 128, 255} length:4];

    // when
    self.uiMOC.pushKitToken = [[ZMPushToken alloc] initWithDeviceToken:deviceToken identifier:self.identifier transportType:self.transportType isRegistered:NO isMarkedForDeletion:NO];
    XCTAssert([self.uiMOC saveOrRollback]);

    // then
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMPushToken *tokenA = self.syncMOC.pushKitToken;

        XCTAssertNotNil(tokenA);
        XCTAssertEqualObjects(tokenA.deviceToken, deviceToken);
        XCTAssertEqualObjects(tokenA.appIdentifier, self.identifier);
        XCTAssertEqualObjects(tokenA.transportType, self.transportType);
        XCTAssertFalse(tokenA.isRegistered);
        XCTAssertFalse(tokenA.isMarkedForDeletion);
    }];

    // and when
    self.uiMOC.pushKitToken = [[ZMPushToken alloc] initWithDeviceToken:deviceToken identifier:self. identifier transportType:self.transportType isRegistered:YES isMarkedForDeletion:YES];
    XCTAssert([self.uiMOC saveOrRollback]);

    // then
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMPushToken *tokenB = self.syncMOC.pushKitToken;

        XCTAssertNotNil(tokenB);
        XCTAssertEqualObjects(tokenB.deviceToken, deviceToken);
        XCTAssertEqualObjects(tokenB.appIdentifier, self.identifier);
        XCTAssertEqualObjects(tokenB.transportType, self.transportType);
        XCTAssertTrue(tokenB.isRegistered);
        XCTAssertTrue(tokenB.isMarkedForDeletion);
    }];
}

- (void)testThatItCanBeStoredInsideAManagedObjectContextAsPushKitToken;
{
    NSData * const deviceToken = [NSData dataWithBytes:(uint8_t[]){1, 0, 128, 255} length:4];

    // when
    self.uiMOC.pushKitToken = [[ZMPushToken alloc] initWithDeviceToken:deviceToken identifier:self.identifier transportType:self.transportType isRegistered:NO isMarkedForDeletion:NO];
    XCTAssert([self.uiMOC saveOrRollback]);

    // then
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMPushToken *tokenA = self.syncMOC.pushKitToken;

        XCTAssertNotNil(tokenA);
        XCTAssertEqualObjects(tokenA.deviceToken, deviceToken);
        XCTAssertEqualObjects(tokenA.appIdentifier, self.identifier);
        XCTAssertEqualObjects(tokenA.transportType, self.transportType);
        XCTAssertFalse(tokenA.isRegistered);
        XCTAssertFalse(tokenA.isMarkedForDeletion);
    }];

    // and when
    self.uiMOC.pushKitToken = [[ZMPushToken alloc] initWithDeviceToken:deviceToken identifier:self.identifier transportType:self.transportType isRegistered:YES isMarkedForDeletion:YES];
    XCTAssert([self.uiMOC saveOrRollback]);

    // then
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMPushToken *tokenB = self.syncMOC.pushKitToken;

        XCTAssertNotNil(tokenB);
        XCTAssertEqualObjects(tokenB.deviceToken, deviceToken);
        XCTAssertEqualObjects(tokenB.appIdentifier, self.identifier);
        XCTAssertEqualObjects(tokenB.transportType, self.transportType);
        XCTAssertTrue(tokenB.isRegistered);
        XCTAssertTrue(tokenB.isMarkedForDeletion);

    }];
}

@end
