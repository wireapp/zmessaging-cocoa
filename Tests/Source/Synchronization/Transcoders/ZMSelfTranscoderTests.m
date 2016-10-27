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


@import zimages;
@import ZMTransport;
@import zmessaging;
@import ZMCDataModel;

#import "ObjectTranscoderTests.h"
#import "ZMSelfTranscoder+Internal.h"
#import "ZMUserSession+Internal.h"

@interface ZMSelfTranscoderTests : ObjectTranscoderTests

@property (nonatomic) ZMSelfTranscoder<ZMSingleRequestTranscoder> *sut;
@property (nonatomic) ZMUpstreamModifiedObjectSync *upstreamObjectSync;
@property (nonatomic) NSString *trackingIdentifier;
@property (nonatomic) id mockClientRegistrationStatus;
@property (nonatomic) ZMClientRegistrationStatus *realClientRegistrationStatus;
@property (nonatomic) NSTimeInterval originalRequestInterval;
@end



@implementation ZMSelfTranscoderTests

- (void)setUp
{
    [super setUp];
    self.originalRequestInterval = ZMSelfTranscoderPendingValidationRequestInterval;
    
    self.mockClientRegistrationStatus = [OCMockObject niceMockForClass:[ZMClientRegistrationStatus class]];
    self.upstreamObjectSync = [OCMockObject niceMockForClass:ZMUpstreamModifiedObjectSync.class];
    [self.syncMOC performBlockAndWait:^{
        [ZMUser selfUserInContext:self.syncMOC].needsToBeUpdatedFromBackend = NO;
        [self.syncMOC saveOrRollback];
    }];
    self.sut = (id) [[ZMSelfTranscoder alloc] initWithClientRegistrationStatus:self.mockClientRegistrationStatus
                                                          managedObjectContext:self.syncMOC
                                                            upstreamObjectSync:self.upstreamObjectSync];
    
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)tearDown
{
    ZMSelfTranscoderPendingValidationRequestInterval = self.originalRequestInterval;
    
    [self.realClientRegistrationStatus tearDown];
    self.realClientRegistrationStatus = nil;
    [self.sut tearDown];
    self.upstreamObjectSync = nil;
    self.sut = nil;
    [super tearDown];
}

- (NSMutableDictionary *)samplePayloadForUserID:(NSUUID *)userID
{
    self.trackingIdentifier = NSUUID.createUUID.transportString;
    return [@{
              @"name" : @"Papineau",
              @"id" : userID.transportString,
              @"email" : @"pp@example.com",
              @"phone" : @"555-986-45789",
              @"accent_id" : @3,
              @"picture" : @[],
              @"tracking_id": self.trackingIdentifier,
              } mutableCopy];
}

- (void)testThatItRequestSelfUserIfNeedsSlowSync
{
    // given
    [self.sut setNeedsSlowSync];
    
    // when
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    
    // then
    XCTAssertNotNil(request);
    XCTAssertEqualObjects(@"/self", request.path);
    XCTAssertEqual(ZMMethodGET, request.method);
}

- (void)testThatItDoesNotRequestSelfUserIfSlowSyncIsDone
{
    // given
    [self.sut setNeedsSlowSync];
    NSDictionary *payload = [self samplePayloadForUserID:[NSUUID createUUID]];
    
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPStatus:200 transportSessionError:nil];

    
    // simulate hard sync done
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    [request completeWithResponse:response];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    request = [self.sut.requestGenerators nextRequest];
    
    // then
    XCTAssertNil(request);
}

