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

@import ZMCDataModel;

#import "ObjectTranscoderTests.h"
#import "ZMAddressBookSync+Testing.h"
#import "ZMAddressBookEncoder.h"
#import "ZMSingleRequestSync.h"
#import "ZMAddressBook.h"

@interface ZMAddressBookSyncTests : ObjectTranscoderTests
{
    ZMSingleRequestProgress _addressBookUploadStatus;
}

@property (nonatomic) ZMAddressBookSync<ZMSingleRequestTranscoder> *sut;
@property (nonatomic) id addressBookUpload;
@property (nonatomic) id addressBookMock;
@property (nonatomic) NSArray *contacts;

@end



@interface ZMAddressBookSync (NSManagedObjectContext_Testing)

- (void)clearAddressBookAsNeedingToBeUploaded;

@end



@implementation ZMAddressBookSyncTests

- (ZMSingleRequestProgress)addressBookUploadStatus;
{
    return _addressBookUploadStatus;
}

- (void)setUp
{
    [super setUp];
    
    self.addressBookUpload = [OCMockObject mockForClass:ZMSingleRequestSync.class];
    (void)[(ZMSingleRequestSync *)[[self.addressBookUpload stub] andCall:@selector(addressBookUploadStatus) onObject:self] status];
    _addressBookUploadStatus = ZMSingleRequestIdle;
    [self verifyMockLater:self.addressBookUpload];
    
    self.addressBookMock = [OCMockObject mockForClass:ZMAddressBook.class];
    
    [self stubAddressBookWithContacts];
    
    ZMUser *selfUser = [ZMUser selfUserInContext:self.uiMOC];
    selfUser.emailAddress = @"doe@example.com";
    
    self.sut = (id) [[ZMAddressBookSync alloc] initWithManagedObjectContext:self.uiMOC addressBook:self.addressBookMock addressBookUpload:self.addressBookUpload];
}

- (void)tearDown
{
    [self.sut tearDown];
    self.sut = nil;
    self.addressBookUpload = nil;
    
    WaitForAllGroupsToBeEmpty(0.5);
    [self.addressBookMock stopMocking];
    self.addressBookMock = nil;
    
    [super tearDown];
}

- (void)stubAddressBookWithContacts;
{
    ZMAddressBookContact *contactA = [[ZMAddressBookContact alloc] init];
    contactA.emailAddresses = @[@"max.musterman@example.com"];
    
    ZMAddressBookContact *contactB = [[ZMAddressBookContact alloc] init];
    contactB.emailAddresses = @[@"john@example.com", @"john.appleseed@example.com"];
    contactB.phoneNumbers = @[@"+123456789012", @"+4915324568954"];
    
    ZMAddressBookContact *contactC = [[ZMAddressBookContact alloc] init];
    contactC.emailAddresses = @[];
    contactC.phoneNumbers = @[];
    
    self.contacts = @[contactA, contactB, contactC];
    [(ZMAddressBook *)[[self.addressBookMock stub] andReturn:self.contacts] contacts];
    [[self.addressBookMock expect] numberOfContacts];
}

- (void)testThatItReturnsNilRequestWhenAddressBookDoesNotNeedToBeUploaded;
{
    // given
    [self.sut clearAddressBookAsNeedingToBeUploaded];
    NSError *error;
    XCTAssert([self.uiMOC save:&error], @"%@", error);
    
    // when
    ZMTransportRequest *r = self.sut.nextRequest;
    
    // then
    XCTAssertNil(r);
}

- (void)testThatItReturnsAnAddressBookUploadRequest
{
    // given
    [self.sut tearDown];
    self.sut = (id) [[ZMAddressBookSync alloc] initWithManagedObjectContext:self.uiMOC addressBook:self.addressBookMock addressBookUpload:nil];
    [ZMAddressBookSync markAddressBookAsNeedingToBeUploadedInContext:self.uiMOC];
    NSError *error;
    XCTAssert([self.uiMOC save:&error], @"%@", error);
    XCTAssertTrue(self.sut.addressBookNeedsToBeUploaded);

    // expect
    [self expectationForNotification:@"ZMOperationLoopNewRequestAvailable" object:nil handler:nil];
    
    // when
    ZMTransportRequest *request = [self.sut nextRequest];
    XCTAssertNil(request);
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
    request = [self.sut nextRequest];
    
    // then
    XCTAssertNotNil(request);
    XCTAssertEqual(request.method, ZMMethodPOST);
    XCTAssertTrue(request.shouldCompress);
    XCTAssertEqualObjects(request.path, @"/onboarding/v2");
    XCTAssertNotNil(request.payload);
    XCTAssertTrue([request.payload isKindOfClass:[NSDictionary class]]);
    NSDictionary *payload = [request.payload asDictionary];
    for (NSString *digest in [payload arrayForKey:@"self"]) {
        XCTAssertTrue([digest isKindOfClass:[NSString class]]);
        NSData *digestData = [[NSData alloc] initWithBase64EncodedString:digest options:0];
        XCTAssertNotNil(digestData);
    }
    for (NSDictionary *card in [payload arrayForKey:@"cards"]) {
        for (NSString *digest in [card arrayForKey:@"contact"]) {
            XCTAssertTrue([digest isKindOfClass:[NSString class]]);
            NSData *digestData = [[NSData alloc] initWithBase64EncodedString:digest options:0];
            XCTAssertNotNil(digestData);
        }
    }
}

