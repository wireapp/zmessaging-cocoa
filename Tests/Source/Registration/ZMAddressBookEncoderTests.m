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

#import "MessagingTest.h"
#import "ZMAddressBook.h"
#import "ZMAddressBookEncoder.h"



@interface ZMAddressBookEncoderTests : MessagingTest

@property (nonatomic) ZMAddressBookEncoder *sut;
@property (nonatomic) id addressBookMock;
@property (nonatomic) NSArray *contacts;
@end



@implementation ZMAddressBookEncoderTests

- (void)setUp
{
    [super setUp];
    self.addressBookMock = [OCMockObject mockForClass:ZMAddressBook.class];
    self.sut = [[ZMAddressBookEncoder alloc] initWithManagedObjectContext:self.uiMOC addressBook:self.addressBookMock];
}

- (void)tearDown
{
    self.addressBookMock = nil;
    self.sut = nil;
    [super tearDown];
}

- (void)testThatItReturnsTheSelfUsersHashesWhenTheAddressBookIsEmpty;
{
    // given
    [self stubEmptyAddressBook];
    ZMUser *selfUser = [ZMUser selfUserInContext:self.uiMOC];
    selfUser.emailAddress = @"doe@example.com";
    
    // then
    XCTestExpectation *e = [self expectationWithDescription:@"Got payload"];
    [self.sut createPayloadWithCompletionHandler:^(ZMEncodedAddressBook *encoded) {
        XCTAssertNotNil(encoded.localData);
        XCTAssertEqualObjects(encoded.localData, @[@"xot6QwrI3ulnbsd6OHGU4j8jTQJOA9hEBQz2wBd1yPY="]);
        XCTAssertNil(encoded.otherData);
        XCTAssertEqual(encoded.digest.length, 64u, @"Valid SHA-512 length");
        NSData *expectedDigest = [NSData dataWithBytes:(const uint8_t[]){
            0xcf,0x83,0xe1,0x35,0x7e,0xef,0xb8,0xbd,0xf1,0x54,0x28,0x50,0xd6,0x6d,0x80,0x07,0xd6,0x20,0xe4,0x05,
            0x0b,0x57,0x15,0xdc,0x83,0xf4,0xa9,0x21,0xd3,0x6c,0xe9,0xce,0x47,0xd0,0xd1,0x3c,0x5d,0x85,0xf2,0xb0,
            0xff,0x83,0x18,0xd2,0x87,0x7e,0xec,0x2f,0x63,0xb9,0x31,0xbd,0x47,0x41,0x7a,0x81,0xa5,0x38,0x32,0x7a,
            0xf9,0x27,0xda,0x3e
        } length:64];
        AssertEqualData(encoded.digest, expectedDigest);
        [e fulfill];
    }];
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
}

- (void)testThatItReturnsTheSelfUsersPhoneHashWhenTheAddressBookIsEmpty;
{
    // given
    [self stubEmptyAddressBook];
    ZMUser *selfUser = [ZMUser selfUserInContext:self.uiMOC];
    selfUser.phoneNumber = @"+01234567894";
    
    // then
    XCTestExpectation *e = [self expectationWithDescription:@"Got payload"];
    [self.sut createPayloadWithCompletionHandler:^(ZMEncodedAddressBook *encoded) {
        XCTAssertNotNil(encoded.localData);
        XCTAssertEqualObjects(encoded.localData, @[@"eenMMwYY5V/7u2sQNo5JLkhXKBHfmkEZ7XcOZEakTjk="]);
        XCTAssertNil(encoded.otherData);
        XCTAssertEqual(encoded.digest.length, 64u, @"Valid SHA-512 length");
        NSData *expectedDigest = [NSData dataWithBytes:(const uint8_t[]){
            0xcf,0x83,0xe1,0x35,0x7e,0xef,0xb8,0xbd,0xf1,0x54,0x28,0x50,0xd6,0x6d,0x80,0x07,0xd6,0x20,0xe4,0x05,
            0x0b,0x57,0x15,0xdc,0x83,0xf4,0xa9,0x21,0xd3,0x6c,0xe9,0xce,0x47,0xd0,0xd1,0x3c,0x5d,0x85,0xf2,0xb0,
            0xff,0x83,0x18,0xd2,0x87,0x7e,0xec,0x2f,0x63,0xb9,0x31,0xbd,0x47,0x41,0x7a,0x81,0xa5,0x38,0x32,0x7a,
            0xf9,0x27,0xda,0x3e
        } length:64];
        AssertEqualData(encoded.digest, expectedDigest);
        [e fulfill];
    }];
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
}

