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


@import ZMTransport;
@import zmessaging;
@import ZMCDataModel;

#import "MessagingTest.h"
#import "ZMPushTokenTranscoder.h"
#import "ZMPushToken.h"
#import "ZMContextChangeTracker.h"
#import "ZMSingleRequestSync.h"
#import <zmessaging/zmessaging-Swift.h>

static NSString * const FallbackAPNS = @"APNS";

@interface ZMPushTokenTranscoderTests : MessagingTest

@property (nonatomic) ZMPushTokenTranscoder *sut;
@property (nonatomic) NSData *deviceToken;
@property (nonatomic) NSString *deviceTokenString;
@property (nonatomic) NSData *deviceTokenB;
@property (nonatomic) NSString *deviceTokenBString;
@property (nonatomic) NSString *identifier;
@property (nonatomic) NSString *transportTypeNormal;
@property (nonatomic) NSString *transportTypeVOIP;
@property (nonatomic) id mockClientStatus;

- (UserClient *)simulateRegisteredClient;

@end



@implementation ZMPushTokenTranscoderTests

- (void)setUp
{
    [super setUp];
    self.mockClientStatus = [OCMockObject niceMockForClass:[ZMClientRegistrationStatus class]];
    self.sut = [[ZMPushTokenTranscoder alloc] initWithManagedObjectContext:self.uiMOC clientRegistrationStatus:self.mockClientStatus];
    
    // jot -r -w %02x -s '' 32
    self.deviceTokenString = @"c5e24e41e4d4329037928449349487547ef14f162c77aee3aa8e12a39c8db1d5";
    self.deviceToken = [self.deviceTokenString zmDeviceTokenData];
    
    self.deviceTokenBString = @"0c11633011485c4558615009045b022d565e0c380a5330444d3a0f4b185a014a";
    self.deviceTokenB = [self.deviceTokenBString zmDeviceTokenData];
    
    self.identifier = @"com.wire.zclient";
    self.transportTypeNormal = @"APNS";
    self.transportTypeVOIP = @"APNS_VOIP";
}

- (void)tearDown
{
    [self.sut tearDown];
    self.sut = nil;
    
    [super tearDown];
}


- (void)testThatItReturnsTheContextChangeTrackers;
{
    // when
    NSArray *trackers = self.sut.contextChangeTrackers;
    
    // then
    XCTAssertEqualObjects(trackers, @[self.sut]);
}

- (void)testThatItDoesNotReturnARequestWhenThereIsNoPushToken;
{
    // given
    self.uiMOC.pushToken = nil;
    self.uiMOC.pushKitToken = nil;
    
    // when
    ZMTransportRequest *req = [self.sut.requestGenerators nextRequest];
    
    // then
    XCTAssertNil(req);
}

- (void)testThatItDoesNotReturnAFetchRequest
{
    // when
    NSFetchRequest *request = [self.sut fetchRequestForTrackedObjects];
    
    // then
    XCTAssertNil(request);
    
}

- (UserClient *)simulateRegisteredClient
{
    UserClient *client = [UserClient insertNewObjectInManagedObjectContext:self.uiMOC];
    client.remoteIdentifier = @"TheClientID";
    client.user = [ZMUser selfUserInContext:self.uiMOC];
    
    [self.uiMOC setPersistentStoreMetadata:client.remoteIdentifier forKey:@"PersistedClientId"];
    [self.uiMOC saveOrRollback];
    return client;
}

@end



@implementation ZMPushTokenTranscoderTests (ReRegister)