- (void)testThatItUpdatesSelfUser
{
    // given
    NSDictionary *payload = [self samplePayloadForUserID:[NSUUID createUUID]];
    
    __block ZMUser *selfUser;
    [self.syncMOC performGroupedBlockAndWait:^{
        [self.sut setNeedsSlowSync];

        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPStatus:200 transportSessionError:nil];
        ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
        selfUser = [ZMUser selfUserInContext:self.syncMOC];
        
        // when
        [request completeWithResponse:response];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    [self.syncMOC performGroupedBlockAndWait:^{
        // then
        XCTAssertEqualObjects(payload[@"id"], [selfUser.remoteIdentifier transportString]);
        XCTAssertEqualObjects(payload[@"name"], selfUser.name);
        XCTAssertEqualObjects(payload[@"email"], selfUser.emailAddress);
    }];
}


- (void)testThatItDoesNotRequestSelfUserWhileARequestIsAlreadyInProgress
{
    // given
    //
    // The self user is inserted automatically by -[NSManagedObjectContext syncContext]
    //
    
    ZMTransportRequest *req = [self.sut.requestGenerators nextRequest];
    NOT_USED(req);
    
    // when
    ZMTransportRequest *nextReq = [self.sut.requestGenerators nextRequest];
    
    // then
    XCTAssertNil(nextReq);
}

- (void)testThatItRequestsTheSelfUserAgain
{
    // given
    [self.sut setNeedsSlowSync];
    NSDictionary *payload = [self samplePayloadForUserID:[NSUUID createUUID]];
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPStatus:200 transportSessionError:nil];
    
    
    // simulate hard sync done
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    [request completeWithResponse:response];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    [self.sut setNeedsSlowSync];
    request = [self.sut.requestGenerators nextRequest];
    
    // then
    XCTAssertNotNil(request);
    XCTAssertEqualObjects(request.path, @"/self");
    XCTAssertEqual(request.method, ZMMethodGET);
    XCTAssertNil(request.payload);
}



- (void)testThatItIndicatesThatTheSelfUserIsIncomplete
{
    // given
    // we have an incomplete self user

    // when
    BOOL hasSelfUser = [self.sut isSelfUserComplete];

    // then
    XCTAssertFalse(hasSelfUser);
}

