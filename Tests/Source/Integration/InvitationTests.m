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

#import <XCTest/XCTest.h>
#import <ocmock/ocmock.h>
#import "zmessaging.h"

#import "ZMUserSession+Internal.h"
#import "IntegrationTestBase.h"


@interface MockSearchResultObserver : NSObject <ZMSearchResultObserver>
@property (nonatomic, strong) void (^completionBlock)(ZMSearchResult *, ZMSearchToken);
- (instancetype)initWithBlock:(void (^)(ZMSearchResult *, ZMSearchToken))completionBlock;
@end

@implementation MockSearchResultObserver

- (instancetype)initWithBlock:(void (^)(ZMSearchResult *result, ZMSearchToken token))completionBlock;
{
    if (!self) return nil;
    _completionBlock = completionBlock;
    return self;
}

- (void)didReceiveSearchResult:(ZMSearchResult *)result forToken:(ZMSearchToken)searchToken;
{
    self.completionBlock(result, searchToken);
}

@end


@interface InvitationTests : IntegrationTestBase
{
    id _mockAddressBook;
}
@property (nonatomic, strong) ZMSearchDirectory *searchDirectory;
@property (nonatomic, strong) NSArray *addressBookContacts;

@end

@implementation InvitationTests

- (void)setUp {
    [super setUp];
    [self updateDisplayNameGeneratorWithUsers:self.allUsers];
    self.searchDirectory = [[ZMSearchDirectory alloc] initWithUserSession:self.userSession];
}

- (void)tearDown {
    [_mockAddressBook stopMocking];
    _mockAddressBook = nil;
    [self.searchDirectory tearDown];
    self.searchDirectory = nil;
    self.addressBookContacts = nil;
    [super tearDown];
}

- (NSArray<ZMAddressBookContact *> *)addressBookWithContainingEmails:(BOOL)shouldSetEmails phoneNumbers:(BOOL)shouldSetPhones;
{
    NSArray *firstNames = @[@"Jean", @"Jaques", @"Jules", @"Jeane", @"Julie"];
    NSArray *lastNames = @[@"Dupont", @"Dupuit", @"Deschamps", @"Desbois", @"Dujardin"];
    NSArray *mails = @[@"Jean@example.com", @"Jaques@example.com", @"Jules@example.com", @"Jeane@example.com", @"Julie@example.com"];
    NSArray *phoneNumbers = @[@"191295921341", @"123012345349", @"028340980034", @"298403123498", @"109878946541"];

    NSMutableArray<ZMAddressBookContact *> *contacts = [NSMutableArray array];
    
    for (NSUInteger i = 0; i < [firstNames count]; ++i) {
            
        ZMAddressBookContact *contact = [[ZMAddressBookContact alloc] init];
        contact.firstName = firstNames[i];
        contact.lastName = lastNames[i];
        if (shouldSetPhones) {contact.phoneNumbers = @[phoneNumbers[i]]; }
        if (shouldSetEmails) {contact.emailAddresses = @[mails[i]]; }
        
        [contacts addObject:contact];
    }
    return [contacts copy];
}

- (ZMAddressBookContact *)addressBookContactWithUser:(MockUser *)mockUser;
{
    ZMAddressBookContact *contact = [[ZMAddressBookContact alloc] init];
    contact.firstName = mockUser.name;
    contact.emailAddresses = @[mockUser.email];
    contact.phoneNumbers = @[mockUser.phone];
    return contact;
}

- (void)setupAddressBook;
{
    self.addressBookContacts = [self addressBookWithContainingEmails:YES phoneNumbers:YES];
    [self setupAddressBookStubsWithAuthorizationAccess:YES contacts:self.addressBookContacts];
}

- (void)setupAddressBookStubsWithAuthorizationAccess:(BOOL)authorized contacts:(NSArray *)contacts;
{
    NOT_USED(authorized);
    NOT_USED(contacts);
    // TODO MARCO: re-enable?
//    _mockAddressBook = [OCMockObject mockForClass:[ZMAddressBook class]];
//    [[[[_mockAddressBook stub] classMethod] andReturnValue:@(authorized)] userHasAuthorizedAccess];
//    [[[_mockAddressBook stub] andReturn:contacts] contacts];
//    [[[[_mockAddressBook stub] classMethod] andReturn:_mockAddressBook] addressBook] ;
}
    