- (void)testThatItMarksATokenAsNotRegisteredWhenReceivingAPushRemoveEvent_ApplicationToken
{
    // given
    self.uiMOC.pushToken = [[ZMPushToken alloc] initWithDeviceToken:self.deviceToken identifier:self.identifier transportType:self.transportTypeNormal fallback:nil isRegistered:YES];
    self.uiMOC.pushKitToken = [[ZMPushToken alloc] initWithDeviceToken:self.deviceTokenB identifier:self.identifier transportType:self.transportTypeVOIP fallback:FallbackAPNS isRegistered:YES];
    XCTAssert([self.uiMOC save:nil]);
    ZMUpdateEvent *updateEvent = [ZMUpdateEvent eventFromEventStreamPayload:@{@"type": @"user.push-remove",
                                                                              @"token": self.deviceTokenString} uuid:nil];
    
    // when
    [self.syncMOC performGroupedBlockAndWait:^{
        [self.sut processEvents:@[updateEvent] liveEvents:YES prefetchResult:nil];
        XCTAssert([self.uiMOC save:nil]);
    }];
    
    // then
    XCTAssertNotNil(self.uiMOC.pushToken);
    XCTAssertEqualObjects(self.uiMOC.pushToken.deviceToken, self.deviceToken);
    XCTAssertFalse(self.uiMOC.pushToken.isRegistered);
    
    XCTAssertNotNil(self.uiMOC.pushKitToken);
    XCTAssertEqualObjects(self.uiMOC.pushKitToken.deviceToken, self.deviceTokenB);
    XCTAssertFalse(self.uiMOC.pushKitToken.isRegistered);
}

- (void)testThatItMarksATokenAsNotRegisteredWhenReceivingAPushRemoveEvent_PushKit
{
    // given
    self.uiMOC.pushToken = [[ZMPushToken alloc] initWithDeviceToken:self.deviceToken identifier:self.identifier transportType:self.transportTypeNormal fallback:nil isRegistered:YES];
    self.uiMOC.pushKitToken = [[ZMPushToken alloc] initWithDeviceToken:self.deviceTokenB identifier:self.identifier transportType:self.transportTypeVOIP fallback:FallbackAPNS isRegistered:YES];
    XCTAssert([self.uiMOC save:nil]);
    ZMUpdateEvent *updateEvent = [ZMUpdateEvent eventFromEventStreamPayload:@{@"type": @"user.push-remove",
                                                                              @"token": self.deviceTokenBString} uuid:nil];
    
    // when
    [self.syncMOC performGroupedBlockAndWait:^{
        [self.sut processEvents:@[updateEvent] liveEvents:YES prefetchResult:nil];
        XCTAssert([self.uiMOC save:nil]);
    }];
    
    // then
    XCTAssertNotNil(self.uiMOC.pushToken);
    XCTAssertEqualObjects(self.uiMOC.pushToken.deviceToken, self.deviceToken);
    XCTAssertFalse(self.uiMOC.pushToken.isRegistered);
    
    XCTAssertNotNil(self.uiMOC.pushKitToken);
    XCTAssertEqualObjects(self.uiMOC.pushKitToken.deviceToken, self.deviceTokenB);
    XCTAssertFalse(self.uiMOC.pushKitToken.isRegistered);
}

@end



@implementation ZMPushTokenTranscoderTests (ApplicationToken)

- (void)testThatItReturnsARequestWhenThePushTokenIsNotRegistered;
{
    // given
    [(ZMClientRegistrationStatus *)[[self.mockClientStatus expect] andReturnValue:OCMOCK_VALUE(ZMClientRegistrationPhaseRegistered)] currentPhase];
    
    self.uiMOC.pushToken = [[ZMPushToken alloc] initWithDeviceToken:self.deviceToken identifier:self.identifier transportType:self.transportTypeNormal fallback:nil isRegistered:NO];
    XCTAssert([self.uiMOC save:nil]);
    for (id<ZMContextChangeTracker> t in [self.sut contextChangeTrackers]) {
        [t objectsDidChange:[NSSet set]];
    }
    
    // when
    ZMTransportRequest *req = [self.sut.requestGenerators nextRequest];
    
    
    // then
    XCTAssertNotNil(req);
    XCTAssertEqual(req.method, ZMMethodPOST);
    XCTAssertEqualObjects(req.path, @"/push/tokens");
    NSDictionary *expectedPayload = @{@"token": @"c5e24e41e4d4329037928449349487547ef14f162c77aee3aa8e12a39c8db1d5",
                                      @"app": @"com.wire.zclient",
                                      @"transport": @"APNS"};
    XCTAssertEqualObjects(req.payload, expectedPayload);
}