- (void)testThatItIndicatesThatTheSelfUserIsComplete
{
    // given
    [self.syncMOC performGroupedBlockAndWait:^{
        [self.sut setNeedsSlowSync];
        NSDictionary *payload = [self samplePayloadForUserID:[NSUUID createUUID]];
        
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPStatus:200 transportSessionError:nil];
        ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
        ZMUser *selfUser = [ZMUser selfUserInContext:self.syncMOC];
        NOT_USED(selfUser);

        // when
        [request completeWithResponse:response];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    [self.syncMOC performGroupedBlockAndWait:^{
        // then
        XCTAssertTrue([self.sut isSelfUserComplete]);
    }];
}


- (void)testThatItRequestsTheSelfUserAfterSetNeedSlowSync
{
    // given
    [self.sut setNeedsSlowSync];
    XCTAssertFalse(self.sut.isSlowSyncDone);
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    NSDictionary *payload = [self samplePayloadForUserID:[NSUUID createUUID]];
    
    // complete request and hard sync
    [request completeWithResponse:[ZMTransportResponse responseWithPayload:payload HTTPStatus:200 transportSessionError:nil]];
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertTrue(self.sut.isSlowSyncDone);
    
    // when
    [self.sut setNeedsSlowSync];
    
    // then
    ZMTransportRequest *secondRequest = [self.sut.requestGenerators nextRequest];
    XCTAssertNotNil(secondRequest);

}

- (void)testThatItReturnsSlowSyncDoneAfterCompletingRequest
{
    // given
    [self.sut setNeedsSlowSync];
    XCTAssertFalse(self.sut.isSlowSyncDone);
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    NSDictionary *payload = [self samplePayloadForUserID:[NSUUID createUUID]];
    
    // when
    [request completeWithResponse:[ZMTransportResponse responseWithPayload:payload HTTPStatus:200 transportSessionError:nil]];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertTrue(self.sut.isSlowSyncDone);
    
}

- (void)testThatItIsCreatedWithIsSlowSyncDoneTrue
{
    XCTAssertTrue(self.sut.isSlowSyncDone);
}


- (void)testThatItCalls_FetchRequestForTrackedObjects_OnUpStreamObjectSync
{
    // expect
    NSFetchRequest *request = [OCMockObject niceMockForClass:[NSFetchRequest class]];
    [(ZMUpstreamModifiedObjectSync *)[[(id)self.upstreamObjectSync expect] andReturn:request] fetchRequestForTrackedObjects];

    // when
    NSFetchRequest *fetchRequest = [self.sut fetchRequestForTrackedObjects];

    XCTAssertEqual(fetchRequest, request);
}

- (void)testThatItCalls_addTrackedObjects_OnUpStreamObjectSync
{
    // expect
    ZMUser *selfUser = [ZMUser selfUserInContext:self.uiMOC];
    NSSet *objects = [NSSet setWithObject:selfUser];
    [[(OCMockObject *)self.upstreamObjectSync expect] addTrackedObjects:objects];
    
    // when
    [self.sut addTrackedObjects:objects];
}


@end



@implementation ZMSelfTranscoderTests (UpstreamSync)

- (void)testThatItGeneratesARequestForUpdatingChangedSelfUser
{
    NSDictionary* uploadPayload = @{
                                    @"name" : @"My new name testThatItGeneratesARequestForUpdatingChangedSelfUser",
                                    @"accent_id" : @(ZMAccentColorBrightYellow)
                                    };
    
    [self checkThatItGeneratesUpstreamUpdateRequestWithPayload:uploadPayload changedKeys:[NSSet setWithObjects:@"name", @"accentColorValue", nil]];
}


- (void)testThatItGeneratesARequestForUpdatingJustTheNameInChangedSelfUser
{
    NSDictionary* uploadPayload = @{
                                    @"name" : @"My new name testThatItGeneratesARequestForUpdatingJustTheNameInChangedSelfUser",
                                    };
    
    [self checkThatItGeneratesUpstreamUpdateRequestWithPayload:uploadPayload changedKeys:[NSSet setWithObjects:@"name", nil]];
}


- (void)testThatItGeneratesARequestForUpdatingJustTheAccentColorInChangedSelfUser
{
    NSDictionary* uploadPayload = @{
                                    @"accent_id" : @(ZMAccentColorBrightYellow)
                                    };
    
    [self checkThatItGeneratesUpstreamUpdateRequestWithPayload:uploadPayload changedKeys:[NSSet setWithObjects:@"accentColorValue", nil]];
}

- (void)checkThatItGeneratesUpstreamUpdateRequestWithPayload:(NSDictionary *)expectedPayload changedKeys:(NSSet *)changedKeys
{
    
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        ZMUser *selfUser = [ZMUser selfUserInContext:self.syncMOC];
        selfUser.name = expectedPayload[@"name"] ?: @"Random User";
        selfUser.accentColorValue = (ZMAccentColor) [(expectedPayload[@"accent_id"] ?: @(ZMAccentColorSoftPink)) integerValue];
        
        // when
        NSSet *updatedKeys = changedKeys;
        ZMUpstreamRequest *request = [(id<ZMUpstreamTranscoder>) self.sut requestForUpdatingObject:selfUser forKeys:updatedKeys];
        
        // then
        XCTAssertNotNil(request);
        XCTAssertEqualObjects(request.transportRequest.path, @"/self");
        XCTAssertEqual(request.transportRequest.method, ZMMethodPUT);
        XCTAssertEqualObjects(request.transportRequest.payload, expectedPayload);
        XCTAssertEqualObjects(request.keys, updatedKeys);
        
    }];
    
}


- (void)testThatItAlwaysReturnsNilForRequestsForInsertedObjects
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        ZMUser *selfUser = [ZMUser selfUserInContext:self.syncMOC];
        
        // when
        ZMUpstreamRequest *request = [(id<ZMUpstreamTranscoder>) self.sut requestForInsertingObject:selfUser forKeys:[NSSet setWithObject:@"name"]];
        
        // then
        XCTAssertNil(request);
    }];
}


- (void)testThatItAlwaysReturnsNoForUpdatingUpdatedObject
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        ZMUser *selfUser = [ZMUser selfUserInContext:self.syncMOC];
        selfUser.name = @"Joe Random User";
        ZMUpstreamRequest *request = [(id<ZMUpstreamTranscoder>) self.sut requestForInsertingObject:selfUser forKeys:[NSSet setWithObject:@"name"]];
        
        // when
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:nil HTTPStatus:200 transportSessionError:nil];
        BOOL needsToUpdateMoreObjects = [(id<ZMUpstreamTranscoder>) self.sut updateUpdatedObject:selfUser requestUserInfo:request.userInfo response:response keysToParse:[NSSet set]];
        
        // then
        XCTAssertFalse(needsToUpdateMoreObjects);
    }];
}