- (void)testThatTheSelfUsersPhoneHashIsEqualToThePhoneHashOfAContactForTheSamePhoneNumber;
{
    // given
    ZMUser *selfUser = [ZMUser selfUserInContext:self.uiMOC];
    selfUser.phoneNumber = @"+01234567894";
    [self stubAddressBookWithSinlgeContactEmails:@[] phoneNumbers:@[selfUser.phoneNumber]];
    
    
    // then
    XCTestExpectation *e = [self expectationWithDescription:@"Got payload"];
    [self.sut createPayloadWithCompletionHandler:^(ZMEncodedAddressBook *encoded) {
        XCTAssertNotNil(encoded.localData);
        XCTAssertEqualObjects(encoded.localData, @[@"eenMMwYY5V/7u2sQNo5JLkhXKBHfmkEZ7XcOZEakTjk="]);
        NSArray *expected = @[
                              @{@"card_id" : @"0",
                                @"contact" : @[
                                        @"eenMMwYY5V/7u2sQNo5JLkhXKBHfmkEZ7XcOZEakTjk="
                                        ],
                                },
                              ];
        AssertArraysContainsSameObjects((NSArray *) encoded.otherData, expected);
        [e fulfill];
    }];
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
}


- (void)testThatItReturnsTheSelfUsersHashesWhenTheAddressBookIsNil;
{
    // given
    self.sut = [[ZMAddressBookEncoder alloc] initWithManagedObjectContext:self.uiMOC addressBook:nil];
    ZMUser *selfUser = [ZMUser selfUserInContext:self.uiMOC];
    selfUser.emailAddress = @"doe@example.com";
    
    // then
    XCTestExpectation *e = [self expectationWithDescription:@"Got payload"];
    [self.sut createPayloadWithCompletionHandler:^(ZMEncodedAddressBook *encoded) {
        XCTAssertNotNil(encoded.localData);
        XCTAssertEqualObjects(encoded.localData, @[@"xot6QwrI3ulnbsd6OHGU4j8jTQJOA9hEBQz2wBd1yPY="]);
        XCTAssertNil(encoded.otherData);
        XCTAssertEqual(encoded.digest.length, 64u, @"Valid SHA-512 length");
        NSData *expectedDigest = [NSData dataWithBytes:(const uint8_t[]){
            0xcf,0x83,0xe1,0x35,0x7e,0xef,0xb8,0xbd,0xf1,0x54,0x28,0x50,0xd6,0x6d,0x80,0x07,0xd6,0x20,0xe4,0x05,
            0x0b,0x57,0x15,0xdc,0x83,0xf4,0xa9,0x21,0xd3,0x6c,0xe9,0xce,0x47,0xd0,0xd1,0x3c,0x5d,0x85,0xf2,0xb0,
            0xff,0x83,0x18,0xd2,0x87,0x7e,0xec,0x2f,0x63,0xb9,0x31,0xbd,0x47,0x41,0x7a,0x81,0xa5,0x38,0x32,0x7a,
            0xf9,0x27,0xda,0x3e

        } length:64];
        AssertEqualData(encoded.digest, expectedDigest);
        [e fulfill];
    }];
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
}