- (void)testThatItAddsTheClientIDIfTheClientIsSpecified_Application
{
    // given
    [(ZMClientRegistrationStatus *)[[self.mockClientStatus expect] andReturnValue:OCMOCK_VALUE(ZMClientRegistrationPhaseRegistered)] currentPhase];

    UserClient *client = [self simulateRegisteredClient];
    self.uiMOC.pushToken = [[ZMPushToken alloc] initWithDeviceToken:self.deviceToken identifier:self.identifier transportType:self.transportTypeNormal fallback:nil isRegistered:NO];
    XCTAssert([self.uiMOC save:nil]);
    for (id<ZMContextChangeTracker> t in [self.sut contextChangeTrackers]) {
        [t objectsDidChange:[NSSet set]];
    }
    
    // when
    ZMTransportRequest *req = [self.sut.requestGenerators nextRequest];

    // then
    XCTAssertNotNil(req);
    XCTAssertEqual(req.method, ZMMethodPOST);
    XCTAssertEqualObjects(req.path, @"/push/tokens");
    NSDictionary *expectedPayload = @{@"token": @"c5e24e41e4d4329037928449349487547ef14f162c77aee3aa8e12a39c8db1d5",
                                      @"app": @"com.wire.zclient",
                                      @"transport": @"APNS",
                                      @"client": client.remoteIdentifier};
    XCTAssertEqualObjects(req.payload, expectedPayload);
}

- (void)testThatItMarksThePushTokenAsRegisteredWhenTheRequestCompletes;
{
    // given
    [(ZMClientRegistrationStatus *)[[self.mockClientStatus expect] andReturnValue:OCMOCK_VALUE(ZMClientRegistrationPhaseRegistered)] currentPhase];

    self.uiMOC.pushToken = [[ZMPushToken alloc] initWithDeviceToken:self.deviceToken identifier:self.identifier transportType:self.transportTypeNormal fallback:nil isRegistered:NO];
    XCTAssert([self.uiMOC save:nil]);
    for (id<ZMContextChangeTracker> t in [self.sut contextChangeTrackers]) {
        [t objectsDidChange:[NSSet set]];
    }
    NSDictionary *responsePayload = @{@"token": @"aabbccddeeff",
                                      @"app": @"foo.bar",
                                      @"transport": @"APNS"};
    ZMTransportResponse *response = [[ZMTransportResponse alloc] initWithPayload:responsePayload HTTPStatus:201 transportSessionError:nil headers:@{}];
    
    
    // when
    ZMTransportRequest *req = [self.sut.requestGenerators nextRequest];
    [req completeWithResponse:response];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertNotNil(self.uiMOC.pushToken);
    XCTAssertTrue(self.uiMOC.pushToken.isRegistered);
    XCTAssertEqualObjects(self.uiMOC.pushToken.appIdentifier, @"foo.bar");
    NSData *newDeviceToken = [NSData dataWithBytes:(const uint8_t []){0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff} length:6];
    XCTAssertEqualObjects(self.uiMOC.pushToken.deviceToken, newDeviceToken);
}