- (void)DISABLED_becauseItTraps_testThatItDoesNotGenerateARequestForUpdatingChangedNonSelfUser
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user.name = @"Joe Random User";
        user.accentColorValue = ZMAccentColorBrightYellow;
        user.remoteIdentifier = [NSUUID createUUID];
        
        // when
        ZMUpstreamRequest *request = [(id<ZMUpstreamTranscoder>) self.sut requestForUpdatingObject:user forKeys:[NSSet setWithObjects:@"name", @"accentColorValue", nil]];
        
        // then
        XCTAssertNil(request);
    }];
}

- (void)testThatItReturnsAnPUTRequestForSelf
{
    // given
    [self markSlowSyncAsDone];
    
    ZMTransportRequest *request = [ZMTransportRequest requestWithPath:@"/self" method:ZMMethodPUT payload:@{}];
    [[[(OCMockObject *)self.upstreamObjectSync expect] andReturn:request] nextRequest];
    [[[(OCMockObject *)self.upstreamObjectSync expect] andReturn:nil] nextRequest];
    
    // when
    ZMTransportRequest *receivedRequest = [self.sut.requestGenerators nextRequest];
    
    // then
    XCTAssertEqual(receivedRequest, request);
}


- (void)testThatContextChangeTrackersContainUpstreamObjectSync
{
    [self markSlowSyncAsDone];
    
    // when
    NSArray *changeTrackers = self.sut.contextChangeTrackers;
    
    // then
    XCTAssertTrue([changeTrackers containsObject:self.upstreamObjectSync]);
    
}



- (void)markSlowSyncAsDone;
{
    [self.sut setNeedsSlowSync];
    NSDictionary *payload = [self samplePayloadForUserID:[NSUUID createUUID]];
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPStatus:200 transportSessionError:nil];
    
    // simulate hard sync done
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    [request completeWithResponse:response];
    WaitForAllGroupsToBeEmpty(0.5);
}

@end


@implementation ZMSelfTranscoderTests (ImageUpload)




- (void)setUpSelfUser:(ZMUser **)selfUserPointer
{
    __block ZMUser *selfUser;
    NSUUID *selfUserAndSelfConversationID = [NSUUID createUUID];
    
    [self.syncMOC performGroupedBlockAndWaitWithReasonableTimeout:^{
        selfUser = [ZMUser selfUserInContext:self.syncMOC];
        selfUser.remoteIdentifier = selfUserAndSelfConversationID;
        selfUser.accentColorValue = ZMAccentColorStrongBlue;
        
        [selfUser setImageData:[self dataForResource:@"medium" extension:@"jpg"] forFormat:ZMImageFormatMedium properties:nil];
        [selfUser setImageData:[self dataForResource:@"tiny" extension:@"jpg"] forFormat:ZMImageFormatProfile properties:nil];
        
        ZMConversation *selfConv = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        selfConv.conversationType = ZMConversationTypeSelf;
        selfConv.remoteIdentifier = selfUserAndSelfConversationID;
        
        selfUser.needsToBeUpdatedFromBackend = NO;
        [selfUser setLocallyModifiedKeys:[NSSet setWithArray:@[@"imageSmallProfileData", @"imageMediumData"]]];
        
        *selfUserPointer = selfUser;
    }];
}



