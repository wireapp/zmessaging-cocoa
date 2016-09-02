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
@import ZMCMockTransport;
@import Cryptobox;
@import ZMProtos;
@import ZMCDataModel;

#import "ZMClientMessageTranscoder+Internal.h"
#import "ZMMessageTranscoderTests.h"
#import "ZMSyncStrategy.h"
#import "ZMUpstreamInsertedObjectSync.h"
#import "ZMUpstreamModifiedObjectSync.h"
#import "ZMMessageExpirationTimer.h"
#import "ZMUpstreamTranscoder.h"
#import "ZMChangeTrackerBootstrap+Testing.h"
#import "ZMImagePreprocessingTracker.h"

#import "ZMLocalNotificationDispatcher.h"
#import <zmessaging/ZMUpstreamRequest.h>
#import <zmessaging/zmessaging-Swift.h>
#import "ZMContextChangeTracker.h"

@interface FakeClientMessageRequestFactory : NSObject

@end

@implementation FakeClientMessageRequestFactory

- (ZMTransportRequest *)upstreamRequestForAssetMessage:(ZMImageFormat __unused)format message:(ZMAssetClientMessage *__unused)message forConversationWithId:(NSUUID *__unused)conversationId
{
    return nil;
}


@end

@interface ZMClientMessageTranscoderTests : ZMMessageTranscoderTests

@property (nonatomic) ZMClientRegistrationStatus *mockClientRegistrationStatus;
@property (nonatomic) BackgroundAPNSConfirmationStatus *mockAPNSConfirmationStatus;

@end



@implementation ZMClientMessageTranscoderTests

- (void)setUp
{
    [super setUp];
    self.mockAPNSConfirmationStatus = [OCMockObject niceMockForClass:[BackgroundAPNSConfirmationStatus class]];
    [[[(id)self.mockAPNSConfirmationStatus stub] andReturnValue:@(NO)] needsToSyncMessages];
    self.mockClientRegistrationStatus = [OCMockObject mockForProtocol:@protocol(ZMClientClientRegistrationStatusProvider)];
    self.sut = [[ZMClientMessageTranscoder alloc] initWithManagedObjectContext:self.syncMOC
                                                              localNotificationDispatcher:self.notificationDispatcher
                                                                 clientRegistrationStatus:self.mockClientRegistrationStatus
                                                        apnsConfirmationStatus:self.mockAPNSConfirmationStatus];
    
    [[self.mockExpirationTimer stub] tearDown];
    [self verifyMockLater:self.mockClientRegistrationStatus];
    [self verifyMockLater:self.mockAPNSConfirmationStatus];
}

- (void)tearDown
{
    [self.sut tearDown];
    self.sut = nil;
    [super tearDown];
}

- (UserClient *)insertMissingClientWithSelfClient:(UserClient *)selfClient;
{
    UserClient *missingClient = [UserClient insertNewObjectInManagedObjectContext:self.syncMOC];
    missingClient.remoteIdentifier = [NSString createAlphanumericalString];
    missingClient.user = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
    [selfClient missesClient:missingClient];
    
    return missingClient;
}

- (ZMClientMessage *)insertMessageInConversation:(ZMConversation *)conversation
{
    NSString *messageText = @"foo";
    ZMGenericMessage *genericMessage = [ZMGenericMessage messageWithText:messageText nonce:[NSUUID createUUID].transportString];
    ZMClientMessage *message = [conversation appendClientMessageWithData:genericMessage.data];
    return message;
}


- (void)testThatItReturnsSelfClientAsDependentObjectForMessageIfItHasMissingClients
{
    [self.syncMOC performGroupedBlock:^{
        
        //given
        UserClient *client = [self createSelfClient];
        UserClient *missingClient = [self insertMissingClientWithSelfClient:client];
        
        ZMConversation *conversation = [self insertGroupConversation];
        [conversation.mutableOtherActiveParticipants addObject:missingClient.user];
        [self.syncMOC saveOrRollback];
        
        ZMClientMessage *message = [self insertMessageInConversation:conversation];
        
        //when
        ZMManagedObject *dependentObject = [self.sut dependentObjectNeedingUpdateBeforeProcessingObject:message];
        
        // then
        XCTAssertNotNil(dependentObject);
        XCTAssertEqual(dependentObject, client);
    }];

    WaitForAllGroupsToBeEmpty(0.5);
}