- (void)testThatItDoesNotRegisterThePushTokenAgainAfterTheRequestCompletes;
{
    // given
    [(ZMClientRegistrationStatus *)[[self.mockClientStatus expect] andReturnValue:OCMOCK_VALUE(ZMClientRegistrationPhaseRegistered)] currentPhase];

    self.uiMOC.pushToken = [[ZMPushToken alloc] initWithDeviceToken:self.deviceToken identifier:self.identifier transportType:self.transportTypeNormal fallback:nil isRegistered:NO];
    XCTAssert([self.uiMOC save:nil]);
    for (id<ZMContextChangeTracker> t in [self.sut contextChangeTrackers]) {
        [t objectsDidChange:[NSSet set]];
    }
    NSDictionary *responsePayload = @{@"token": @"aabbccddeeff",
                                      @"app": @"foo.bar",
                                      @"transport": @"APNS"};
    ZMTransportResponse *response = [[ZMTransportResponse alloc] initWithPayload:responsePayload HTTPStatus:201 transportSessionError:nil headers:@{}];
    
    
    // when
    ZMTransportRequest *req = [self.sut.requestGenerators nextRequest];
    XCTAssertNotNil(req);
    [req completeWithResponse:response];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertNotNil(self.uiMOC.pushToken);
    for (id<ZMContextChangeTracker> t in [self.sut contextChangeTrackers]) {
        [t objectsDidChange:[NSSet set]];
    }
    
    // and when
    ZMTransportRequest *req2 = [self.sut.requestGenerators nextRequest];
    XCTAssertNil(req2);
}

@end



@implementation ZMPushTokenTranscoderTests (PuskKit)

- (void)testThatItReturnsNoRequestIfTheClientIsNotRegistered;
{
    // given
    [(ZMClientRegistrationStatus *)[[self.mockClientStatus expect] andReturnValue:OCMOCK_VALUE(ZMClientRegistrationPhaseUnregistered)] currentPhase];
    
    self.uiMOC.pushKitToken = [[ZMPushToken alloc] initWithDeviceToken:self.deviceToken identifier:self.identifier transportType:self.transportTypeVOIP fallback:FallbackAPNS isRegistered:NO];
    XCTAssert([self.uiMOC save:nil]);
    for (id<ZMContextChangeTracker> t in [self.sut contextChangeTrackers]) {
        [t objectsDidChange:[NSSet set]];
    }
    
    // when
    ZMTransportRequest *req = [self.sut.requestGenerators nextRequest];
    
    
    // then
    XCTAssertNil(req);
}

- (void)testThatItReturnsARequestWhenThePushKitTokenIsNotRegistered;
{
    // given
    [(ZMClientRegistrationStatus *)[[self.mockClientStatus expect] andReturnValue:OCMOCK_VALUE(ZMClientRegistrationPhaseRegistered)] currentPhase];

    self.uiMOC.pushKitToken = [[ZMPushToken alloc] initWithDeviceToken:self.deviceToken identifier:self.identifier transportType:self.transportTypeVOIP fallback:FallbackAPNS isRegistered:NO];
    XCTAssert([self.uiMOC save:nil]);
    for (id<ZMContextChangeTracker> t in [self.sut contextChangeTrackers]) {
        [t objectsDidChange:[NSSet set]];
    }
    
    // when
    ZMTransportRequest *req = [self.sut.requestGenerators nextRequest];
    
    
    // then
    XCTAssertNotNil(req);
    XCTAssertEqual(req.method, ZMMethodPOST);
    XCTAssertEqualObjects(req.path, @"/push/tokens");
    NSDictionary *expectedPayload = @{
                                      @"token": @"c5e24e41e4d4329037928449349487547ef14f162c77aee3aa8e12a39c8db1d5",
                                      @"app": @"com.wire.zclient",
                                      @"transport": @"APNS_VOIP",
                                      @"fallback": @"APNS"
                                      };
    XCTAssertEqualObjects(req.payload, expectedPayload);
}

