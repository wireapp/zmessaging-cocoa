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
#import "ZMPushToken.h"



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

- (void)testThatItCanParseDeviceTokenStrings;
{
    // given
    NSString *tokenString = @"c5e24e41e4d4329037928449349487547ef14f162c77aee3aa8e12a39c8db1d5";
    uint8_t const tokenBytes[] = {
        0xc5, 0xe2, 0x4e, 0x41, 0xe4, 0xd4, 0x32, 0x90, 0x37, 0x92, 0x84, 0x49, 0x34, 0x94, 0x87, 0x54, 0x7e, 0xf1, 0x4f, 0x16, 0x2c, 0x77, 0xae, 0xe3, 0xaa, 0x8e, 0x12, 0xa3, 0x9c, 0x8d, 0xb1, 0xd5,
    };
    NSData *deviceToken = [NSData dataWithBytes:tokenBytes length:sizeof(tokenBytes)];
    
    // then
    XCTAssertEqualObjects([tokenString zmDeviceTokenData], deviceToken);
    XCTAssertNil([@"c5e24e41e4d4329037928449349487547ef14f162c77aee3aa8e12a39c8db1d" zmDeviceTokenData]);
    XCTAssertNil([@"c" zmDeviceTokenData]);
}

- (void)testThatItCanBeArchived
{
    for (int i = 0; i < 2; ++i) {
        // given
        NSData * const deviceToken = [NSData dataWithBytes:(uint8_t[]){1, 0, 128, 255} length:4];
        BOOL const isRegistered = (i == 1);
        ZMPushToken *token = [[ZMPushToken alloc] initWithDeviceToken:deviceToken identifier:self.identifier transportType:self.transportType isRegistered:isRegistered];
        
        // when
        NSMutableData *archive = [NSMutableData data];
        NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:archive];
        archiver.requiresSecureCoding = YES;
        [archiver encodeObject:token forKey:@"token"];
        [archiver finishEncoding];
        
        NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:archive];
        unarchiver.requiresSecureCoding = YES;
        ZMPushToken *unarchivedToken = [unarchiver decodeObjectOfClass:ZMPushToken.class forKey:@"token"];
        
        // then
        XCTAssertNotNil(unarchivedToken);
        XCTAssertEqualObjects(unarchivedToken.deviceToken, deviceToken);
        XCTAssertEqualObjects(unarchivedToken.appIdentifier, self.identifier);
        XCTAssertEqualObjects(unarchivedToken.transportType, self.transportType);
        XCTAssertEqual(unarchivedToken.isRegistered, isRegistered);
    }
}

- (void)testThatItCanBeStoredInsideAManagedObjectContext;
{
    NSData * const deviceToken = [NSData dataWithBytes:(uint8_t[]){1, 0, 128, 255} length:4];
    
    // when
    self.uiMOC.pushKitToken = [[ZMPushToken alloc] initWithDeviceToken:deviceToken identifier:self.identifier transportType:self.transportType isRegistered:NO];
    XCTAssert([self.uiMOC saveOrRollback]);
    
    // then
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMPushToken *tokenA = self.syncMOC.pushKitToken;
        
        XCTAssertNotNil(tokenA);
        XCTAssertEqualObjects(tokenA.deviceToken, deviceToken);
        XCTAssertEqualObjects(tokenA.appIdentifier, self.identifier);
        XCTAssertEqualObjects(tokenA.transportType, self.transportType);
        XCTAssertFalse(tokenA.isRegistered);
    }];
    
    // and when
    self.uiMOC.pushKitToken = [[ZMPushToken alloc] initWithDeviceToken:deviceToken identifier:self. identifier transportType:self.transportType isRegistered:YES];
    XCTAssert([self.uiMOC saveOrRollback]);
    
    // then
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMPushToken *tokenB = self.syncMOC.pushKitToken;
        
        XCTAssertNotNil(tokenB);
        XCTAssertEqualObjects(tokenB.deviceToken, deviceToken);
        XCTAssertEqualObjects(tokenB.appIdentifier, self.identifier);
        XCTAssertEqualObjects(tokenB.transportType, self.transportType);
        XCTAssertTrue(tokenB.isRegistered);
    }];
}

- (void)testThatItCanBeStoredInsideAManagedObjectContextAsPushKitToken;
{
    NSData * const deviceToken = [NSData dataWithBytes:(uint8_t[]){1, 0, 128, 255} length:4];
    
    // when
    self.uiMOC.pushKitToken = [[ZMPushToken alloc] initWithDeviceToken:deviceToken identifier:self.identifier transportType:self.transportType isRegistered:NO];
    XCTAssert([self.uiMOC saveOrRollback]);
    
    // then
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMPushToken *tokenA = self.syncMOC.pushKitToken;
        
        XCTAssertNotNil(tokenA);
        XCTAssertEqualObjects(tokenA.deviceToken, deviceToken);
        XCTAssertEqualObjects(tokenA.appIdentifier, self.identifier);
        XCTAssertEqualObjects(tokenA.transportType, self.transportType);
        XCTAssertFalse(tokenA.isRegistered);
    }];
    
    // and when
    self.uiMOC.pushKitToken = [[ZMPushToken alloc] initWithDeviceToken:deviceToken identifier:self.identifier transportType:self.transportType isRegistered:YES];
    XCTAssert([self.uiMOC saveOrRollback]);
    
    // then
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMPushToken *tokenB = self.syncMOC.pushKitToken;
        
        XCTAssertNotNil(tokenB);
        XCTAssertEqualObjects(tokenB.deviceToken, deviceToken);
        XCTAssertEqualObjects(tokenB.appIdentifier, self.identifier);
        XCTAssertEqualObjects(tokenB.transportType, self.transportType);
        XCTAssertTrue(tokenB.isRegistered);
    }];
}

- (void)testThatItComparesEqualRegardlessOfBeingRegisteredOrNot;
{
    // given
    NSData * const token = [@"whoa!" dataUsingEncoding:NSUTF8StringEncoding];
    
    // when
    ZMPushToken *tokenA = [[ZMPushToken alloc] initWithDeviceToken:token identifier:self.identifier transportType:self.transportType isRegistered:NO];
    ZMPushToken *tokenB = [[ZMPushToken alloc] initWithDeviceToken:token identifier:self.identifier transportType:self.transportType isRegistered:YES];
    
    XCTAssertEqualObjects(tokenA, tokenB);
}

- (void)testThatItCreatesAnUnregisteredCopy;
{
    // given
    NSData * const token = [@"whoa!" dataUsingEncoding:NSUTF8StringEncoding];
    
    ZMPushToken *tokenA = [[ZMPushToken alloc] initWithDeviceToken:token identifier:self.identifier transportType:self.transportType isRegistered:YES];
    
    // when
    ZMPushToken *tokenB = [tokenA unregisteredCopy];
    
    // then
    XCTAssertEqualObjects(tokenA, tokenB);
    XCTAssertFalse(tokenB.isRegistered);
}

@end