- (void)testThatItReturnsConversationIfNeedsToBeUpdatedFromBackendBeforeMissingClients
{
    [self.syncMOC performGroupedBlock:^{
        
        //given
        UserClient *client = [self createSelfClient];
        UserClient *missingClient = [self insertMissingClientWithSelfClient:client];
        
        ZMConversation *conversation = [self insertGroupConversation];
        [conversation.mutableOtherActiveParticipants addObject:missingClient.user];
        
        ZMClientMessage *message = [self insertMessageInConversation:conversation];
        
        // when
        conversation.needsToBeUpdatedFromBackend = YES;
        ZMManagedObject *dependentObject1 = [self.sut dependentObjectNeedingUpdateBeforeProcessingObject:message];
        
        // then
        XCTAssertNotNil(dependentObject1);
        XCTAssertEqual(dependentObject1, conversation);
    }];

    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItReturnsConnectionIfNeedsToBeUpdatedFromBackendBeforeMissingClients
{
    [self.syncMOC performGroupedBlock:^{
        
        //given
        UserClient *client = [self createSelfClient];
        UserClient *missingClient = [self insertMissingClientWithSelfClient:client];
        
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.conversationType = ZMConversationTypeOneOnOne;
        conversation.connection = [ZMConnection insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.connection.to = missingClient.user;
        [conversation.mutableOtherActiveParticipants addObject:missingClient.user];
        
        ZMClientMessage *message = [self insertMessageInConversation:conversation];
        
        // when
        conversation.connection.needsToBeUpdatedFromBackend = YES;
        ZMManagedObject *dependentObject1 = [self.sut dependentObjectNeedingUpdateBeforeProcessingObject:message];
        
        // then
        XCTAssertNotNil(dependentObject1);
        XCTAssertEqual(dependentObject1, conversation.connection);
    }];

    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItDoesNotReturnSelfClientAsDependentObjectForMessageIfConversationIsNotAffectedByMissingClients
{
    [self.syncMOC performGroupedBlock:^{
        
        //given
        UserClient *client = [self createSelfClient];
        UserClient *missingClient = [self insertMissingClientWithSelfClient:client];
        
        
        ZMConversation *conversation1 = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        [conversation1.mutableOtherActiveParticipants addObject:missingClient.user];
        
        ZMConversation *conversation2 = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation2.conversationType = ZMConversationTypeGroup;
        conversation2.remoteIdentifier = [NSUUID createUUID];
        
        ZMClientMessage *message = [self insertMessageInConversation:conversation2];
        
        // when
        ZMManagedObject *dependentObject = [self.sut dependentObjectNeedingUpdateBeforeProcessingObject:message];
        
        // then
        XCTAssertNil(dependentObject);
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItReturnsNilAsDependentObjectForMessageIfItHasNoMissingClients
{
    [self.syncMOC performGroupedBlock:^{
        
        //given
        [self createSelfClient];
        
        ZMConversation *conversation = [self insertGroupConversation];
        ZMClientMessage *message = [self insertMessageInConversation:conversation];
        
        // when
        ZMManagedObject *dependentObject = [self.sut dependentObjectNeedingUpdateBeforeProcessingObject:message];
        
        // then
        XCTAssertNil(dependentObject);
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItReturnsAPreviousPendingTextMessageAsDependency
{
    [self.syncMOC performGroupedBlock:^{
        
        //given
        [self createSelfClient];
        NSDate *zeroTime = [NSDate dateWithTimeIntervalSince1970:1000];
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.remoteIdentifier = [NSUUID createUUID];
        
        ZMMessage *message = [conversation appendMessageWithText:@"message a1"];
        message.nonce = [NSUUID createUUID];
        message.serverTimestamp = zeroTime;
        message.eventID = [self createEventID]; // already delivered message
        
        ZMMessage *nextMessage = [conversation appendMessageWithText:@"message a2"];
        nextMessage.serverTimestamp = [NSDate dateWithTimeInterval:100 sinceDate:zeroTime];
        nextMessage.nonce = [NSUUID createUUID]; // undelivered
        
        ZMGenericMessage *genericMessage = [ZMGenericMessage messageWithText:@"message a3" nonce:[NSUUID createUUID].transportString];
        ZMClientMessage *lastMessage = [conversation appendClientMessageWithData:genericMessage.data];
        lastMessage.serverTimestamp = [NSDate dateWithTimeInterval:10 sinceDate:nextMessage.serverTimestamp];
        
        // when
        XCTAssertTrue([self.syncMOC saveOrRollback]);
        
        // then
        ZMManagedObject *dependency = [self.sut dependentObjectNeedingUpdateBeforeProcessingObject:lastMessage];
        XCTAssertEqual(dependency, nextMessage);
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItGeneratesARequestToSendAClientMessage
{
    [self.syncMOC performGroupedBlock:^{
        
        // given
        [self createSelfClient];
        ZMConversation *conversation = [self insertGroupConversation];
        NSString *messageText = @"foo";
        ZMGenericMessage *genericMessage = [ZMGenericMessage messageWithText:messageText nonce:[NSUUID createUUID].transportString];
        
        ZMClientMessage *message = [conversation appendClientMessageWithData:genericMessage.data];
        XCTAssertTrue([self.syncMOC saveOrRollback]);
        
        // when
        ZMUpstreamRequest *request = [(id<ZMUpstreamTranscoder>) self.sut requestForInsertingObject:message forKeys:nil];
        
        // then
        // POST /conversations/{cnv}/otr/messages
        NSString *expectedPath = [NSString pathWithComponents:@[@"/", @"conversations", conversation.remoteIdentifier.transportString, @"otr", @"messages"]];
        
        XCTAssertNotNil(request);
        XCTAssertNotNil(request.transportRequest);
        XCTAssertEqualObjects(expectedPath, request.transportRequest.path);
        XCTAssertEqual(ZMMethodPOST, request.transportRequest.method);
        XCTAssertEqualObjects(request.transportRequest.binaryDataType, @"application/x-protobuf");
        XCTAssertNotNil(request.transportRequest.binaryData);
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatANewOtrMessageIsCreatedFromAnEvent
{
    [self.syncMOC performGroupedBlock:^{
        
        // given
        UserClient *client = [self createSelfClient];
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.remoteIdentifier = [NSUUID createUUID];
        [self.syncMOC saveOrRollback];
        
        NSString *text = @"Everything";
        NSString *base64String = @"CiQ5ZTU2NTQwOS0xODZiLTRlN2YtYTE4NC05NzE4MGE0MDAwMDQSDAoKRXZlcnl0aGluZw==";
        NSDictionary *payload = @{@"recipient": client.remoteIdentifier, @"sender": client.remoteIdentifier, @"text": base64String};
        NSDictionary *eventPayload = @{@"type":         @"conversation.otr-message-add",
                                       @"data":         payload,
                                       @"conversation": conversation.remoteIdentifier.transportString,
                                       @"time":         [NSDate dateWithTimeIntervalSince1970:555555].transportString
                                       };
        ZMUpdateEvent *updateEvent = [ZMUpdateEvent decryptedUpdateEventFromEventStreamPayload:eventPayload uuid:[NSUUID createUUID] source:ZMUpdateEventSourceWebSocket];
        
        // when
        [self.sut processEvents:@[updateEvent] liveEvents:NO prefetchResult:nil];
        
        // then
        XCTAssertEqualObjects([conversation.messages.lastObject messageText], text);
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatANewOtrMessageIsCreatedFromADecryptedAPNSEvent
{
    [self.syncMOC performGroupedBlock:^{
        // given
        UserClient *client = [self createSelfClient];
        NSString *text = @"Everything";
        NSUUID *conversationID = [NSUUID createUUID];
        
        //create encrypted message
        ZMGenericMessage *message = [ZMGenericMessage messageWithText:text nonce:[NSUUID createUUID].transportString];
        NSData *encryptedData = [self encryptedMessage:message recipient:client];
        
        NSDictionary *payload = @{@"recipient": client.remoteIdentifier, @"sender": client.remoteIdentifier, @"text": [encryptedData base64String]};
        ZMUpdateEvent *updateEvent = [ZMUpdateEvent eventFromEventStreamPayload:
                                      @{
                                        @"type":@"conversation.otr-message-add",
                                        @"data":payload,
                                        @"conversation":conversationID.transportString,
                                        @"time":[NSDate dateWithTimeIntervalSince1970:555555].transportString
                                        } uuid:nil];
        
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.remoteIdentifier = conversationID;
        [self.syncMOC saveOrRollback];
        
        __block ZMUpdateEvent *decryptedEvent;
        [self.syncMOC.zm_cryptKeyStore.encryptionContext perform:^(EncryptionSessionsDirectory * _Nonnull sessionsDirectory) {
            decryptedEvent = [sessionsDirectory decryptUpdateEventAndAddClient:updateEvent managedObjectContext:self.syncMOC];
        }];
        
        // when
        [self.sut processEvents:@[decryptedEvent] liveEvents:NO prefetchResult:nil];
        
        // then
        XCTAssertEqualObjects([conversation.messages.lastObject messageText], text);
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItGeneratesARequestToSendAClientMessageExternalWithExternalBlob
{
    NSString *longText = [@"Hello" stringByPaddingToLength:10000 withString:@"?" startingAtIndex:0];
    [self checkThatItGeneratesARequestToSendOTRMessageWhenAMessageIsInsertedWithText:longText block:^(ZMMessage *message) {
        [self.sut.contextChangeTrackers[0] objectsDidChange:@[message].set];
    }];
}

- (void)testThatItGeneratesARequestToSendAClientMessageWhenAMessageIsInsertedWithBlock:(void(^)(ZMMessage *message))block
{
    [self.syncMOC performGroupedBlock:^{
        
        // given
        [self createSelfClient];
        ZMConversation *conversation = [self insertGroupConversation];
        ZMGenericMessage *genericMessage = [ZMGenericMessage messageWithText:@"foo" nonce:[NSUUID createUUID].transportString];
        
        ZMClientMessage *message = [conversation appendClientMessageWithData:genericMessage.data];
        XCTAssertTrue([self.syncMOC saveOrRollback]);
        
        // when
        block(message);
        ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
        
        // then
        //POST /conversations/{cnv}/messages
        NSString *expectedPath = [NSString pathWithComponents:@[@"/", @"conversations", conversation.remoteIdentifier.transportString, @"otr", @"messages"]];
        XCTAssertNotNil(request);
        XCTAssertEqualObjects(expectedPath, request.path);
        XCTAssertNotNil(request.binaryData);
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
}


- (void)checkThatItGeneratesARequestToSendOTRMessageWhenAMessageIsInsertedWithBlock:(void(^)(ZMMessage *message))block
{
    [self checkThatItGeneratesARequestToSendOTRMessageWhenAMessageIsInsertedWithText:@"foo" block:block];
}

- (void)checkThatItGeneratesARequestToSendOTRMessageWhenAMessageIsInsertedWithText:(NSString *)messageText block:(void(^)(ZMMessage *message))block
{
    // given
    __block ZMConversation *conversation;
    __block ZMClientMessage *message;
    
    [self.syncMOC performGroupedBlock:^{
        conversation = self.insertGroupConversation;
        message = [conversation appendOTRMessageWithText:messageText nonce:[NSUUID createUUID]];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    XCTAssertNotNil(message);
    XCTAssertNotNil(conversation);
    
    __block UserClient *selfClient;
    
    [self.syncMOC performGroupedBlock:^{
        conversation = [ZMConversation fetchObjectWithRemoteIdentifier:conversation.remoteIdentifier inManagedObjectContext:self.syncMOC];
        selfClient = self.createSelfClient;
        
        //other user client
        EncryptionContext *otherClientsBox = [[EncryptionContext alloc] initWithPath:[UserClientKeysStore otrDirectory]];
        [conversation.otherActiveParticipants enumerateObjectsUsingBlock:^(ZMUser *user, NSUInteger __unused idx, BOOL *__unused stop) {
            UserClient *userClient = [UserClient insertNewObjectInManagedObjectContext:self.syncMOC];
            userClient.remoteIdentifier = [NSString createAlphanumericalString];
            userClient.user = user;
            
            __block NSError *keyError;
            [otherClientsBox perform:^(EncryptionSessionsDirectory * _Nonnull sessionsDirectory) {
                NSString *key = [sessionsDirectory generatePrekey:1 error:&keyError];
                [sessionsDirectory createClientSession:userClient.remoteIdentifier base64PreKeyString:key error:&keyError];
            }];
        }];
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertNotNil(selfClient);
    
    // when
    block(message);
    
    __block ZMTransportRequest *request;
    [self.syncMOC performGroupedBlock:^{
        request = [self.sut.requestGenerators nextRequest];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then we expect a POST request to /conversations/{cnv}/otr/messages
    NSArray *pathComponents = @[@"/", @"conversations", conversation.remoteIdentifier.transportString, @"otr", @"messages"];
    NSString *expectedPath = [NSString pathWithComponents:pathComponents];
    XCTAssertNotNil(request);
    XCTAssertEqualObjects(expectedPath, request.path);
    
    ZMClientMessage *syncMessage = (ZMClientMessage *)[self.sut.managedObjectContext objectWithID:message.objectID];
    ZMNewOtrMessage *expectedOtrMessageMetadata = (ZMNewOtrMessage *)[ZMNewOtrMessage.builder mergeFromData:syncMessage.encryptedMessagePayloadDataOnly].build;
    ZMNewOtrMessage *otrMessageMetadata = (ZMNewOtrMessage *)[ZMNewOtrMessage.builder mergeFromData:request.binaryData].build;
    [self assertNewOtrMessageMetadata:otrMessageMetadata expected:expectedOtrMessageMetadata conversation:conversation];
}

- (void)assertNewOtrMessageMetadata:(ZMNewOtrMessage *)otrMessageMetadata expected:(ZMNewOtrMessage *)expectedOtrMessageMetadata conversation:(ZMConversation *)conversation
{
    NSArray *userIds = [otrMessageMetadata.recipients mapWithBlock:^id(ZMUserEntry *entry) {
        return [[NSUUID alloc] initWithUUIDBytes:entry.user.uuid.bytes];
    }];
    
    NSArray *expectedUserIds = [expectedOtrMessageMetadata.recipients mapWithBlock:^id(ZMUserEntry *entry) {
        return [[NSUUID alloc] initWithUUIDBytes:entry.user.uuid.bytes];
    }];
    
    AssertArraysContainsSameObjects(userIds, expectedUserIds);
    
    NSArray *recipientsIds = [otrMessageMetadata.recipients flattenWithBlock:^NSArray *(ZMUserEntry *entry) {
        return [entry.clients mapWithBlock:^NSNumber *(ZMClientEntry *clientEntry) {
            return @(clientEntry.client.client);
        }];
    }];
    
    NSArray *expectedRecipientsIds = [expectedOtrMessageMetadata.recipients flattenWithBlock:^NSArray *(ZMUserEntry *entry) {
        return [entry.clients mapWithBlock:^NSNumber *(ZMClientEntry *clientEntry) {
            return @(clientEntry.client.client);
        }];
    }];
    
    AssertArraysContainsSameObjects(recipientsIds, expectedRecipientsIds);
    
    NSArray *conversationUserIds = [conversation.otherActiveParticipants.array mapWithBlock:^id(ZMUser *obj) {
        return [obj remoteIdentifier];
    }];
    AssertArraysContainsSameObjects(userIds, conversationUserIds);
    
    NSArray *conversationRecipientsIds = [conversation.otherActiveParticipants.array flattenWithBlock:^NSArray *(ZMUser *obj) {
        return [obj.clients.allObjects mapWithBlock:^NSString *(UserClient *client) {
            return client.remoteIdentifier;
        }];
    }];
    
    NSArray *stringRecipientsIds = [recipientsIds mapWithBlock:^NSString *(NSNumber *obj) {
        return [NSString stringWithFormat:@"%lx", (unsigned long)[obj unsignedIntegerValue]];
    }];
    
    AssertArraysContainsSameObjects(stringRecipientsIds, conversationRecipientsIds);
    
    XCTAssertEqual(otrMessageMetadata.nativePush, expectedOtrMessageMetadata.nativePush);
}

- (void)assertOtrAssetMetadata:(ZMOtrAssetMeta *)otrAssetMetadata expected:(ZMOtrAssetMeta *)expectedOtrAssetMetadata conversation:(ZMConversation *)conversation
{
    [self assertNewOtrMessageMetadata:(ZMNewOtrMessage *)otrAssetMetadata expected:(ZMNewOtrMessage *)expectedOtrAssetMetadata conversation:conversation];
    
    XCTAssertEqual(otrAssetMetadata.isInline, expectedOtrAssetMetadata.isInline);
}

- (void)testThatItGeneratesARequestToSendAMessageWhenAGenericMessageIsInserted_OnInitialization
{
    [self testThatItGeneratesARequestToSendAClientMessageWhenAMessageIsInsertedWithBlock:^(ZMMessage *message) {
        NOT_USED(message);
        [ZMChangeTrackerBootstrap bootStrapChangeTrackers:self.sut.contextChangeTrackers onContext:self.syncMOC];
    }];
}

- (void)testThatItGeneratesARequestToSendAMessageWhenAGenericMessageIsInserted_OnObjectsDidChange
{
    [self testThatItGeneratesARequestToSendAClientMessageWhenAMessageIsInsertedWithBlock:^(ZMMessage *message) {
        NOT_USED(message);
        [self.sut.contextChangeTrackers[0] objectsDidChange:[NSSet setWithObject:message]];
    }];
}

- (void)testThatItGeneratesARequestToSendAMessageWhenOTRMessageIsInserted_OnInitialization
{
    [self checkThatItGeneratesARequestToSendOTRMessageWhenAMessageIsInsertedWithBlock:^(ZMMessage *message) {
        NOT_USED(message);
        [ZMChangeTrackerBootstrap bootStrapChangeTrackers:self.sut.contextChangeTrackers onContext:self.syncMOC];
    }];
}

- (void)testThatItGeneratesARequestToSendAMessageWhenOTRMessageIsInserted_OnObjectsDidChange
{
    [self checkThatItGeneratesARequestToSendOTRMessageWhenAMessageIsInsertedWithBlock:^(ZMMessage *message) {
        NSManagedObject *syncMessage = [self.sut.managedObjectContext objectWithID:message.objectID];
        for(id changeTracker in self.sut.contextChangeTrackers) {
            [changeTracker objectsDidChange:[NSSet setWithObject:syncMessage]];
        }
    }];
}

- (ZMAssetClientMessage *)bootstrapAndCreateOTRAssetMessageInConversationWithId:(NSUUID *)conversationId
{
    ZMConversation *conversation = [self insertGroupConversationInMoc:self.syncMOC];
    conversation.remoteIdentifier = conversationId;
    return [self bootstrapAndCreateOTRAssetMessageInConversation:conversation];
}


- (ZMAssetClientMessage *)bootstrapAndCreateOTRAssetMessageInConversation:(ZMConversation *)conversation
{
    // given
    NSData *imageData = [self verySmallJPEGData];
    ZMAssetClientMessage *message = [self createImageMessageWithImageData:imageData format:ZMImageFormatMedium processed:YES stored:NO encrypted:YES moc:self.syncMOC];
    [conversation.mutableMessages addObject:message];
    XCTAssertTrue([self.syncMOC saveOrRollback]);
    
    //self client
    [self createSelfClient];
    
    //other user client
    [conversation.otherActiveParticipants enumerateObjectsUsingBlock:^(ZMUser *user, NSUInteger __unused idx, BOOL *__unused stop) {
        [self createClientForUser:user createSessionWithSelfUser:YES];
    }];
    
    XCTAssertTrue([self.syncMOC saveOrRollback]);
    return message;
}

- (void)prepareMessage:(ZMAssetClientMessage *)message forUploadOnlyForFormat:(ZMImageFormat)format {
    
    // this will cause the message to be "ready to upload", but just for the given format
    ZMImageFormat otherFormat = (format == ZMImageFormatMedium) ? ZMImageFormatPreview : ZMImageFormatMedium;
    [message.imageAssetStorage setImageData:message.imageAssetStorage.originalImageData forFormat:format properties:[ZMIImageProperties imagePropertiesWithSize:message.imageAssetStorage.originalImageSize length:1000 mimeType:@"image/jpg"]];
    [message.imageAssetStorage setImageData:message.imageAssetStorage.originalImageData forFormat:otherFormat properties:[ZMIImageProperties imagePropertiesWithSize:message.imageAssetStorage.originalImageSize length:1000 mimeType:@"image/jpg"]];
    
    message.uploadState = format == ZMImageFormatMedium ? ZMAssetUploadStateUploadingFullAsset : ZMAssetUploadStateUploadingPlaceholder;
    [self.syncMOC saveOrRollback];
}

- (void)testThatItGeneratesARequestToSendOTRAssetWhenAMessageIsInsertedWithFormat:(ZMImageFormat)format block:(void(^)(ZMMessage *message))block
{
    [self.syncMOC performGroupedBlock:^{
        
        NSUUID *conversationId = [NSUUID createUUID];
        ZMAssetClientMessage *message = [self bootstrapAndCreateOTRAssetMessageInConversationWithId:conversationId];
        [self prepareMessage:message forUploadOnlyForFormat:format];
        
        // when
        block(message);
        ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
        
        // then
        //POST /conversations/{cnv}/otr/assets
        NSString *expectedPath = [NSString pathWithComponents:@[@"/", @"conversations", conversationId.transportString, @"otr", @"assets"]];
        XCTAssertNotNil(request);
        if(!request) {
            return;
        }
        XCTAssertEqualObjects(expectedPath, request.path);
        ZMMultipartBodyItem *metadataItem = [request multipartBodyItems].firstObject;
        
        ZMAssetClientMessage *syncMessage = (ZMAssetClientMessage *)[self.sut.managedObjectContext objectWithID:message.objectID];
        
        NSData *syncMessageData = [[syncMessage encryptedMessagePayloadForImageFormat:format] data];
        ZMOtrAssetMeta *expectedOtrMessageMetadata = (ZMOtrAssetMeta *)[[[ZMOtrAssetMeta builder] mergeFromData:syncMessageData] build];
        ZMOtrAssetMeta *otrMessageMetadata = (ZMOtrAssetMeta *)[[[ZMOtrAssetMeta builder] mergeFromData:metadataItem.data] build];
        
        [self assertOtrAssetMetadata:otrMessageMetadata expected:expectedOtrMessageMetadata conversation:message.conversation];
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItGeneratesARequestToSendAssetWhenOTRAssetIsInserted_OnInitialization
{
    [self testThatItGeneratesARequestToSendOTRAssetWhenAMessageIsInsertedWithFormat:ZMImageFormatMedium block:^(ZMMessage *message) {
        NOT_USED(message);
        [ZMChangeTrackerBootstrap bootStrapChangeTrackers:self.sut.contextChangeTrackers onContext:self.syncMOC];
    }];
}

- (void)testThatItGeneratesARequestToSendAssetWhenOTRAssetIsInserted_OnObjectsDidChange
{
    [self testThatItGeneratesARequestToSendOTRAssetWhenAMessageIsInsertedWithFormat:ZMImageFormatMedium block:^(ZMMessage *message) {
        NSManagedObject *syncMessage = [self.sut.managedObjectContext objectWithID:message.objectID];
        for(id changeTracker in self.sut.contextChangeTrackers) {
            [changeTracker objectsDidChange:[NSSet setWithObject:syncMessage]];
        }
    }];
}

- (ZMTransportRequest *)requestToDownloadAssetWithAssetId:(NSUUID *)assetId inConversationWithId:(NSUUID *)conversationId
{
    // given
    NSData *imageData = [self verySmallJPEGData];
    NSUUID *nonce = [NSUUID createUUID];
    
    __block ZMAssetClientMessage *message;
    
    [self.syncMOC performGroupedBlockAndWait:^{
        // message
        message = [ZMAssetClientMessage assetClientMessageWithOriginalImageData:imageData
                                                                                                nonce:nonce
                                                                                 managedObjectContext:self.syncMOC];
        message.isEncrypted = YES;
        
        // remove image data or it won't be downloaded
        [self.syncMOC.zm_imageAssetCache deleteAssetData:message.nonce format:ZMImageFormatOriginal encrypted:NO];
        
        ZMIImageProperties *properties = [ZMIImageProperties imagePropertiesWithSize:[ZMImagePreprocessor sizeOfPrerotatedImageWithData:imageData] length:imageData.length mimeType:@"image/jpeg"];
        ZMImageAssetEncryptionKeys *keys = [[ZMImageAssetEncryptionKeys alloc] initWithOtrKey:[NSData randomEncryptionKey] macKey:[NSData zmRandomSHA256Key] mac:[NSData zmRandomSHA256Key]];
        [message addGenericMessage:[ZMGenericMessage messageWithMediumImageProperties:properties processedImageProperties:properties encryptionKeys:keys nonce:nonce.transportString format:ZMImageFormatMedium]];
        [message addGenericMessage:[ZMGenericMessage messageWithMediumImageProperties:properties processedImageProperties:properties encryptionKeys:keys nonce:nonce.transportString format:ZMImageFormatPreview]];
        [message resetLocallyModifiedKeys:[NSSet setWithObject:ZMAssetClientMessageUploadedStateKey]];
        message.assetId = assetId;
        
        // Conversation
        ZMConversation *conversation = [self insertGroupConversationInMoc:self.syncMOC];
        conversation.remoteIdentifier = conversationId;
        [conversation.mutableMessages addObject:message];
        XCTAssertTrue([self.syncMOC saveOrRollback]);

        // trigger download
        [message requestImageDownload];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    // request
    __block ZMTransportRequest *request;
    [self.syncMOC performGroupedBlockAndWait:^{
        request = [self.sut.requestGenerators nextRequest];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    return request;
}

- (void)testThatItReturnsRequestToDownloadAssetIfHasAssetId
{
    // given
    NSUUID *conversationId = [NSUUID createUUID];
    NSUUID *assetId = [NSUUID createUUID];
    
    // when
    ZMTransportRequest *request = [self requestToDownloadAssetWithAssetId:assetId inConversationWithId:conversationId];
    WaitForAllGroupsToBeEmpty(0.5);
    
    NSString *expectedPath = [NSString pathWithComponents:@[@"/", @"conversations", conversationId.transportString, @"otr", @"assets", assetId.transportString]];
    
    // then
    XCTAssertNotNil(request);
    XCTAssertEqualObjects(request.path, expectedPath);
}

- (void)testThatItDoesNotReturnsRequestToDownloadFileAsset
{
    [self.syncMOC performGroupedBlock:^{
        // given
        NSUUID *nonce = [NSUUID createUUID];
        NSURL *testURL = [[NSBundle bundleForClass:self.class] URLForResource:@"Lorem Ipsum" withExtension:@"txt"];
        ZMFileMetadata *metadata = [[ZMFileMetadata alloc] initWithFileURL:testURL thumbnail:nil];
        ZMAssetClientMessage *message = [ZMAssetClientMessage assetClientMessageWithFileMetadata:metadata
                                                                                           nonce:nonce
                                                                            managedObjectContext:self.syncMOC];
        message.transferState = ZMFileTransferStateUploaded;
        message.delivered = YES;
        message.assetId = [NSUUID createUUID];
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.remoteIdentifier = [NSUUID createUUID];
        conversation.conversationType = ZMConversationTypeGroup;
        
        // when
        for(id changeTracker in self.sut.contextChangeTrackers) {
            [changeTracker objectsDidChange:[NSSet setWithObject:message]];
        }
        
        ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
        
        // then
        XCTAssertNil(request);
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItDoesNotReturnRequestToDownloadAssetIfItHasNoAssetId
{
    ZMTransportRequest *request = [self requestToDownloadAssetWithAssetId:nil inConversationWithId:[NSUUID createUUID]];
    XCTAssertNil(request);
}

- (void)testThatItUpdatesMessageWithImageData
{
    [self.syncMOC performGroupedBlock:^{
        // given
        NSData *imageData = [self verySmallJPEGData];
        ZMAssetClientMessage *message = [ZMAssetClientMessage insertNewObjectInManagedObjectContext:self.syncMOC];
        id mockMessage = [OCMockObject partialMockForObject:message];
        
        ZMTransportResponse *response = [OCMockObject mockForClass:ZMTransportResponse.class];
        [[[(id)response stub] andReturn:imageData] rawData];
        [[[(id)response stub] andReturnValue:@(200)] HTTPStatus];
        
        //expect
        [[mockMessage expect] updateMessageWithImageData:imageData forFormat:ZMImageFormatMedium];
        
        // when
        [(ZMClientMessageTranscoder *)self.sut updateObject:message withResponse:response downstreamSync:nil];
        
        //then
        [mockMessage verify];
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItDeletesMessageIfDownstreamRequestFailed
{
    [self.syncMOC performGroupedBlock:^{
        // given
        ZMAssetClientMessage *message = [ZMAssetClientMessage assetClientMessageWithOriginalImageData:[NSData data]
                                                                                                nonce:[NSUUID createUUID]
                                                                                 managedObjectContext:self.syncMOC];
        
        // when
        [(ZMClientMessageTranscoder *)self.sut deleteObject:message downstreamSync:nil];
        
        // then
        XCTAssertTrue(message.isDeleted);
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItAddsMissingRecipientInMessageRelationship
{
    [self.syncMOC performGroupedBlock:^{
        // given
        ZMAssetClientMessage *message = [self bootstrapAndCreateOTRAssetMessageInConversationWithId:[NSUUID createUUID]];
        
        NSString *missingClientId = [NSString createAlphanumericalString];
        NSDictionary *payload = @{@"missing": @{[NSUUID createUUID].transportString : @[missingClientId]}};
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPstatus:412 transportSessionError:nil];
        ZMUpstreamRequest *request = [[ZMUpstreamRequest alloc] initWithTransportRequest:[ZMTransportRequest requestGetFromPath:@"foo"]];
        
        // when
        [self.sut shouldRetryToSyncAfterFailedToUpdateObject:message request:request response:response keysToParse:[NSSet set]];
        
        // then
        UserClient *missingClient = message.missingRecipients.anyObject;
        XCTAssertNotNil(missingClient);
        XCTAssertEqualObjects(missingClient.remoteIdentifier, missingClientId);
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItDeletesTheCurrentClientIfWeGetA403ResponseWithCorrectLabel
{
    [self.syncMOC performGroupedBlock:^{

        // given
        ZMAssetClientMessage *message = [self bootstrapAndCreateOTRAssetMessageInConversationWithId:[NSUUID createUUID]];
        id <ZMTransportData> payload = @{ @"label": @"unknown-client" };
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPstatus:403 transportSessionError:nil];
        ZMUpstreamRequest *request = [[ZMUpstreamRequest alloc] initWithTransportRequest:[ZMTransportRequest requestGetFromPath:@"foo"]];
        
        // expect
        [[(id)self.mockClientRegistrationStatus expect] didDetectCurrentClientDeletion];
        
        // when
        [self.sut shouldRetryToSyncAfterFailedToUpdateObject:message request:request response:response keysToParse:[NSSet set]];
        
        // then
        [(id)self.mockClientRegistrationStatus verify];
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItDoesNotDeletesTheCurrentClientIfWeGetA403ResponseWithoutTheCorrectLabel
    {
        [self.syncMOC performGroupedBlock:^{
            
            // given
            ZMAssetClientMessage *message = [self bootstrapAndCreateOTRAssetMessageInConversationWithId:[NSUUID createUUID]];
            ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:@[] HTTPstatus:403 transportSessionError:nil];
            ZMUpstreamRequest *request = [[ZMUpstreamRequest alloc] initWithTransportRequest:[ZMTransportRequest requestGetFromPath:@"foo"]];
            
            // reject
            [[(id)self.mockClientRegistrationStatus reject] didDetectCurrentClientDeletion];
            
            // when
            [self.sut shouldRetryToSyncAfterFailedToUpdateObject:message request:request response:response keysToParse:[NSSet set]];
            
            // then
            [(id)self.mockClientRegistrationStatus verify];
        }];
        
        WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItSetsNeedsToBeUpdatedFromBackendOnConversationIfMissingMapIncludesUsersThatAreNoActiveUsers
{
    [self.syncMOC performGroupedBlock:^{
        
        // given
        ZMAssetClientMessage *message = [self bootstrapAndCreateOTRAssetMessageInConversationWithId:[NSUUID createUUID]];
        XCTAssertFalse(message.conversation.needsToBeUpdatedFromBackend);
        
        NSString *missingClientId = [NSString createAlphanumericalString];
        NSDictionary *payload = @{@"missing": @{[NSUUID createUUID].transportString : @[missingClientId]}};
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPstatus:412 transportSessionError:nil];
        ZMUpstreamRequest *request = [[ZMUpstreamRequest alloc] initWithTransportRequest:[ZMTransportRequest requestGetFromPath:@"foo"]];
        
        // when
        [self.sut shouldRetryToSyncAfterFailedToUpdateObject:message request:request response:response keysToParse:[NSSet set]];
        
        // then
        XCTAssertTrue(message.conversation.needsToBeUpdatedFromBackend);
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItSetsNeedsToBeUpdatedFromBackendOnConnectionIfMissingMapIncludesUsersThatIsNoActiveUser_OneOnOne
{
    [self.syncMOC performGroupedBlock:^{
        // given
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.conversationType = ZMConversationTypeOneOnOne;
        conversation.remoteIdentifier = [NSUUID UUID];
        conversation.connection = [ZMConnection insertNewObjectInManagedObjectContext:self.syncMOC];
        ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user.remoteIdentifier = [NSUUID UUID];
        
        ZMAssetClientMessage *message = [self bootstrapAndCreateOTRAssetMessageInConversation:conversation];
        XCTAssertFalse(message.conversation.connection.needsToBeUpdatedFromBackend);
        
        NSString *missingClientId = [NSString createAlphanumericalString];
        NSDictionary *payload = @{@"missing": @{user.remoteIdentifier.transportString : @[missingClientId]}};
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPstatus:412 transportSessionError:nil];
        ZMUpstreamRequest *request = [[ZMUpstreamRequest alloc] initWithTransportRequest:[ZMTransportRequest requestGetFromPath:@"foo"]];
        
        
        // when
        [self.sut shouldRetryToSyncAfterFailedToUpdateObject:message request:request response:response keysToParse:[NSSet set]];
        [self.syncMOC saveOrRollback];
        
        // then
        XCTAssertNotNil(user.connection);
        XCTAssertNotNil(message.conversation.connection);
        XCTAssertTrue(message.conversation.connection.needsToBeUpdatedFromBackend);
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItInsertsAndSetsNeedsToBeUpdatedFromBackendOnConnectionIfMissingMapIncludesUsersThatIsNoActiveUser_OneOnOne
{
    [self.syncMOC performGroupedBlock:^{
        // given
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.conversationType = ZMConversationTypeOneOnOne;
        conversation.remoteIdentifier = [NSUUID UUID];
        
        ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user.remoteIdentifier = [NSUUID UUID];
        
        ZMAssetClientMessage *message = [self bootstrapAndCreateOTRAssetMessageInConversation:conversation];
        XCTAssertFalse(message.conversation.needsToBeUpdatedFromBackend);
        
        NSString *missingClientId = [NSString createAlphanumericalString];
        NSDictionary *payload = @{@"missing": @{user.remoteIdentifier.transportString : @[missingClientId]}};
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPstatus:412 transportSessionError:nil];
        ZMUpstreamRequest *request = [[ZMUpstreamRequest alloc] initWithTransportRequest:[ZMTransportRequest requestGetFromPath:@"foo"]];
        
        // when
        [self.sut shouldRetryToSyncAfterFailedToUpdateObject:message request:request response:response keysToParse:[NSSet set]];
        [self.syncMOC saveOrRollback];
        
        // then
        XCTAssertNotNil(user.connection);
        XCTAssertNotNil(message.conversation.connection);
        XCTAssertTrue(message.conversation.connection.needsToBeUpdatedFromBackend);
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
}
    
- (void)testThatItDeletesDeletedRecipientsOnFailure
{
    // given
    [self.syncMOC performGroupedBlock:^{
        UserClient *client = [UserClient insertNewObjectInManagedObjectContext:self.syncMOC];
        client.remoteIdentifier = @"whoopy";
        client.user = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        ZMAssetClientMessage *message = [self bootstrapAndCreateOTRAssetMessageInConversation:conversation];
        
        ZMUser *user = client.user;
        user.remoteIdentifier = [NSUUID createUUID];
        
        NSDictionary *payload = @{@"deleted": @{user.remoteIdentifier.transportString : @[client.remoteIdentifier]}};
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPstatus:412 transportSessionError:nil];
        ZMUpstreamRequest *request = [[ZMUpstreamRequest alloc] initWithTransportRequest:[ZMTransportRequest requestGetFromPath:@"foo"]];

        // when
        [self.sut shouldRetryToSyncAfterFailedToUpdateObject:message request:request response:response keysToParse:[NSSet set]];
        [self.syncMOC saveOrRollback];
        
        // then
        XCTAssertTrue(client.isZombieObject);
        XCTAssertEqual(user.clients.count, 0u);
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItDeletesDeletedRecipientsOnSuccessInsertion
{
    [self.syncMOC performGroupedBlock:^{
        
        // given
        UserClient *client = [UserClient insertNewObjectInManagedObjectContext:self.syncMOC];
        client.remoteIdentifier = @"whoopy";
        client.user = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        ZMAssetClientMessage *message = [self bootstrapAndCreateOTRAssetMessageInConversation:conversation];
        
        ZMUser *user = client.user;
        user.remoteIdentifier = [NSUUID createUUID];
        
        NSDictionary *payload = @{@"deleted": @{user.remoteIdentifier.transportString : @[client.remoteIdentifier]}};
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPstatus:200 transportSessionError:nil];
        ZMUpstreamRequest *request = [[ZMUpstreamRequest alloc] initWithTransportRequest:[ZMTransportRequest requestGetFromPath:@"foo"]];

        // when
        [self.sut updateInsertedObject:message request:request response:response];
        [self.syncMOC saveOrRollback];
        
        // then
        XCTAssertTrue(client.isZombieObject);
        XCTAssertEqual(user.clients.count, 0u);
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItDeletesDeletedRecipientsOnSuccessUpdate
{
    [self.syncMOC performGroupedBlock:^{
        
        // given
        ZMClientMessage *message = [ZMClientMessage insertNewObjectInManagedObjectContext:self.syncMOC];
        message.visibleInConversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        UserClient *client = [UserClient insertNewObjectInManagedObjectContext:self.syncMOC];
        client.remoteIdentifier = @"whoopy";
        client.user = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        
        ZMUser *user = client.user;
        user.remoteIdentifier = [NSUUID createUUID];
        
        [self.syncMOC saveOrRollback];
        
        NSDictionary *payload = @{
                                  @"time" : [NSDate date].transportString,
                                  @"deleted": @{user.remoteIdentifier.transportString : @[client.remoteIdentifier]}
                                  };
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPstatus:200 transportSessionError:nil];

        // when
        [self.sut updateUpdatedObject:message requestUserInfo:[NSDictionary dictionary] response:response keysToParse:[NSSet set]];
        [self.syncMOC saveOrRollback];
        
        // then
        XCTAssertTrue(client.isZombieObject);
        XCTAssertEqual(user.clients.count, 0u);
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
}


- (void)checkThatItDeletesMessageIfFailedToCreatedUpdateRequestAndNoOriginalDataStored:(ZMImageFormat)format
{
    [self.syncMOC performGroupedBlock:^{
        
        NSData *imageData = [self verySmallJPEGData];
        NSUUID *nonce = [NSUUID createUUID];
        ZMAssetClientMessage *message = [ZMAssetClientMessage assetClientMessageWithOriginalImageData:imageData nonce:nonce managedObjectContext:self.syncMOC];
        ZMIImageProperties *properties = [ZMIImageProperties imagePropertiesWithSize:[ZMImagePreprocessor sizeOfPrerotatedImageWithData:imageData] length:imageData.length mimeType:@""];
        [message addGenericMessage:[ZMGenericMessage messageWithMediumImageProperties:properties processedImageProperties:properties encryptionKeys:nil nonce:nonce.transportString format:format]];
        
        //when
        switch (format) {
            case ZMImageFormatPreview:
                message.uploadState = ZMAssetUploadStateUploadingPlaceholder;
                break;
            case ZMImageFormatMedium:
                message.uploadState = ZMAssetUploadStateUploadingFullAsset;
                break;
            default:
                break;
        }
        [self.sut requestForUpdatingObject:message forKeys:[NSSet setWithObject:ZMAssetClientMessageUploadedStateKey]];
        
        //then
        XCTAssertTrue(message.isZombieObject);
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItDeletesMessageIfFailedToCreatedUpdateRequestForMediumFormatAndNoOriginalDataStored
{
    [self checkThatItDeletesMessageIfFailedToCreatedUpdateRequestAndNoOriginalDataStored:ZMImageFormatMedium];
}

- (void)testThatItDeletesMessageIfFailedToCreatedUpdateRequestForPreviewFormatAndNoOriginalDataStored
{
    [self checkThatItDeletesMessageIfFailedToCreatedUpdateRequestAndNoOriginalDataStored:ZMImageFormatPreview];
}

- (void)testThatItChecksIfItNeedsProcessingBeforeCreatingRequest
{
    [self.syncMOC performGroupedBlock:^{
        
        NSUUID *conversationId = [NSUUID createUUID];
        ZMAssetClientMessage *message = [self bootstrapAndCreateOTRAssetMessageInConversationWithId:conversationId];
        [self prepareMessage:message forUploadOnlyForFormat:ZMImageFormatMedium];
        
        NSManagedObject *syncMessage = [self.sut.managedObjectContext objectWithID:message.objectID];
        for(id changeTracker in self.sut.contextChangeTrackers) {
            [changeTracker objectsDidChange:[NSSet setWithObject:syncMessage]];
        }
        
        // when
        [message.managedObjectContext.zm_imageAssetCache deleteAssetData:message.nonce format:ZMImageFormatMedium encrypted:YES];
        ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
        
        // then
        XCTAssertNil(request);
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItResetsNeedsToUploadMediumKeyWhenParsingTheResponseForPreviewImage
{
    [self.syncMOC performGroupedBlock:^{

        // given
        NSString *key = ZMAssetClientMessageUploadedStateKey;
        ZMAssetClientMessage *message = [ZMAssetClientMessage assetClientMessageWithOriginalImageData:[self verySmallJPEGData]
                                                                                                nonce:[NSUUID createUUID]
                                                                                 managedObjectContext:self.syncMOC];
        message.uploadState = ZMAssetUploadStateUploadingPlaceholder;
        XCTAssertTrue([message hasLocalModificationsForKey:key]);
        
        NSDictionary *responsePayload = @{@"time" : [NSDate date].transportString};
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:responsePayload HTTPstatus:200 transportSessionError:nil];
        
        // when
        [self.sut updateUpdatedObject:message requestUserInfo:nil response:response keysToParse:[NSSet setWithObject:key]];
        
        // then
        XCTAssertTrue([message hasLocalModificationsForKey:key]);
        XCTAssertEqual(message.uploadState, ZMAssetUploadStateUploadingFullAsset);
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItDoesNotSetTheAssetIdWhenParsingTheResponseForPreviewImage
{
    [self.syncMOC performGroupedBlock:^{
        
        // given
        ZMAssetClientMessage *message = [ZMAssetClientMessage assetClientMessageWithOriginalImageData:[self verySmallJPEGData]
                                                                                                nonce:[NSUUID createUUID]
                                                                                 managedObjectContext:self.syncMOC];
        NSDictionary *responsePayload = @{@"time" : [NSDate date].transportString};
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:responsePayload HTTPstatus:200 transportSessionError:nil];
        
        // when
        [self.sut updateUpdatedObject:message requestUserInfo:nil response:response keysToParse:[NSSet setWithObject:ZMAssetClientMessageUploadedStateKey]];
        
        // then
        XCTAssertNil(message.assetId);
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
}


- (void)testThatItResetsNeedsToUploadMediumKeyWhenParsingTheResponseForMediumImage
{
    [self.syncMOC performGroupedBlock:^{
        
        // given
        NSString *key = ZMAssetClientMessageUploadedStateKey;
        ZMAssetClientMessage *message = [ZMAssetClientMessage assetClientMessageWithOriginalImageData:[self verySmallJPEGData]
                                                                                                nonce:[NSUUID createUUID]
                                                                                 managedObjectContext:self.syncMOC];
        message.uploadState = ZMAssetUploadStateUploadingFullAsset;
        XCTAssertTrue([message hasLocalModificationsForKey:key]);
        XCTAssertEqual(message.uploadState, ZMAssetUploadStateUploadingFullAsset);
        
        NSDictionary *responsePayload = @{@"time" : [NSDate date].transportString};
        NSUUID *assetID = [NSUUID createUUID];
        
        NSDictionary *responseHeader = @{@"Location" : assetID.transportString};
        ZMTransportResponse *response = [[ZMTransportResponse alloc] initWithPayload:responsePayload HTTPstatus:200 transportSessionError:nil headers:responseHeader];
        
        // when
        [self.sut updateUpdatedObject:message requestUserInfo:nil response:response keysToParse:[NSSet setWithObject:key]];
        
        // then
        XCTAssertFalse([message hasLocalModificationsForKey:key]);
        XCTAssertEqual(message.uploadState, ZMAssetUploadStateDone);
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItSetsTheAssetIdWhenParsingTheResponseForMediumImage
{
    [self.syncMOC performGroupedBlock:^{
        
        // given
        ZMAssetClientMessage *message = [ZMAssetClientMessage assetClientMessageWithOriginalImageData:[self verySmallJPEGData]
                                                                                                nonce:[NSUUID createUUID]
                                                                                 managedObjectContext:self.syncMOC];
        message.uploadState = ZMAssetUploadStateUploadingFullAsset;
        NSDictionary *responsePayload = @{@"time" : [NSDate date].transportString};
        NSUUID *assetID = [NSUUID createUUID];
        
        NSDictionary *responseHeader = @{@"Location" : assetID.transportString};
        ZMTransportResponse *response = [[ZMTransportResponse alloc] initWithPayload:responsePayload HTTPstatus:200 transportSessionError:nil headers:responseHeader];
        
        // when
        [self.sut updateUpdatedObject:message requestUserInfo:nil response:response keysToParse:[NSSet setWithObject:ZMAssetClientMessageUploadedStateKey]];
        
        // then
        XCTAssertEqualObjects(message.assetId, assetID);
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItResetsKeysWhenRequestFails_ClientDeleted
{
    [self.syncMOC performGroupedBlock:^{
        
        // given
        NSSet *keys = [NSSet setWithObject:ZMAssetClientMessageUploadedStateKey];
        
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        ZMAssetClientMessage *message = [conversation appendOTRMessageWithImageData:[self verySmallJPEGData] nonce:[NSUUID createUUID]];
        
        [message setLocallyModifiedKeys:keys];
        XCTAssertTrue([message hasLocalModificationsForKeys:keys]);
        ZMUpstreamRequest *request = [[ZMUpstreamRequest alloc] initWithTransportRequest:[ZMTransportRequest requestGetFromPath:@"foo"]];
        
        // when
        [[(id)self.mockClientRegistrationStatus stub] didDetectCurrentClientDeletion];
        
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:@{@"label": @"unknown-client"} HTTPstatus:403 transportSessionError:nil];
        [self.sut shouldRetryToSyncAfterFailedToUpdateObject:message request:request response:response keysToParse:keys];
        
        // then
        XCTAssertEqual(message.uploadState, ZMAssetUploadStateUploadingFailed);
        XCTAssertTrue([message hasLocalModificationsForKeys:keys]);
        XCTAssertFalse(message.conversation.needsToBeUpdatedFromBackend);
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
}

@end


@implementation ZMClientMessageTranscoderTests (ClientsTrust)

- (NSArray *)createGroupConversationUsersWithClients
{
    self.selfUser = [ZMUser selfUserInContext:self.syncMOC];
    
    ZMUser *user1 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
    UserClient *userClient1 = [UserClient insertNewObjectInManagedObjectContext:self.syncMOC];
    ZMConnection *firstConnection = [ZMConnection insertNewSentConnectionToUser:user1];
    firstConnection.status = ZMConnectionStatusAccepted;
    userClient1.user = user1;
    
    ZMUser *user2 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
    UserClient *userClient2 = [UserClient insertNewObjectInManagedObjectContext:self.syncMOC];
    ZMConnection *secondConnection = [ZMConnection insertNewSentConnectionToUser:user2];
    secondConnection.status = ZMConnectionStatusAccepted;
    userClient2.user = user2;
    
    return @[user1, user2];
}

- (ZMMessage *)createMessageInGroupConversationWithUsers:(NSArray *)users encrypted:(BOOL)encrypted
{
    ZMClientMessage *message = [ZMClientMessage insertNewObjectInManagedObjectContext:self.syncMOC];
    message.isEncrypted = encrypted;
    
    ZMConversation *conversation = [ZMConversation insertGroupConversationIntoManagedObjectContext:self.syncMOC withParticipants:users];
    [conversation.mutableMessages addObject:message];
    return message;
}


@end



@implementation ZMClientMessageTranscoderTests (ZMLastRead)

- (void)testThatItPicksUpLastReadUpdateMessages
{
    // given
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMUser *selfUser = [ZMUser selfUserInContext:self.syncMOC];
        selfUser.remoteIdentifier = [NSUUID createUUID];
        ZMConversation *selfConversation = [ZMConversation conversationWithRemoteID:selfUser.remoteIdentifier createIfNeeded:YES inContext:self.syncMOC];
        selfConversation.conversationType = ZMConversationTypeSelf;
        
        NSDate *lastRead = [NSDate date];
        ZMConversation *updatedConversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        updatedConversation.remoteIdentifier = [NSUUID createUUID];
        updatedConversation.lastReadServerTimeStamp = lastRead;
        
        ZMClientMessage *lastReadUpdateMessage = [ZMConversation appendSelfConversationWithLastReadOfConversation:updatedConversation];
        XCTAssertNotNil(lastReadUpdateMessage);

        // when
        for (id tracker in self.sut.contextChangeTrackers) {
            [tracker objectsDidChange:[NSSet setWithObject:lastReadUpdateMessage]];
        }
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMTransportRequest *request = [self.sut.requestGenerators.firstObject nextRequest];
        
        // then
        XCTAssertNotNil(request);
    }];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItCreatesARequestForLastReadUpdateMessages
{
    // given
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMUser *selfUser = [ZMUser selfUserInContext:self.syncMOC];
        selfUser.remoteIdentifier = [NSUUID createUUID];
        ZMConversation *selfConversation = [ZMConversation conversationWithRemoteID:selfUser.remoteIdentifier createIfNeeded:YES inContext:self.syncMOC];
        selfConversation.conversationType = ZMConversationTypeSelf;

        NSDate *lastRead = [NSDate date];
        ZMConversation *updatedConversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        updatedConversation.remoteIdentifier = [NSUUID createUUID];
        updatedConversation.lastReadServerTimeStamp = lastRead;
        
        ZMClientMessage *lastReadUpdateMessage = [ZMConversation appendSelfConversationWithLastReadOfConversation:updatedConversation];
        XCTAssertNotNil(lastReadUpdateMessage);
        [[self.mockExpirationTimer stub] stopTimerForMessage:lastReadUpdateMessage];
        
        // when
        ZMUpstreamRequest *request = [(id<ZMUpstreamTranscoder>)self.sut requestForInsertingObject:lastReadUpdateMessage forKeys:nil];
        
        // then
        XCTAssertNotNil(request);
    }];
    WaitForAllGroupsToBeEmpty(0.5);
}


@end


@implementation ZMClientMessageTranscoderTests (GenericMessageData)

- (void)testThatThePreviewGenericMessageDataHasTheOriginalSizeOfTheMediumGenericMessagedata
{
    [self.syncMOC performGroupedBlockAndWait:^{

        // given
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        ZMAssetClientMessage *message = [conversation appendOTRMessageWithImageData:[self dataForResource:@"1900x1500" extension:@"jpg"] nonce:[NSUUID createUUID]];
        [[(id)self.upstreamObjectSync stub] objectsDidChange:OCMOCK_ANY];
        [[(id)self.mockExpirationTimer stub] objectsDidChange:OCMOCK_ANY];
        // when
        for(id<ZMContextChangeTracker> tracker in self.sut.contextChangeTrackers) {
            [tracker objectsDidChange:[NSSet setWithObject:message]];
        }
        
        // then
        ZMGenericMessage *mediumGenericMessage = [message.imageAssetStorage genericMessageForFormat:ZMImageFormatMedium];
        ZMGenericMessage *previewGenericMessage = [message.imageAssetStorage genericMessageForFormat:ZMImageFormatPreview];
        
        XCTAssertEqual(mediumGenericMessage.image.height, previewGenericMessage.image.originalHeight);
        XCTAssertEqual(mediumGenericMessage.image.width, previewGenericMessage.image.originalWidth);
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
}

@end


@implementation ZMClientMessageTranscoderTests (MessageConfirmation)


- (ZMUpdateEvent *)updateEventForTextMessage:(NSString *)text inConversationWithID:(NSUUID *)conversationID forClient:(UserClient *)client senderClient:(UserClient *)senderClient eventSource:(ZMUpdateEventSource)eventSource
{
    ZMGenericMessage *message = [ZMGenericMessage messageWithText:text nonce:[NSUUID createUUID].transportString];
    
    NSDictionary *payload = @{@"recipient": client.remoteIdentifier, @"sender": senderClient.remoteIdentifier, @"text": message.data.base64String};
    
    NSDictionary *eventPayload = @{
                                   @"id": NSUUID.createUUID.transportString,
                                   @"sender": senderClient.user.remoteIdentifier.transportString,
                                   @"type":@"conversation.otr-message-add",
                                   @"data":payload,
                                   @"conversation":conversationID.transportString,
                                   @"time":[NSDate dateWithTimeIntervalSince1970:555555].transportString
                                   };
    if (eventSource == ZMUpdateEventSourceDownload) {
        return [ZMUpdateEvent eventFromEventStreamPayload:eventPayload
                                                     uuid:nil];
    }
    return [ZMUpdateEvent eventsArrayFromTransportData:@{@"id" : NSUUID.createUUID.transportString,
                                                         @"payload" : @[eventPayload]} source:eventSource].firstObject;
}

- (void)testThatItInsertAConfirmationMessageWhenReceivingAnEvent
{
    // given
    UserClient *client = [self createSelfClient];
    ZMUser *user1 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
    user1.remoteIdentifier = [NSUUID createUUID];
    UserClient *senderClient = [self createClientForUser:user1 createSessionWithSelfUser:YES];
    [self.syncMOC saveOrRollback];
    WaitForAllGroupsToBeEmpty(0.5);
    
    NSString *text = @"Everything";
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
    conversation.conversationType = ZMTConversationTypeOneOnOne;
    conversation.remoteIdentifier = [NSUUID createUUID];
    
    ZMUpdateEvent *updateEvent = [self updateEventForTextMessage:text inConversationWithID:conversation.remoteIdentifier forClient:client senderClient:senderClient eventSource:ZMUpdateEventSourcePushNotification];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    [self.sut processEvents:@[updateEvent] liveEvents:YES prefetchResult:nil];

    // then
    XCTAssertEqual(conversation.hiddenMessages.count, 1u);
    ZMClientMessage *confirmationMessage = conversation.hiddenMessages.lastObject;
    XCTAssertTrue(confirmationMessage.genericMessage.hasConfirmation);
    XCTAssertEqualObjects(confirmationMessage.genericMessage.confirmation.messageId, updateEvent.messageNonce.transportString);
    
}


- (void)checkThatItCallsConfirmationStatus:(BOOL)shouldCallConfirmationStatus whenReceivingAnEventThroughSource:(ZMUpdateEventSource)source
{
    // given
    UserClient *client = [self createSelfClient];
    
    ZMUser *user1 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
    user1.remoteIdentifier = [NSUUID createUUID];
    UserClient *senderClient = [self createClientForUser:user1 createSessionWithSelfUser:YES];
    [self.syncMOC saveOrRollback];
    WaitForAllGroupsToBeEmpty(0.5);
    
    NSString *text = @"Everything";
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
    conversation.conversationType = ZMTConversationTypeOneOnOne;
    conversation.remoteIdentifier = [NSUUID createUUID];
    
    ZMUpdateEvent *updateEvent = [self updateEventForTextMessage:text inConversationWithID:conversation.remoteIdentifier forClient:client senderClient:senderClient eventSource:source];
    
    // expect
    if (shouldCallConfirmationStatus) {
    [[(id)self.mockAPNSConfirmationStatus expect] needsToConfirmMessage:[OCMArg checkWithBlock:^BOOL(NSUUID *messageNonce) {
        return ([[conversation.hiddenMessages.lastObject nonce] isEqual:messageNonce]);
    }]];
    } else {
        [[(id)self.mockAPNSConfirmationStatus reject] needsToConfirmMessage:OCMOCK_ANY];
    }
    
    // when
    [self.sut processEvents:@[updateEvent] liveEvents:YES prefetchResult:nil];
    [(id)self.mockAPNSConfirmationStatus verify];
}


- (void)testThatItCallsConfirmationStatusWhenReceivingAnEventThroughPush
{
    [self checkThatItCallsConfirmationStatus:YES whenReceivingAnEventThroughSource:ZMUpdateEventSourcePushNotification];
}

- (void)testThatItCallsConfirmationStatusWhenReceivingAnEventThroughWebSocket
{
    [self checkThatItCallsConfirmationStatus:NO whenReceivingAnEventThroughSource:ZMUpdateEventSourceWebSocket];
}

- (void)testThatItCallsConfirmationStatusWhenReceivingAnEventThroughDownload
{
    [self checkThatItCallsConfirmationStatus:NO whenReceivingAnEventThroughSource:ZMUpdateEventSourceDownload];
}

- (void)testThatItCallsConfirmationStatusWhenConfirmationMessageIsSentSuccessfully
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
    conversation.conversationType = ZMTConversationTypeOneOnOne;
    conversation.remoteIdentifier = [NSUUID createUUID];
    
    ZMMessage *message = [conversation appendMessageWithText:@"text"];
    ZMClientMessage *confirmationMessage = [(id)message confirmReception];
    NSUUID *confirmationUUID = confirmationMessage.nonce;
    [self.sut.upstreamObjectSync objectsDidChange:[NSSet setWithObject:confirmationMessage]];

    // expect
    [[(id)self.mockAPNSConfirmationStatus expect] didConfirmMessage:[OCMArg checkWithBlock:^BOOL(NSUUID *messageNonce) {
        return ([confirmationUUID isEqual:messageNonce]);
    }]];
    
    // when
    ZMTransportRequest *request = [self.sut.upstreamObjectSync nextRequest];
    [request completeWithResponse:[ZMTransportResponse responseWithPayload:@{} HTTPstatus:200 transportSessionError:nil]];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [(id)self.mockAPNSConfirmationStatus verify];
}

- (void)testThatItDeletesTheConfirmationMessageWhenSentSuccessfully
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
    conversation.conversationType = ZMTConversationTypeOneOnOne;
    conversation.remoteIdentifier = [NSUUID createUUID];
    
    ZMMessage *message = [conversation appendMessageWithText:@"text"];
    ZMClientMessage *confirmationMessage = [(id)message confirmReception];
    [self.sut.upstreamObjectSync objectsDidChange:[NSSet setWithObject:confirmationMessage]];
    
    // when
    ZMTransportRequest *request = [self.sut.upstreamObjectSync nextRequest];
    [request completeWithResponse:[ZMTransportResponse responseWithPayload:@{} HTTPstatus:200 transportSessionError:nil]];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertTrue(confirmationMessage.isZombieObject);
}

@end