- (void)testThatItDoesNotIncludeFallbackInRequestWhenNotSet
{
    // given
    [(ZMClientRegistrationStatus *)[[self.mockClientStatus expect] andReturnValue:OCMOCK_VALUE(ZMClientRegistrationPhaseRegistered)] currentPhase];
    
    self.uiMOC.pushKitToken = [[ZMPushToken alloc] initWithDeviceToken:self.deviceToken identifier:self.identifier transportType:self.transportTypeVOIP fallback:FallbackAPNS isRegistered:NO];
    XCTAssert([self.uiMOC save:nil]);
    for (id<ZMContextChangeTracker> t in [self.sut contextChangeTrackers]) {
        [t objectsDidChange:[NSSet set]];
    }
    
    // when
    ZMTransportRequest *req = [self.sut.requestGenerators nextRequest];
    
    
    // then
    XCTAssertNotNil(req);
    XCTAssertEqual(req.method, ZMMethodPOST);
    XCTAssertEqualObjects(req.path, @"/push/tokens");
    NSDictionary *expectedPayload = @{
                                      @"token": @"c5e24e41e4d4329037928449349487547ef14f162c77aee3aa8e12a39c8db1d5",
                                      @"app": @"com.wire.zclient",
                                      @"transport": @"APNS_VOIP",
                                      @"fallback": @"APNS"
                                      };
    XCTAssertEqualObjects(req.payload, expectedPayload);
}

- (void)testThatItAddsTheClientIDIfTheClientIsSpecified_PushKit
{
    // given
    [(ZMClientRegistrationStatus *)[[self.mockClientStatus expect] andReturnValue:OCMOCK_VALUE(ZMClientRegistrationPhaseRegistered)] currentPhase];

    UserClient *client = [self simulateRegisteredClient];
    self.uiMOC.pushKitToken = [[ZMPushToken alloc] initWithDeviceToken:self.deviceToken identifier:self.identifier transportType:self.transportTypeVOIP fallback:FallbackAPNS isRegistered:NO];
    XCTAssert([self.uiMOC save:nil]);
    for (id<ZMContextChangeTracker> t in [self.sut contextChangeTrackers]) {
        [t objectsDidChange:[NSSet set]];
    }
    
    // when
    ZMTransportRequest *req = self.sut.requestGenerators.nextRequest;
    
    // then
    XCTAssertNotNil(req);
    XCTAssertEqual(req.method, ZMMethodPOST);
    XCTAssertEqualObjects(req.path, @"/push/tokens");
    NSDictionary *expectedPayload = @{
                                      @"token": @"c5e24e41e4d4329037928449349487547ef14f162c77aee3aa8e12a39c8db1d5",
                                      @"app": self.identifier,
                                      @"transport": self.transportTypeVOIP,
                                      @"client": client.remoteIdentifier,
                                      @"fallback": @"APNS"
                                      };
    
    XCTAssertEqualObjects(req.payload, expectedPayload);
}


- (void)testThatItMarksThePushKitTokenAsRegisteredWhenTheRequestCompletes;
{
    // given
    [(ZMClientRegistrationStatus *)[[self.mockClientStatus expect] andReturnValue:OCMOCK_VALUE(ZMClientRegistrationPhaseRegistered)] currentPhase];

    self.uiMOC.pushKitToken = [[ZMPushToken alloc] initWithDeviceToken:self.deviceToken identifier:self.identifier transportType:self.transportTypeVOIP fallback:FallbackAPNS isRegistered:NO];
    XCTAssert([self.uiMOC save:nil]);
    for (id<ZMContextChangeTracker> t in [self.sut contextChangeTrackers]) {
        [t objectsDidChange:[NSSet set]];
    }
    NSDictionary *responsePayload = @{
                                      @"token": @"aabbccddeeff",
                                      @"app": @"foo.bar-voip",
                                      @"transport": @"APNS_VOIP",
                                      @"fallback": @"APNS"
                                      };
    ZMTransportResponse *response = [[ZMTransportResponse alloc] initWithPayload:responsePayload HTTPStatus:201 transportSessionError:nil headers:@{}];
    
    
    // when
    ZMTransportRequest *req = [self.sut.requestGenerators nextRequest];
    [req completeWithResponse:response];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertNotNil(self.uiMOC.pushKitToken);
    XCTAssertTrue(self.uiMOC.pushKitToken.isRegistered);
    XCTAssertEqualObjects(self.uiMOC.pushKitToken.appIdentifier, @"foo.bar-voip");
    XCTAssertEqualObjects(self.uiMOC.pushKitToken.transportType, @"APNS_VOIP");
    NSData *newDeviceToken = [NSData dataWithBytes:(const uint8_t []){0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff} length:6];
    XCTAssertEqualObjects(self.uiMOC.pushKitToken.deviceToken, newDeviceToken);
}