- (void)testThatItSetsTheImageMetaDataAsTheProfileImageDataWithBlock:(void(^)(ZMUser *user))block;
{
    // given
    [self useSUTWithRealDependencies];
    
    ZMUser *selfUser;
    [self setUpSelfUser:&selfUser];

    NSUUID *correlationID = [NSUUID createUUID];
    NSUUID *smallProfileID = [NSUUID createUUID];
    NSUUID *mediumID = [NSUUID createUUID];
    NSDictionary *smallProfileAssetData = [ZMAssetMetaDataEncoder createAssetDataWithID:smallProfileID
                                                                             imageOwner:selfUser
                                                                                 format:ZMImageFormatProfile
                                                                          correlationID:correlationID];
    
    NSDictionary *mediumAssetData = [ZMAssetMetaDataEncoder createAssetDataWithID:mediumID
                                                                       imageOwner:selfUser
                                                                           format:ZMImageFormatMedium
                                                                    correlationID:correlationID];
    
    [self.syncMOC performBlockAndWait:^{
        selfUser.smallProfileRemoteIdentifier = smallProfileID;
        selfUser.mediumRemoteIdentifier = mediumID;
        selfUser.imageCorrelationIdentifier = correlationID;
        [selfUser setLocallyModifiedKeys:[NSSet setWithArray:@[@"mediumRemoteIdentifier_data", @"smallProfileRemoteIdentifier_data"]]];
        [selfUser resetLocallyModifiedKeys:[NSSet setWithArray:@[ @"imageSmallProfileData", @"imageMediumData" ]]];
    }];
    
    // when
    block(selfUser);

    // next request should set both images to /self
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    
    // then
    NSDictionary *expectedPayload = @{@"picture": @[smallProfileAssetData, mediumAssetData]};
    
    XCTAssertNotNil(request);
    
    XCTAssertEqual(request.method, ZMMethodPUT);
    XCTAssertEqualObjects(request.path, @"/self");
    AssertEqualDictionaries(request.payload.asDictionary, expectedPayload);
    
}

- (void)testThatItSetsTheImageMetaDataAsTheProfileImageData_OnInitialization
{
    [self testThatItSetsTheImageMetaDataAsTheProfileImageDataWithBlock:^(ZMUser *user) {
        NOT_USED(user);
        [ZMChangeTrackerBootstrap bootStrapChangeTrackers:self.sut.contextChangeTrackers onContext:self.syncMOC];
    }];
}


- (void)testThatItSetsTheImageMetaDataAsTheProfileImageData_OnObjectsDidChange
{
    [self testThatItSetsTheImageMetaDataAsTheProfileImageDataWithBlock:^(ZMUser *user) {
        [self.sut.contextChangeTrackers[0] objectsDidChange:[NSSet setWithObject:user]];
     }];    
}

- (void)useSUTWithRealDependencies {
    [self.sut tearDown];
    //let it create an actual ZMUpstreamSync, not a mocked one
    self.realClientRegistrationStatus = [[ZMClientRegistrationStatus alloc] initWithManagedObjectContext:self.syncMOC loginCredentialProvider:nil updateCredentialProvider:nil cookie:nil registrationStatusDelegate:nil];
    ;
    self.sut = (id) [[ZMSelfTranscoder alloc] initWithClientRegistrationStatus:self.realClientRegistrationStatus
                                                          managedObjectContext:self.syncMOC];
}

- (void)testThatItResetsTheProfileImageWithBlock:(void(^)(ZMUser *user))block;
{
    // when
    [self useSUTWithRealDependencies];

    ZMUser *selfUser;
    [self setUpSelfUser:&selfUser];

    [self.syncMOC performBlockAndWait:^{
        selfUser.smallProfileRemoteIdentifier = nil;
        selfUser.mediumRemoteIdentifier = nil;
        [selfUser setLocallyModifiedKeys:[NSSet setWithArray:@[@"mediumRemoteIdentifier_data", @"smallProfileRemoteIdentifier_data"]]];
        [selfUser resetLocallyModifiedKeys:[NSSet setWithArray:@[@"imageSmallProfileData", @"imageMediumData"]]];
    }];
    
        // next request should set both images to /self
    block(selfUser);
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    
    // then
    NSDictionary *expectedPayload = @{@"picture": @[]};
    
    XCTAssertNotNil(request);
    
    XCTAssertEqual(request.method, ZMMethodPUT);
    XCTAssertEqualObjects(request.path, @"/self");
    AssertEqualDictionaries(request.payload.asDictionary, expectedPayload);
}