- (void)testThatItReturnsTheSelfUsersHashesWhenTheAddressBookOnlyContainsEmptyContacts;
{
    // given
    [self stubAddressBookWithEmptyContact];
    ZMUser *selfUser = [ZMUser selfUserInContext:self.uiMOC];
    selfUser.emailAddress = @"doe@example.com";
    
    // then
    XCTestExpectation *e = [self expectationWithDescription:@"Got payload"];
    [self.sut createPayloadWithCompletionHandler:^(ZMEncodedAddressBook *encoded) {
        XCTAssertNotNil(encoded.localData);
        XCTAssertEqualObjects(encoded.localData, @[@"xot6QwrI3ulnbsd6OHGU4j8jTQJOA9hEBQz2wBd1yPY="]);
        XCTAssertNil(encoded.otherData);
        XCTAssertEqual(encoded.digest.length, 64u, @"Valid SHA-512 length");
        NSData *expectedDigest = [NSData dataWithBytes:(const uint8_t[]){
            0xcf,0x83,0xe1,0x35,0x7e,0xef,0xb8,0xbd,0xf1,0x54,0x28,0x50,0xd6,0x6d,0x80,0x07,0xd6,0x20,0xe4,0x05,
            0x0b,0x57,0x15,0xdc,0x83,0xf4,0xa9,0x21,0xd3,0x6c,0xe9,0xce,0x47,0xd0,0xd1,0x3c,0x5d,0x85,0xf2,0xb0,
            0xff,0x83,0x18,0xd2,0x87,0x7e,0xec,0x2f,0x63,0xb9,0x31,0xbd,0x47,0x41,0x7a,0x81,0xa5,0x38,0x32,0x7a,
            0xf9,0x27,0xda,0x3e

        } length:64];
        AssertEqualData(encoded.digest, expectedDigest);
        [e fulfill];
    }];
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
}


- (void)testThatItEncodesTheAddressBook;
{
    // given
    [self stubAddressBookWithContacts];
    ZMUser *selfUser = [ZMUser selfUserInContext:self.uiMOC];
    selfUser.emailAddress = @"doe@example.com";
    
    // then
    XCTestExpectation *e = [self expectationWithDescription:@"Got payload"];
    [self.sut createPayloadWithCompletionHandler:^(ZMEncodedAddressBook *encoded) {
        XCTAssertNotNil(encoded.localData);
        XCTAssertEqualObjects(encoded.localData, @[@"xot6QwrI3ulnbsd6OHGU4j8jTQJOA9hEBQz2wBd1yPY="]);
        NSArray *expected = @[
                              @{
                                  @"card_id" : @"0",
                                  @"contact" : @[
                                          @"z5x1qzsgFZvG8iqvOklPoG8Mzr9SqPnLa1UJ2V1rr6I="
                                          ],
                                  },
                              @{
                                  @"card_id" : @"1",
                                  @"contact" : @[
                                          @"hV+W6YPx+Oi+lEaStvcZ/VQymCbLYumAFe/uji4HHdQ=",
                                          @"9lXmq9KuYNODDOAPmizuAUWDRKDBqcLrIBzHmbQrGBw=",
                                          @"0jTPlMu+7kPPA/ilpG/ikUFK8Hs2xMFVRLHs53JQsgI=",
                                          @"IHI4pX3lC+tkaaLOxbYpubZLA6127QE1R6oJDt5BQu0="
                                          ]
                              }
                            ];
        XCTAssertNotNil(encoded.otherData);
        AssertArraysContainsSameObjects((NSArray *) encoded.otherData, expected);
        XCTAssertEqual(encoded.digest.length, 64u, @"Valid SHA-512 length");
        NSData *expectedDigest = [NSData dataWithBytes:(const uint8_t[]){
            0x6b,0x41,0xe4,0xba,0xbd,0x8f,0x26,0x3d,0x65,0x60,0x31,0xbf,0x09,0x6d,0x67,0xff,0x02,0x5b,0x36,0x4f,
            0x46,0x1f,0x94,0x3d,0x0a,0x57,0xb1,0x19,0xa9,0x04,0xc7,0x3b,0xb1,0x2b,0xd1,0x2b,0x57,0x72,0x8b,0x67,
            0x4e,0x48,0xfa,0x11,0xf6,0x47,0x05,0x5d,0x7e,0x04,0xa9,0x2b,0x70,0xb7,0x86,0xb8,0x1b,0x29,0x7a,0xe7,
            0x79,0xae,0xf7,0x5f

        } length:64];
        AssertEqualData(encoded.digest, expectedDigest);
        [e fulfill];
    }];
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
}