- (void)testThatItClearsTheNeedsUploadStateWhenUploadIsCompleted;
{
    // given
    [ZMAddressBookSync markAddressBookAsNeedingToBeUploadedInContext:self.uiMOC];
    NSError *error;
    XCTAssert([self.uiMOC save:&error], @"%@", error);
    
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:@{@"results": @[]} HTTPstatus:200 transportSessionError:nil];
    
    // when
    [self.sut didReceiveResponse:response forSingleRequest:nil];
    
    // then
    XCTAssertFalse([ZMAddressBookSync addressBookNeedsToBeUploadedInContext:self.uiMOC]);
}

- (void)testThatItClearsTheNeedsUploadStateOnAPermanentError
{
    // given
    [ZMAddressBookSync markAddressBookAsNeedingToBeUploadedInContext:self.uiMOC];
    NSArray *identifiers = @[NSUUID.createUUID, NSUUID.createUUID];
    self.uiMOC.suggestedUsersForUser = [NSOrderedSet orderedSetWithArray:identifiers];
    
    NSError *error;
    XCTAssert([self.uiMOC save:&error], @"%@", error);
    
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:@{@"foo": @[]} HTTPstatus:400 transportSessionError:nil];
    
    // when
    [self.sut didReceiveResponse:response forSingleRequest:nil];
    
    // then
    XCTAssertFalse([ZMAddressBookSync addressBookNeedsToBeUploadedInContext:self.uiMOC]);
    XCTAssertEqualObjects([NSSet setWithArray:self.uiMOC.suggestedUsersForUser.array], [NSSet setWithArray:identifiers], @"Should remain unchanged.");
}

- (void)testThatItDoesNotUploadTheSameAddressBookTwice;
{
    // given
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:@{@"results": @[]} HTTPstatus:200 transportSessionError:nil];
    
    // expect
    [[self.addressBookUpload expect] readyForNextRequest];
    [[self.addressBookUpload reject] readyForNextRequest];
    [[self.addressBookUpload stub] nextRequest];
    
    // when
    // (1)
    [ZMAddressBookSync markAddressBookAsNeedingToBeUploadedInContext:self.uiMOC];
    XCTAssert([self.uiMOC saveOrRollback]);
    _addressBookUploadStatus = ZMSingleRequestIdle;
    
    (void) self.sut.nextRequest;
    WaitForAllGroupsToBeEmpty(0.5);
    [self.sut didReceiveResponse:response forSingleRequest:nil];
    _addressBookUploadStatus = ZMSingleRequestCompleted;
    
    // (2)
    [[self.addressBookMock expect] numberOfContacts];
    [ZMAddressBookSync markAddressBookAsNeedingToBeUploadedInContext:self.uiMOC];
    XCTAssert([self.uiMOC saveOrRollback]);
    
    (void) self.sut.nextRequest;
    WaitForAllGroupsToBeEmpty(0.5);
}

@end



@implementation ZMAddressBookSyncTests (SuggestedContacts)

- (void)testThatItUpdatesTheSuggestedContacts;
{
    // given
    [ZMAddressBookSync markAddressBookAsNeedingToBeUploadedInContext:self.uiMOC];
    NSError *error;
    XCTAssert([self.uiMOC save:&error], @"%@", error);
    NSArray *remoteIdentifiers = @[NSUUID.createUUID, NSUUID.createUUID, NSUUID.createUUID];
    ZM_ALLOW_MISSING_SELECTOR(NSDictionary *responsePayload = @{@"results": [remoteIdentifiers mapWithSelector:@selector(transportString)]});
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:responsePayload HTTPstatus:200 transportSessionError:nil];
    
    // expect
    [self expectationForNotification:ZMSuggestedUsersForUserDidChange object:nil handler:nil];
    
    // when
    [self.sut didReceiveResponse:response forSingleRequest:nil];
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
    
    // then
    XCTAssertEqualObjects(self.uiMOC.suggestedUsersForUser.array, remoteIdentifiers);
}

@end