- (void)testThatItResetsTheProfileImage_OnInitialization
{
    [self testThatItResetsTheProfileImageWithBlock:^(ZMUser *user) {
        NOT_USED(user);
        [ZMChangeTrackerBootstrap bootStrapChangeTrackers:self.sut.contextChangeTrackers onContext:self.syncMOC];
    }];
}


- (void)testThatItResetsTheProfileImage_OnObjectsDidChange
{
    [self testThatItResetsTheProfileImageWithBlock:^(ZMUser *user) {
        [self.sut.contextChangeTrackers[0] objectsDidChange:[NSSet setWithObject:user]];
    }];
}

- (void)testThatItSetsLocalImageDataToNilAfterResettingTheProfileImageWithBlock:(void(^)(ZMUser *user))block;
{
    // given
    [self useSUTWithRealDependencies];
    
    ZMUser *selfUser;
    [self setUpSelfUser:&selfUser];
    
    [self.syncMOC performBlockAndWait:^{
        selfUser.imageMediumData = [@"a" dataUsingEncoding:NSUTF8StringEncoding];
        selfUser.imageSmallProfileData = [@"b" dataUsingEncoding:NSUTF8StringEncoding];
        selfUser.smallProfileRemoteIdentifier = nil;
        selfUser.mediumRemoteIdentifier = nil;
        [selfUser setLocallyModifiedKeys:[NSSet setWithArray:@[@"mediumRemoteIdentifier_data", @"smallProfileRemoteIdentifier_data"]]];
        [selfUser resetLocallyModifiedKeys:[NSSet setWithArray:@[@"imageSmallProfileData", @"imageMediumData"]]];
    }];
    
    
    // when
    block(selfUser);
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    
    [self.syncMOC performBlockAndWait:^{
        [request completeWithResponse:[ZMTransportResponse responseWithPayload:nil HTTPStatus:200 transportSessionError:nil]];
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertNil(selfUser.imageMediumData);
    XCTAssertNil(selfUser.imageSmallProfileData);
}

- (void)testThatItSetsLocalImageDataToNilAfterResettingTheProfileImage_OnInitialization
{
    [self testThatItSetsLocalImageDataToNilAfterResettingTheProfileImageWithBlock:^(ZMUser *user) {
        NOT_USED(user);
        [ZMChangeTrackerBootstrap bootStrapChangeTrackers:self.sut.contextChangeTrackers onContext:self.syncMOC];
    }];
}

- (void)testThatItSetsLocalImageDataToNilAfterResettingTheProfileImage_OnObjectDidChange

{
    [self testThatItSetsLocalImageDataToNilAfterResettingTheProfileImageWithBlock:^(ZMUser *user) {
        [self.sut.contextChangeTrackers[0] objectsDidChange:[NSSet setWithObject:user]];
    }];
}

- (void)testThatItDoesNotResetTheTheLocalImageDataWhenSettingTheProfileImageWithBlock:(void(^)(ZMUser *user))block;
{
    // given
    [self useSUTWithRealDependencies];
    
    ZMUser *selfUser;
    [self setUpSelfUser:&selfUser];
    
    [self.syncMOC performBlockAndWait:^{
        [selfUser setImageData:[self dataForResource:@"medium" extension:@"jpg"] forFormat:ZMImageFormatMedium properties:nil];
        [selfUser setImageData:[self dataForResource:@"tiny" extension:@"jpg"] forFormat:ZMImageFormatProfile properties:nil];
        selfUser.smallProfileRemoteIdentifier = NSUUID.createUUID;
        selfUser.mediumRemoteIdentifier = NSUUID.createUUID;
        selfUser.imageCorrelationIdentifier = NSUUID.createUUID;
        [selfUser setLocallyModifiedKeys:[NSSet setWithArray:@[@"mediumRemoteIdentifier_data", @"smallProfileRemoteIdentifier_data"]]];
        [selfUser resetLocallyModifiedKeys:[NSSet setWithArray:@[@"imageSmallProfileData", @"imageMediumData"]]];
    }];
    
    
    // when
    block(selfUser);
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    
    [self.syncMOC performBlockAndWait:^{
        [request completeWithResponse:[ZMTransportResponse responseWithPayload:nil HTTPStatus:200 transportSessionError:nil]];
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertNotNil(selfUser.imageMediumData);
    XCTAssertNotNil(selfUser.imageSmallProfileData);
}

- (void)testThatItDoesNotResetTheTheLocalImageDataWhenSettingTheProfileImage_OnInitialization
{
    [self testThatItDoesNotResetTheTheLocalImageDataWhenSettingTheProfileImageWithBlock:^(ZMUser *user) {
        NOT_USED(user);
        [ZMChangeTrackerBootstrap bootStrapChangeTrackers:self.sut.contextChangeTrackers onContext:self.syncMOC];
    }];
}

- (void)testThatItDoesNotResetTheTheLocalImageDataWhenSettingTheProfileImage_OnObjectsDidChange

{
    [self testThatItDoesNotResetTheTheLocalImageDataWhenSettingTheProfileImageWithBlock:^(ZMUser *user) {
        [self.sut.contextChangeTrackers[0] objectsDidChange:[NSSet setWithObject:user]];
    }];
}

- (void)testThatItDoesNotResetTheProfileImageWhenRequestKeysDoNotContainImageDataKeysWithBlock:(void(^)(ZMUser *user))block;
{
    
    // when
    [self useSUTWithRealDependencies];
    
    ZMUser *selfUser;
    [self setUpSelfUser:&selfUser];
    
    
    [self.syncMOC performBlockAndWait:^{
        selfUser.accentColorValue = ZMAccentColorBrightOrange;
        [selfUser setLocallyModifiedKeys:[NSSet setWithObject:@"accentColorValue"]];
    }];
    
    // next request should set both images to /self
    block(selfUser);
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    
    [self.syncMOC performBlockAndWait:^{
        [request completeWithResponse:[ZMTransportResponse responseWithPayload:nil HTTPStatus:200 transportSessionError:nil]];
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    
    
    XCTAssertNotNil(request);
    XCTAssertNotNil(selfUser.imageSmallProfileData);
    XCTAssertNotNil(selfUser.imageMediumData);
    
    XCTAssertEqual(request.method, ZMMethodPUT);
    XCTAssertEqualObjects(request.path, @"/self");
}

- (void)testThatItDoesNotResetTheProfileImageWhenRequestKeysDoNotContainImageDataKeys_OnInitialization
{
    [self testThatItDoesNotResetTheProfileImageWhenRequestKeysDoNotContainImageDataKeysWithBlock:^(ZMUser *user) {
        NOT_USED(user);
        [ZMChangeTrackerBootstrap bootStrapChangeTrackers:self.sut.contextChangeTrackers onContext:self.syncMOC];
    }];
}

- (void)testThatItDoesNotResetTheProfileImageWhenRequestKeysDoNotContainImageDataKeys_OnObjectsDidChange
{
    [self testThatItDoesNotResetTheProfileImageWhenRequestKeysDoNotContainImageDataKeysWithBlock:^(ZMUser *user) {
        [self.sut.contextChangeTrackers[0] objectsDidChange:[NSSet setWithObject:user]];
    }];
}

- (void)testThatItSetsTheTrackingIdentfier;
{
    // given
    NSDictionary *payload = [self samplePayloadForUserID:[NSUUID createUUID]];
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPStatus:200 transportSessionError:nil];

    // when
    [self.sut didReceiveResponse:response forSingleRequest:nil];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqualObjects(self.uiMOC.userSessionTrackingIdentifier, self.trackingIdentifier);
}

- (void)testThatItDoesNotClearTheTrackingIdentifier;
{
    // given
    NSMutableDictionary *payload = [NSMutableDictionary dictionaryWithDictionary:[self samplePayloadForUserID:[NSUUID createUUID]]];
    [payload removeObjectForKey:@"tracking_id"];
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPStatus:200 transportSessionError:nil];
    self.uiMOC.userSessionTrackingIdentifier = self.trackingIdentifier;
    [self.uiMOC saveOrRollback];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    [self performIgnoringZMLogError:^{
        [self.sut didReceiveResponse:response forSingleRequest:nil];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqualObjects(self.uiMOC.userSessionTrackingIdentifier, self.trackingIdentifier);
}

@end


@implementation ZMSelfTranscoderTests (ClientRegistrationStatus)

- (void)testThatItReturnsTheTimedDownstreamSyncWhenTHeClientRegistrationStatusIsWaitingForEmailVerififcation
{
    // given
    [(ZMClientRegistrationStatus *)[[self.mockClientRegistrationStatus expect] andReturnValue:OCMOCK_VALUE(ZMClientRegistrationPhaseWaitingForEmailVerfication)] currentPhase];
    
    // when
    NSArray *generators = [self.sut requestGenerators];
    
    // then
    XCTAssertEqual(generators.count, 1u);
    XCTAssertEqual([generators.firstObject class], [ZMTimedSingleRequestSync class]);
    [self.mockClientRegistrationStatus verify];
}

- (void)testThatItForwardSelfUserUpdatesToTheClientRegsitrationStatus_RemoteIdentifier
{
    // given
    [(ZMClientRegistrationStatus *)[[self.mockClientRegistrationStatus expect] andReturnValue:OCMOCK_VALUE(ZMClientRegistrationPhaseWaitingForSelfUser)] currentPhase];
    [[self.mockClientRegistrationStatus expect] didFetchSelfUser];
    
    // when
    NSDictionary *payload = @{@"id": [NSUUID UUID].transportString,
                              @"tracking_id": @"someID"};
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPStatus:200 transportSessionError:nil];
    [self.sut didReceiveResponse:response forSingleRequest:nil];
    
    // then
    [self.mockClientRegistrationStatus verify];

}

- (void)testThatItForwardSelfUserUpdatesToTheClientRegsitrationStatus_EmailAddress
{
    // given
    [(ZMClientRegistrationStatus *)[[self.mockClientRegistrationStatus expect] andReturnValue:OCMOCK_VALUE(ZMClientRegistrationPhaseWaitingForEmailVerfication)] currentPhase];
    [[self.mockClientRegistrationStatus expect] didFetchSelfUser];
    
    // when
    NSDictionary *payload = @{@"email": @"my@example.com",
                              @"tracking_id": @"someID"};
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPStatus:200 transportSessionError:nil];
    [self.sut didReceiveResponse:response forSingleRequest:nil];
    
    // then
    [self.mockClientRegistrationStatus verify];
}

- (void)testThatOnSuccessfullyUpdatingEmailAddressItResetsTheTimeInterval
{
    // given
    [(ZMClientRegistrationStatus *)[[self.mockClientRegistrationStatus stub] andReturnValue:OCMOCK_VALUE(ZMClientRegistrationPhaseWaitingForEmailVerfication)] currentPhase];
    [[self.mockClientRegistrationStatus stub] didFetchSelfUser];
    ZMSelfTranscoderPendingValidationRequestInterval = 5;
    
    // when
    NSDictionary *payload = @{@"email": @"my@example.com",
                              @"tracking_id": @"someID"};
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPStatus:200 transportSessionError:nil];
    [self.sut didReceiveResponse:response forSingleRequest:self.sut.timedDownstreamSync];
    
    // then
    XCTAssertEqual(self.sut.timedDownstreamSync.timeInterval, 0);
}

- (void)testThatOnUnsuccessfullyUpdatingEmailAddressItDoesNotResetTheTimeInterval
{
    // given
    [(ZMClientRegistrationStatus *)[[self.mockClientRegistrationStatus stub] andReturnValue:OCMOCK_VALUE(ZMClientRegistrationPhaseWaitingForEmailVerfication)] currentPhase];
    [[self.mockClientRegistrationStatus stub] didFetchSelfUser];
    ZMSelfTranscoderPendingValidationRequestInterval = 5;
    
    // when
    NSDictionary *payload = @{@"email": [NSNull null],
                              @"tracking_id": @"someID"};
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPStatus:200 transportSessionError:nil];
    [self.sut didReceiveResponse:response forSingleRequest:self.sut.timedDownstreamSync];
    
    // then
    XCTAssertEqualWithAccuracy(self.sut.timedDownstreamSync.timeInterval, 5, 0.5);
}

@end