- (void)testThatItEncodesTheAddressBookWithoutEmailNorPhone;
{
    // given
    [self stubAddressBookWithContacts];
    
    // then
    XCTestExpectation *e = [self expectationWithDescription:@"Got payload"];
    [self.sut createPayloadWithCompletionHandler:^(ZMEncodedAddressBook *encoded) {
        XCTAssertNotNil(encoded.localData);
        XCTAssertEqualObjects(encoded.localData, @[]);
        NSArray *expected = @[
                              @{
                                  @"card_id" : @"0",
                                  @"contact" : @[
                                          @"z5x1qzsgFZvG8iqvOklPoG8Mzr9SqPnLa1UJ2V1rr6I="
                                          ],
                                  },
                              @{
                                  @"card_id" : @"1",
                                  @"contact" : @[
                                          @"hV+W6YPx+Oi+lEaStvcZ/VQymCbLYumAFe/uji4HHdQ=",
                                          @"9lXmq9KuYNODDOAPmizuAUWDRKDBqcLrIBzHmbQrGBw=",
                                          @"0jTPlMu+7kPPA/ilpG/ikUFK8Hs2xMFVRLHs53JQsgI=",
                                          @"IHI4pX3lC+tkaaLOxbYpubZLA6127QE1R6oJDt5BQu0="
                                          ]
                                  }
                              ];
        XCTAssertNotNil(encoded.otherData);
        AssertArraysContainsSameObjects((NSArray *) encoded.otherData, expected);
        XCTAssertEqual(encoded.digest.length, 64u, @"Valid SHA-512 length");
        NSData *expectedDigest = [NSData dataWithBytes:(const uint8_t[]){
            0x6b,0x41,0xe4,0xba,0xbd,0x8f,0x26,0x3d,0x65,0x60,0x31,0xbf,0x09,0x6d,0x67,0xff,0x02,0x5b,0x36,0x4f,
            0x46,0x1f,0x94,0x3d,0x0a,0x57,0xb1,0x19,0xa9,0x04,0xc7,0x3b,0xb1,0x2b,0xd1,0x2b,0x57,0x72,0x8b,0x67,
            0x4e,0x48,0xfa,0x11,0xf6,0x47,0x05,0x5d,0x7e,0x04,0xa9,0x2b,0x70,0xb7,0x86,0xb8,0x1b,0x29,0x7a,0xe7,
            0x79,0xae,0xf7,0x5f
        } length:64];
        AssertEqualData(encoded.digest, expectedDigest);
        [e fulfill];
    }];
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
}

- (void)testThatItDoesNotEncodeEmailsOrPhoneNumbersTwice;
{
    // given
    [self stubAddressBookWithSinlgeContactEmails:@[@"anakin@example.com", @"anakin@example.com"] phoneNumbers:@[@"+14152365478", @"+14152365478"]];
    ZMUser *selfUser = [ZMUser selfUserInContext:self.uiMOC];
    selfUser.emailAddress = @"doe@example.com";
    
    // then
    XCTestExpectation *e = [self expectationWithDescription:@"Got payload"];
    [self.sut createPayloadWithCompletionHandler:^(ZMEncodedAddressBook *encoded) {
        XCTAssertNotNil(encoded.localData);
        XCTAssertEqualObjects(encoded.localData, @[@"xot6QwrI3ulnbsd6OHGU4j8jTQJOA9hEBQz2wBd1yPY="]);
        NSArray *expected = @[
                              @{
                                  @"card_id" : @"0",
                                  @"contact" : @[
                                          @"9eDQtCRDDaFHFSJSm3NzCvu9APoZIsybvTuI0hUse3U=",
                                          @"eUgOBPHbuaxv8j35f2xMetj6xDGkjTnYN24EYa+pVek=",
                                          ]
                                  }
                              ];
        XCTAssertNotNil(encoded.otherData);
        AssertArraysContainsSameObjects((NSArray *) encoded.otherData, expected);
        [e fulfill];
    }];
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
}

- (void)testThatItDoesNotEncodeInvalidEmails;
{
    // given
    [self stubAddressBookWithSinlgeContactEmails:@[@"anakin@example.com", @"anakin", @" anakin@example.com", @" anakin@", @" anakin@example", @" @example.com"] phoneNumbers:@[@"+14152365478"]];
    ZMUser *selfUser = [ZMUser selfUserInContext:self.uiMOC];
    selfUser.emailAddress = @"doe@example.com";
    
    // then
    XCTestExpectation *e = [self expectationWithDescription:@"Got payload"];
    [self.sut createPayloadWithCompletionHandler:^(ZMEncodedAddressBook *encoded) {
        XCTAssertNotNil(encoded.localData);
        XCTAssertEqualObjects(encoded.localData, @[@"xot6QwrI3ulnbsd6OHGU4j8jTQJOA9hEBQz2wBd1yPY="]);
        NSArray *expected = @[
                              @{
                                  @"card_id" : @"0",
                                  @"contact" : @[
                                          @"9eDQtCRDDaFHFSJSm3NzCvu9APoZIsybvTuI0hUse3U=",
                                          @"eUgOBPHbuaxv8j35f2xMetj6xDGkjTnYN24EYa+pVek=",
                                          ]
                                  }
                              ];
        XCTAssertNotNil(encoded.otherData);
        AssertArraysContainsSameObjects((NSArray *) encoded.otherData, expected);
        [e fulfill];
    }];
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
}