- (void)testThatFetchingUsersWithAddressBookWorksAtAll;
{
    //given
    XCTAssert([self logInAndWaitForSyncToBeComplete]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self setupAddressBookStubsWithAuthorizationAccess:YES contacts:[self addressBookWithContainingEmails:NO phoneNumbers:YES]];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"Observer called"];
    
    ZMSearchToken searchToken;
    MockSearchResultObserver *observer = [[MockSearchResultObserver alloc] initWithBlock:^(ZMSearchResult *result __unused, ZMSearchToken token __unused) {
        [expectation fulfill];
    }];
    
    ZMSearchRequest *request = [ZMSearchRequest new];
    request.query = @"";
    request.includeContacts = YES;
    
    [self.searchDirectory addSearchResultObserver:observer];
    
    //when
    searchToken = [self.searchDirectory performRequest:[request copy]];
    
    //then
    XCTAssertNotNil(searchToken);
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
    
    [self.searchDirectory removeSearchResultObserver:observer];
}

- (void)testThatWeAreFetchingUsersContactAndAddressBook;
{
    //given
    XCTAssert([self logInAndWaitForSyncToBeComplete]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    self.addressBookContacts =[self addressBookWithContainingEmails:NO phoneNumbers:YES];
    
    [self setupAddressBookStubsWithAuthorizationAccess:YES contacts:self.addressBookContacts];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"Observer called"];
    
    ZMSearchToken searchToken;
    MockSearchResultObserver *observer = [[MockSearchResultObserver alloc] initWithBlock:^(ZMSearchResult *result __unused, ZMSearchToken token __unused) {
        
        XCTAssertEqual(result.usersInContacts.count, self.connectedUsers.count + self.addressBookContacts.count);
        [expectation fulfill];
    }];
    
    ZMSearchRequest *request = [ZMSearchRequest new];
    request.query = @"";
    request.includeContacts = YES;
    request.includeAddressBookContacts = YES;
    [self.searchDirectory addSearchResultObserver:observer];
    
    //when
    searchToken = [self.searchDirectory performRequest:[request copy]];
    
    //then
    XCTAssertNotNil(searchToken);
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
    
    [self.searchDirectory removeSearchResultObserver:observer];
}

- (void)testThatFetchingAddressBookContainingRecordWithoutPermissionDoesntFetchAddressBookContact;
{
    //given
    XCTAssert([self logInAndWaitForSyncToBeComplete]);
    WaitForAllGroupsToBeEmpty(0.5);
    // TODO MARCO: re-enable?
//    _mockAddressBook = [OCMockObject mockForClass:[ZMAddressBook class]];
//    
//    [[[_mockAddressBook expect] classMethod] userHasAuthorizedAccess];
//    [[[[_mockAddressBook stub] classMethod] andReturnValue:@(NO)] userHasAuthorizedAccess];
//    [[[[_mockAddressBook stub] classMethod] andReturn:_mockAddressBook] addressBook] ;
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"Observer called"];
    
    ZMSearchToken searchToken;
    MockSearchResultObserver *observer = [[MockSearchResultObserver alloc] initWithBlock:^(ZMSearchResult *result __unused, ZMSearchToken token __unused) {
        
        XCTAssertEqual(self.addressBookContacts.count, 0lu);
        XCTAssertEqual(result.usersInContacts.count, self.connectedUsers.count);
        [expectation fulfill];
    }];
    
    ZMSearchRequest *request = [ZMSearchRequest new];
    request.query = @"";
    request.includeContacts = YES;
    request.includeAddressBookContacts = YES;
    
    [self.searchDirectory addSearchResultObserver:observer];
    
    //when
    searchToken = [self.searchDirectory performRequest:[request copy]];
    
    //then
    XCTAssertNotNil(searchToken);
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
    [_mockAddressBook verify];
    
    [self.searchDirectory removeSearchResultObserver:observer];
}

- (void)testThatFetchingContactDoesntDuplicateWireAndAddressBookContact;
{
    //given
    XCTAssert([self logInAndWaitForSyncToBeComplete]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    NSMutableArray *addressBookContacts = [[self addressBookWithContainingEmails:NO phoneNumbers:YES] mutableCopy];
    [addressBookContacts addObject:[self addressBookContactWithUser:self.user1]];
    self.addressBookContacts = [addressBookContacts copy];
    [self setupAddressBookStubsWithAuthorizationAccess:YES contacts:self.addressBookContacts];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"Observer called"];
    ZMSearchToken searchToken;
    MockSearchResultObserver *observer = [[MockSearchResultObserver alloc] initWithBlock:^(ZMSearchResult *result __unused, ZMSearchToken token __unused) {
        
        XCTAssertEqual(result.usersInContacts.count, self.connectedUsers.count + self.addressBookContacts.count - 1lu);
        [expectation fulfill];
    }];
    
    ZMSearchRequest *request = [ZMSearchRequest new];
    request.query = @"";
    request.includeContacts = YES;
    request.includeAddressBookContacts = YES;
    
    [self.searchDirectory addSearchResultObserver:observer];
    
    //when
    searchToken = [self.searchDirectory performRequest:[request copy]];
    
    //then
    XCTAssertNotNil(searchToken);
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
    
    [self.searchDirectory removeSearchResultObserver:observer];
}

@end