- (void)testThatItDoesNotRegisterThePushKitTokenAgainAfterTheRequestCompletes;
{
    // given
    [(ZMClientRegistrationStatus *)[[self.mockClientStatus expect] andReturnValue:OCMOCK_VALUE(ZMClientRegistrationPhaseRegistered)] currentPhase];

    self.uiMOC.pushKitToken = [[ZMPushToken alloc] initWithDeviceToken:self.deviceToken identifier:self.identifier transportType:self.transportTypeVOIP fallback:FallbackAPNS isRegistered:NO];
    XCTAssert([self.uiMOC save:nil]);
    for (id<ZMContextChangeTracker> t in [self.sut contextChangeTrackers]) {
        [t objectsDidChange:[NSSet set]];
    }
    NSDictionary *responsePayload = @{
                                      @"token": @"aabbccddeeff",
                                      @"app": @"foo.bar-voip",
                                      @"transport": @"APNS",
                                      @"fallback": @"APNS"
                                      };
    ZMTransportResponse *response = [[ZMTransportResponse alloc] initWithPayload:responsePayload HTTPStatus:201 transportSessionError:nil headers:@{}];
    
    
    // when
    ZMTransportRequest *req = [self.sut.requestGenerators nextRequest];
    XCTAssertNotNil(req);
    [req completeWithResponse:response];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertNotNil(self.uiMOC.pushKitToken);
    for (id<ZMContextChangeTracker> t in [self.sut contextChangeTrackers]) {
        [t objectsDidChange:[NSSet set]];
    }
    
    // and when
    ZMTransportRequest *req2 = [self.sut.requestGenerators nextRequest];
    XCTAssertNil(req2);
}

- (void)testThatItSyncsTokensThatWereMarkedToDeleteAndDeletesThem_PushKit
{
    // given
    [(ZMClientRegistrationStatus *)[[self.mockClientStatus expect] andReturnValue:OCMOCK_VALUE(ZMClientRegistrationPhaseRegistered)] currentPhase];

    self.uiMOC.pushKitToken = [[ZMPushToken alloc] initWithDeviceToken:self.deviceToken identifier:self.identifier transportType:self.transportTypeVOIP fallback:FallbackAPNS isRegistered:YES];
    self.uiMOC.pushKitToken = [self.uiMOC.pushKitToken forDeletionMarkedCopy];
    XCTAssert([self.uiMOC save:nil]);
    XCTAssertNotNil(self.uiMOC.pushKitToken);

    
    for (id<ZMContextChangeTracker> t in [self.sut contextChangeTrackers]) {
        [t objectsDidChange:[NSSet set]];
    }
    ZMTransportResponse *response = [[ZMTransportResponse alloc] initWithPayload:nil HTTPStatus:200 transportSessionError:nil headers:@{}];
    
    // when
    ZMTransportRequest *req = [self.sut.requestGenerators nextRequest];
    XCTAssertNotNil(req);
    XCTAssertEqual(req.method, ZMMethodDELETE);
    XCTAssertTrue([req.path containsString:@"push/tokens"]);
    XCTAssertNil(req.payload);
    
    [req completeWithResponse:response];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertNil(self.uiMOC.pushKitToken);
    for (id<ZMContextChangeTracker> t in [self.sut contextChangeTrackers]) {
        [t objectsDidChange:[NSSet set]];
    }
    
    // and when
    ZMTransportRequest *req2 = [self.sut.requestGenerators nextRequest];
    XCTAssertNil(req2);
}