- (void)testThatItDoesNotEncodeInvalidPhoneNumbers;
{
    // given
    [self stubAddressBookWithSinlgeContactEmails:@[@"anakin@example.com"] phoneNumbers:@[@"+14152365478", @"+112345", @"14152365478", @"22"]];
    ZMUser *selfUser = [ZMUser selfUserInContext:self.uiMOC];
    selfUser.emailAddress = @"doe@example.com";
    
    // then
    XCTestExpectation *e = [self expectationWithDescription:@"Got payload"];
    [self.sut createPayloadWithCompletionHandler:^(ZMEncodedAddressBook *encoded) {
        XCTAssertNotNil(encoded.localData);
        XCTAssertEqualObjects(encoded.localData, @[@"xot6QwrI3ulnbsd6OHGU4j8jTQJOA9hEBQz2wBd1yPY="]);
        NSArray *expected = @[
                              @{
                                  @"card_id" : @"0",
                                  @"contact" : @[
                                          @"9eDQtCRDDaFHFSJSm3NzCvu9APoZIsybvTuI0hUse3U=",
                                          @"eUgOBPHbuaxv8j35f2xMetj6xDGkjTnYN24EYa+pVek=",
                                          ]
                                  }
                              ];
        XCTAssertNotNil(encoded.otherData);
        AssertArraysContainsSameObjects((NSArray *) encoded.otherData, expected);
        [e fulfill];
    }];
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
}

- (void)testThatEmailInPayloadIsNormalized;
{
    //given
    [self stubAddressBookWithSinlgeContactEmails:@[@"\"My Son <anakin@example.com>"] phoneNumbers:@[]];
    ZMUser *selfUser = [ZMUser selfUserInContext:self.uiMOC];
    selfUser.emailAddress = @"doe@example.com";

    //then
    XCTestExpectation *e = [self expectationWithDescription:@"Got payload"];
    [self.sut createPayloadWithCompletionHandler:^(ZMEncodedAddressBook *encoded) {
        
        //update expected data
        NSArray *expected = @[
                              @{
                                  @"card_id" : @"0",
                                  @"contact" : @[
                                          @"9eDQtCRDDaFHFSJSm3NzCvu9APoZIsybvTuI0hUse3U="
                                          ]
                                  }
                              ];
        XCTAssertNotNil(encoded.otherData);
        AssertArraysContainsSameObjects((NSArray *) encoded.otherData, expected);
        [e fulfill];
    }];
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
}

- (void)stubAddressBookWithSinlgeContactEmails:(NSArray *)emails phoneNumbers:(NSArray *)phoneNumbers;
{
    ZMAddressBookContact *contactA = [[ZMAddressBookContact alloc] init];
    contactA.emailAddresses = emails;
    contactA.phoneNumbers = phoneNumbers;
    
    self.contacts = @[contactA];
    [(ZMAddressBook *)[[self.addressBookMock stub] andReturn:self.contacts] contacts];
    [[self.addressBookMock expect] numberOfContacts];
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

- (void)stubAddressBookWithEmptyContact
{
    ZMAddressBookContact *contactC = [[ZMAddressBookContact alloc] init];
    contactC.emailAddresses = @[];
    contactC.phoneNumbers = @[];
    
    self.contacts = @[contactC];
    [(ZMAddressBook *)[[self.addressBookMock stub] andReturn:self.contacts] contacts];
    [[self.addressBookMock expect] numberOfContacts];
}

- (void)stubEmptyAddressBook;
{
    self.contacts = @[];
    [(ZMAddressBook *)[[self.addressBookMock stub] andReturn:self.contacts] contacts];
    [[self.addressBookMock expect] numberOfContacts];
}

@end