- (void)testThatItSyncsTokensThatWereMarkedToDeleteAndDeletesThem_RemotePush
{
    // given
    [(ZMClientRegistrationStatus *)[[self.mockClientStatus expect] andReturnValue:OCMOCK_VALUE(ZMClientRegistrationPhaseRegistered)] currentPhase];
    
    self.uiMOC.pushToken = [[ZMPushToken alloc] initWithDeviceToken:self.deviceToken identifier:self.identifier transportType:self.transportTypeNormal fallback:nil isRegistered:YES];
    self.uiMOC.pushToken = [self.uiMOC.pushToken forDeletionMarkedCopy];
    XCTAssert([self.uiMOC save:nil]);
    XCTAssertNotNil(self.uiMOC.pushToken);
    
    
    for (id<ZMContextChangeTracker> t in [self.sut contextChangeTrackers]) {
        [t objectsDidChange:[NSSet set]];
    }
    ZMTransportResponse *response = [[ZMTransportResponse alloc] initWithPayload:nil HTTPStatus:200 transportSessionError:nil headers:@{}];
    
    // when
    ZMTransportRequest *req = [self.sut.requestGenerators nextRequest];
    XCTAssertNotNil(req);
    XCTAssertEqual(req.method, ZMMethodDELETE);
    XCTAssertTrue([req.path containsString:@"push/tokens"]);
    XCTAssertNil(req.payload);
    
    [req completeWithResponse:response];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertNil(self.uiMOC.pushToken);
    for (id<ZMContextChangeTracker> t in [self.sut contextChangeTrackers]) {
        [t objectsDidChange:[NSSet set]];
    }
    
    // and when
    ZMTransportRequest *req2 = [self.sut.requestGenerators nextRequest];
    XCTAssertNil(req2);
}

- (void)testThatItDoesNotDeleteTokensThatAreNotMarkedForDeletion
{
    // given
    [(ZMClientRegistrationStatus *)[[self.mockClientStatus expect] andReturnValue:OCMOCK_VALUE(ZMClientRegistrationPhaseRegistered)] currentPhase];

    self.uiMOC.pushKitToken = [[ZMPushToken alloc] initWithDeviceToken:self.deviceToken identifier:self.identifier transportType:self.transportTypeVOIP fallback:FallbackAPNS isRegistered:YES];
    self.uiMOC.pushKitToken = [self.uiMOC.pushKitToken forDeletionMarkedCopy];
    XCTAssert([self.uiMOC save:nil]);
    XCTAssertNotNil(self.uiMOC.pushKitToken);
    
    
    for (id<ZMContextChangeTracker> t in [self.sut contextChangeTrackers]) {
        [t objectsDidChange:[NSSet set]];
    }
    ZMTransportResponse *response = [[ZMTransportResponse alloc] initWithPayload:nil HTTPStatus:200 transportSessionError:nil headers:@{}];
    
    
    // when
    ZMTransportRequest *req = [self.sut.requestGenerators nextRequest];
    XCTAssertNotNil(req);
    XCTAssertEqual(req.method, ZMMethodDELETE);
    XCTAssertTrue([req.path containsString:@"push/tokens"]);
    XCTAssertNil(req.payload);
    
    // and replacing the token while the request is in progress
    self.uiMOC.pushKitToken = [[ZMPushToken alloc] initWithDeviceToken:self.deviceToken identifier:self.identifier transportType:self.transportTypeVOIP fallback:FallbackAPNS isRegistered:YES];
    [req completeWithResponse:response];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertNotNil(self.uiMOC.pushKitToken);
}


@end
