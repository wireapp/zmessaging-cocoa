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


@import WireDataModel;
@import WireTransport;
@import WireMockTransport;
@import WireUtilities;
@import WireTesting;

#import "MessagingTest.h"
#import "ZMUserSession.h"
#import "ZMUserSession+Internal.h"
#import "ZMConversationTranscoder+Internal.h"
#import <WireSyncEngine/WireSyncEngine-Swift.h>
#import "WireSyncEngine_iOS_Tests-Swift.h"
#import "ConversationTestsBase.h"

@interface FileTransferTests : ConversationTestsBase

@end

@implementation FileTransferTests

#pragma mark - Helper methods

- (NSURL *)testVideoFileURL
{
    NSBundle *bundle = [NSBundle bundleForClass:self.class];
    
    NSURL *url = [bundle URLForResource:@"video" withExtension:@"mp4"];
    if (nil == url) XCTFail("Unable to load video fixture from disk");
    return url;
}


- (ZMAssetClientMessage *)remotelyInsertAssetOriginalAndUpdate:(ZMGenericMessage *)updateMessage
                                                   insertBlock:(void (^)(NSData *data, MockConversation *conversation, MockUserClient *from, MockUserClient *to))insertBlock
                                                         nonce:(NSUUID *)nonce
{
    return [self remotelyInsertAssetOriginalWithMimeType:@"text/plain" updateWithMessage:updateMessage insertBlock:insertBlock nonce:nonce isEphemeral:NO];
}

- (ZMAssetClientMessage *)remotelyInsertAssetOriginalWithMimeType:(NSString *)mimeType
                                                updateWithMessage:(ZMGenericMessage *)updateMessage
                                                      insertBlock:(void (^)(NSData *data, MockConversation *conversation, MockUserClient *from, MockUserClient *to))insertBlock
                                                            nonce:(NSUUID *)nonce
                                                      isEphemeral:(BOOL)isEphemeral
{
    
    // given
    MockUserClient *selfClient = [self.selfUser.clients anyObject];
    MockUserClient *senderClient = [self.user1.clients anyObject];
    MockConversation *mockConversation = self.selfToUser1Conversation;
    
    XCTAssertNotNil(selfClient);
    XCTAssertNotNil(senderClient);
    
    ZMAsset *asset = [ZMAsset assetWithOriginal:[ZMAssetOriginal originalWithSize:256 mimeType:mimeType name:@"foo229"] preview:nil];
    ZMGenericMessage *original = [ZMGenericMessage messageWithContent:asset nonce:nonce timeout:isEphemeral ? 20 : 0];
    
    // when
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *__unused session) {
        [mockConversation encryptAndInsertDataFromClient:senderClient toClient:selfClient data:original.data];
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
    
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    XCTAssertEqual(conversation.allMessages.count, 2lu);
    
    if (! [conversation.lastMessage isKindOfClass:ZMAssetClientMessage.class]) {
        XCTFail(@"Unexpected message type, expected ZMAssetClientMessage : %@", [conversation.lastMessage class]);
        return nil;
    }
    
    ZMAssetClientMessage *message = (ZMAssetClientMessage *)conversation.lastMessage;
    XCTAssertEqual(message.size, 256lu);
    XCTAssertEqualObjects(message.mimeType, mimeType);
    XCTAssertEqualObjects(message.nonce, nonce);
    
    // perform update
    
    [self.mockTransportSession performRemoteChanges:^(__unused MockTransportSession<MockTransportSessionObjectCreation> *session) {
        NSData *updateMessageData = [MockUserClient encryptedWithData:updateMessage.data from:senderClient to:selfClient];
        insertBlock(updateMessageData, mockConversation, senderClient, selfClient);
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    return message;
}

- (NSArray *)filterOutRequestsForLastRead:(NSArray *)requests
{
    NSString *conversationPrefix = [NSString stringWithFormat:@"/conversations/%@/otr/messages",  [ZMConversation selfConversationInContext:self.userSession.managedObjectContext].remoteIdentifier.transportString];
    return [requests filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id  obj, NSDictionary __unused *bindings) {
        return ![((ZMTransportRequest *)obj).path hasPrefix:conversationPrefix];
    }]];
}



#pragma mark - Asset V2

#pragma mark Downloading

- (void)testThatItSendsTheRequestToDownloadAFile_WhenItHasTheAssetID
{
    // given
    XCTAssertTrue([self login]);
    
    NSUUID *nonce = NSUUID.createUUID;
    NSUUID *token = NSUUID.createUUID;
    NSUUID *assetID = NSUUID.createUUID;
    NSData *otrKey = NSData.randomEncryptionKey;
    
    NSData *assetData = [NSData secureRandomDataOfLength:256];
    NSData *encryptedAsset = [assetData zmEncryptPrefixingPlainTextIVWithKey:otrKey];
    NSData *sha256 = encryptedAsset.zmSHA256Digest;
    
    ZMAssetRemoteData *remoteData = [ZMAssetRemoteData remoteDataWithOTRKey:otrKey sha256:sha256 assetId:assetID.transportString assetToken:nil];
    ZMAssetBuilder *assetBuilder = [[ZMAssetBuilder alloc] init];
    assetBuilder.uploaded = remoteData;
    ZMAsset *asset = [assetBuilder build];
    
    ZMGenericMessage *uploaded = [ZMGenericMessage messageWithContent:asset nonce:nonce];
    
    // when
    ZMAssetClientMessage *message = [self remotelyInsertAssetOriginalAndUpdate:uploaded insertBlock:
                                     ^(NSData *data, MockConversation *conversation, MockUserClient *from, MockUserClient *to) {
                                         [conversation insertOTRMessageFromClient:from toClient:to data:data];
                                     } nonce:nonce];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // creating the asset remotely
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [session insertAssetWithID:assetID assetToken:token assetData:encryptedAsset contentType:@"text/plain"];
    }];
    
    // then
    XCTAssertEqual(message.downloadState, AssetDownloadStateRemote);
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    [self.mockTransportSession resetReceivedRequests];
    [self.userSession performChanges:^{
        [message requestFileDownload];
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(message.downloadState, AssetDownloadStateDownloaded);
}

- (void)testThatItSendsTheRequestToDownloadAFileWhenItHasTheAssetID_AndSetsTheStateTo_FailedDownload_AfterFailedDecryption
{
    //given
    XCTAssertTrue([self login]);
    
    NSUUID *nonce = NSUUID.createUUID;
    NSUUID *assetID = NSUUID.createUUID;
    NSData *otrKey = NSData.randomEncryptionKey;
    
    NSData *assetData = [NSData secureRandomDataOfLength:256];
    NSData *encryptedAsset = [assetData zmEncryptPrefixingPlainTextIVWithKey:otrKey];
    NSData *sha256 = encryptedAsset.zmSHA256Digest;
    
    ZMGenericMessage *uploaded = [ZMGenericMessage messageWithContent:[ZMAsset assetWithUploadedOTRKey:otrKey sha256:sha256] nonce:nonce];
    
    // when
    ZMAssetClientMessage *message = [self remotelyInsertAssetOriginalAndUpdate:uploaded insertBlock:
                                     ^(NSData *data, MockConversation *conversation, MockUserClient *from, MockUserClient *to) {
                                         [conversation insertOTRAssetFromClient:from toClient:to metaData:data imageData:assetData assetId:assetID isInline:NO];
                                     } nonce:nonce];
    WaitForAllGroupsToBeEmpty(0.5);
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    
    // creating a wrong asset (different hash, will fail to decrypt) remotely
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [session createAssetWithData:[NSData secureRandomDataOfLength:128]
                          identifier:assetID.transportString
                         contentType:@"text/plain"
                     forConversation:conversation.remoteIdentifier.transportString];
    }];
    
    // We no longer process incoming V2 assets so we need to manually set some properties to simulate having received the asset
    [self.userSession performChanges:^{
        message.version = 2;
        message.assetId = assetID;
        [message updateTransferState:AssetTransferStateUploaded synchronize:NO];
    }];
    
    // then
    XCTAssertEqualObjects(message.assetId, assetID); // We should have received an asset ID to be able to download the file
    XCTAssertEqualObjects(message.nonce, nonce);
    XCTAssertEqual(message.transferState, AssetTransferStateUploaded);
    XCTAssertEqual(message.downloadState, AssetDownloadStateRemote);
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    [self performIgnoringZMLogError:^{
        [self.userSession performChanges:^{
            [message requestFileDownload];
        }];
        
        WaitForAllGroupsToBeEmpty(0.5);
    }];
    
    // then
    ZMTransportRequest *lastRequest = self.mockTransportSession.receivedRequests.lastObject;
    NSString *expectedPath = [NSString stringWithFormat:@"/conversations/%@/otr/assets/%@", conversation.remoteIdentifier.transportString, message.assetId.transportString];
    XCTAssertEqualObjects(lastRequest.path, expectedPath);
    XCTAssertEqual(message.downloadState, AssetDownloadStateRemote);
}

- (void)testThatItSendsTheRequestToDownloadAFileWhenItHasTheAssetID_AndSetsTheStateTo_FailedDownload_AfterFailedDecryption_Ephemeral
{
    //given
    XCTAssertTrue([self login]);
    
    NSUUID *nonce = NSUUID.createUUID;
    NSUUID *assetID = NSUUID.createUUID;
    NSData *otrKey = NSData.randomEncryptionKey;
    
    NSData *assetData = [NSData secureRandomDataOfLength:256];
    NSData *encryptedAsset = [assetData zmEncryptPrefixingPlainTextIVWithKey:otrKey];
    NSData *sha256 = encryptedAsset.zmSHA256Digest;
    
    ZMGenericMessage *uploaded = [ZMGenericMessage messageWithContent:[ZMAsset assetWithUploadedOTRKey:otrKey sha256:sha256] nonce:nonce timeout:30];
    
    // when
    ZMAssetClientMessage *message = [self remotelyInsertAssetOriginalAndUpdate:uploaded insertBlock:
                                     ^(NSData *data, MockConversation *conversation, MockUserClient *from, MockUserClient *to) {
                                         [conversation insertOTRAssetFromClient:from toClient:to metaData:data imageData:assetData assetId:assetID isInline:NO];
                                     } nonce:nonce];
    XCTAssertTrue(message.isEphemeral);
    
    WaitForAllGroupsToBeEmpty(0.5);
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    
    // creating a wrong asset (different hash, will fail to decrypt) remotely
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [session createAssetWithData:[NSData secureRandomDataOfLength:128]
                          identifier:assetID.transportString
                         contentType:@"text/plain"
                     forConversation:conversation.remoteIdentifier.transportString];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // We no longer process incoming V2 assets so we need to manually set some properties to simulate having received the asset
    [self.userSession performChanges:^{
        message.version = 2;
        message.assetId = assetID;
        [message updateTransferState:AssetTransferStateUploaded synchronize:NO];
    }];
    
    // then
    XCTAssertEqualObjects(message.nonce, nonce);
    XCTAssertEqual(message.transferState, AssetTransferStateUploaded);
    XCTAssertEqual(message.downloadState, AssetDownloadStateRemote);
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    [self.userSession performChanges:^{
        [message requestFileDownload];
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    ZMTransportRequest *lastRequest = self.mockTransportSession.receivedRequests.lastObject;
    NSString *expectedPath = [NSString stringWithFormat:@"/conversations/%@/otr/assets/%@", conversation.remoteIdentifier.transportString, message.assetId.transportString];
    XCTAssertEqualObjects(lastRequest.path, expectedPath);
    XCTAssertEqual(message.downloadState, AssetDownloadStateRemote);
    XCTAssertTrue(message.isEphemeral);
}

#pragma mark - Asset V3

#pragma mark Receiving

- (void)testThatAFileUpload_AssetOriginal_MessageIsReceivedWhenSentRemotely_Ephemeral
{
    //given
    XCTAssertTrue([self login]);
    
    [self establishSessionWithMockUser:self.user1];
    WaitForAllGroupsToBeEmpty(0.5);
    
    NSUUID *nonce = NSUUID.createUUID;
    ZMGenericMessage *original = [ZMGenericMessage messageWithContent:[ZMAsset assetWithOriginalWithImageSize:CGSizeZero mimeType:@"text/plain" size:256] nonce:nonce timeout:30];
    
    // when
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> * __unused session) {
        [self.selfToUser1Conversation encryptAndInsertDataFromClient:self.user1.clients.anyObject
                                                            toClient:self.selfUser.clients.anyObject
                                                                data:original.data];
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    XCTAssertEqual(conversation.allMessages.count, 2lu);
    
    if (! [conversation.lastMessage isKindOfClass:ZMAssetClientMessage.class]) {
        return XCTFail(@"Unexpected message type, expected ZMAssetClientMessage : %@", [conversation.lastMessage class]);
    }
    
    ZMAssetClientMessage *message = (ZMAssetClientMessage *)conversation.lastMessage;
    XCTAssertTrue(message.isEphemeral);
    
    XCTAssertEqual(message.size, 256lu);
    XCTAssertEqualObjects(message.mimeType, @"text/plain");
    XCTAssertEqualObjects(message.nonce, nonce);
    XCTAssertNil(message.assetId);
    XCTAssertEqual(message.transferState, AssetTransferStateUploading);
}

- (void)testThatItDeletesAFileMessageWhenTheUploadIsCancelledRemotely_Ephemeral
{
    //given
    XCTAssertTrue([self login]);
    
    NSUUID *nonce = NSUUID.createUUID;
    ZMGenericMessage *cancelled = [ZMGenericMessage messageWithContent:[ZMAsset assetWithNotUploaded:ZMAssetNotUploadedCANCELLED] nonce:nonce timeout:30];
    
    // when
    ZMAssetClientMessage *message = [self remotelyInsertAssetOriginalAndUpdate:cancelled insertBlock:
                                     ^(NSData *data, MockConversation *conversation, MockUserClient *from, MockUserClient *to) {
                                         [conversation insertOTRMessageFromClient:from toClient:to data:data];
                                     } nonce:nonce];
    
    // then
    XCTAssertTrue(message.isZombieObject);
}

- (void)testThatItUpdatesAFileMessageWhenTheUploadFailesRemotlely_Ephemeral
{
    //given
    XCTAssertTrue([self login]);
    
    NSUUID *nonce = NSUUID.createUUID;
    ZMGenericMessage *failed = [ZMGenericMessage messageWithContent:[ZMAsset assetWithNotUploaded:ZMAssetNotUploadedFAILED] nonce:nonce timeout:30];
    
    // when
    ZMAssetClientMessage *message = [self remotelyInsertAssetOriginalAndUpdate:failed insertBlock:
                                     ^(NSData *data, MockConversation *conversation, MockUserClient *from, MockUserClient *to) {
                                         [conversation insertOTRMessageFromClient:from toClient:to data:data];
                                     } nonce:nonce];
    XCTAssertTrue(message.isEphemeral);
    
    // then
    XCTAssertNil(message.assetId);
    XCTAssertEqual(message.transferState, AssetTransferStateUploadingFailed);
    XCTAssertTrue(message.isEphemeral);
}

- (void)testThatItReceivesAVideoFileMessageThumbnailSentRemotely_V3
{
    // given
    XCTAssertTrue([self login]);

    NSUUID *nonce = NSUUID.createUUID;
    NSUUID *thumbnailAssetID = NSUUID.createUUID;
    NSString *thumbnailIDString = thumbnailAssetID.transportString;
    NSData *otrKey = NSData.randomEncryptionKey;
    NSData *encryptedAsset = [self.mediumJPEGData zmEncryptPrefixingPlainTextIVWithKey:otrKey];
    NSData *sha256 = encryptedAsset.zmSHA256Digest;

    ZMAssetRemoteData *remote = [ZMAssetRemoteData remoteDataWithOTRKey:otrKey sha256:sha256 assetId:thumbnailIDString assetToken:nil];
    ZMAssetImageMetaData *image = [ZMAssetImageMetaData imageMetaDataWithWidth:1024 height:2048];
    ZMAssetPreview *preview = [ZMAssetPreview previewWithSize:256 mimeType:@"image/jpeg" remoteData:remote imageMetadata:image];
    ZMAsset *asset = [ZMAsset assetWithOriginal:nil preview:preview];
    ZMGenericMessage *updateMessage = [ZMGenericMessage messageWithContent:asset nonce:nonce];


    // when
    __block MessageChangeObserver *observer;
    __block ZMConversation *conversation;

    id insertBlock = ^(NSData *data, MockConversation *mockConversation, MockUserClient *from, MockUserClient *to) {
        [mockConversation insertOTRMessageFromClient:from toClient:to data:data];
        conversation = [self conversationForMockConversation:mockConversation];
        observer = [[MessageChangeObserver alloc] initWithMessage:conversation.lastMessage];
    };

    ZMAssetClientMessage *message = [self remotelyInsertAssetOriginalWithMimeType:@"video/mp4"
                                                                updateWithMessage:updateMessage
                                                                      insertBlock:insertBlock
                                                                            nonce:nonce
                                                                      isEphemeral:NO];

    // Mock the asset/v3 request
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request) {
        NSString *expectedPath = [NSString stringWithFormat:@"/assets/v3/%@", thumbnailIDString];
        if ([request.path isEqualToString:expectedPath]) {
            return [[ZMTransportResponse alloc] initWithImageData:encryptedAsset HTTPStatus:200 transportSessionError:nil headers:nil];
        }
        return nil;
    };

    WaitForAllGroupsToBeEmpty(0.5);

    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertNotNil(message);
    XCTAssertNotNil(observer);
    XCTAssertNotNil(conversation);

    [self.userSession performChanges:^{
        [message.fileMessageData requestImagePreviewDownload];
    }];

    WaitForAllGroupsToBeEmpty(0.5);

    XCTAssertNotNil(message);
    NSArray *notifications = observer.notifications;
    XCTAssertEqual(notifications.count, 2lu);
    MessageChangeInfo *info = notifications.lastObject;
    XCTAssertTrue(info.imageChanged);

    // then
    // We should have received an thumbnail asset ID to be able to download the thumbnail image
    XCTAssertEqualObjects(message.fileMessageData.thumbnailAssetID, thumbnailIDString);
    XCTAssertEqualObjects(message.nonce, nonce);
    XCTAssertEqual(message.transferState, AssetTransferStateUploading);
    
}

- (void)testThatItReceivesAVideoFileMessageThumbnailSentRemotely_Ephemeral_V3
{
    // given
    XCTAssertTrue([self login]);

    NSUUID *nonce = NSUUID.createUUID;
    NSUUID *thumbnailAssetID = NSUUID.createUUID;
    NSString *thumbnailIDString = thumbnailAssetID.transportString;
    NSData *otrKey = NSData.randomEncryptionKey;
    NSData *encryptedAsset = [self.mediumJPEGData zmEncryptPrefixingPlainTextIVWithKey:otrKey];
    NSData *sha256 = encryptedAsset.zmSHA256Digest;

    ZMAssetRemoteData *remote = [ZMAssetRemoteData remoteDataWithOTRKey:otrKey sha256:sha256 assetId:thumbnailIDString assetToken:nil];
    ZMAssetImageMetaData *image = [ZMAssetImageMetaData imageMetaDataWithWidth:1024 height:2048];
    ZMAssetPreview *preview = [ZMAssetPreview previewWithSize:256 mimeType:@"image/jpeg" remoteData:remote imageMetadata:image];
    ZMAsset *asset = [ZMAsset assetWithOriginal:nil preview:preview];
    ZMGenericMessage *updateMessage = [ZMGenericMessage messageWithContent:asset nonce:nonce timeout:20];

    // when
    __block MessageChangeObserver *observer;
    __block ZMConversation *conversation;

    id insertBlock = ^(NSData *data, MockConversation *mockConversation, MockUserClient *from, MockUserClient *to) {
        [mockConversation insertOTRMessageFromClient:from toClient:to data:data];
        conversation = [self conversationForMockConversation:mockConversation];
        observer = [[MessageChangeObserver alloc] initWithMessage:conversation.lastMessage];
    };

    ZMAssetClientMessage *message = [self remotelyInsertAssetOriginalWithMimeType:@"video/mp4"
                                                                updateWithMessage:updateMessage
                                                                      insertBlock:insertBlock
                                                                            nonce:nonce
                                                                      isEphemeral:YES];
    XCTAssertTrue(message.isEphemeral);

    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request) {
        NSString *expectedPath = [NSString stringWithFormat:@"/assets/v3/%@", thumbnailIDString];
        if ([request.path isEqualToString:expectedPath]) {
            return [[ZMTransportResponse alloc] initWithImageData:encryptedAsset HTTPStatus:200 transportSessionError:nil headers:nil];
        }
        return nil;
    };

    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertNotNil(message);
    XCTAssertNotNil(observer);
    XCTAssertNotNil(conversation);

    [self.userSession performChanges:^{
        [message.fileMessageData requestImagePreviewDownload];
    }];

    WaitForAllGroupsToBeEmpty(0.5);

    XCTAssertNotNil(message);
    NSArray *notifications = observer.notifications;
    XCTAssertEqual(notifications.count, 2lu);
    MessageChangeInfo *info = notifications.lastObject;
    XCTAssertTrue(info.imageChanged);

    // then
    // We should have received an thumbnail asset ID to be able to download the thumbnail image
    XCTAssertEqualObjects(message.fileMessageData.thumbnailAssetID, thumbnailIDString);
    XCTAssertEqualObjects(message.nonce, nonce);
    XCTAssertEqual(message.transferState, AssetTransferStateUploading);
    XCTAssertTrue(message.isEphemeral);

}

- (void)testThatAFileUpload_AssetUploaded_MessageIsReceivedAndUpdatesTheOriginalMessageWhenSentRemotely_V3
{
    // given
    XCTAssertTrue([self login]);

    NSUUID *nonce = NSUUID.createUUID;
    NSUUID *assetID = NSUUID.createUUID;
    NSData *otrKey = NSData.randomEncryptionKey;
    NSData *sha256 = NSData.zmRandomSHA256Key;
    ZMGenericMessage *uploaded = [[ZMGenericMessage messageWithContent:[ZMAsset assetWithUploadedOTRKey:otrKey sha256:sha256] nonce:nonce] updatedUploadedWithAssetId:assetID.transportString token:nil];

    // when
    ZMAssetClientMessage *message = [self remotelyInsertAssetOriginalAndUpdate:uploaded insertBlock:
                                     ^(NSData *data, MockConversation *conversation, MockUserClient *from, MockUserClient *to) {
                                         [conversation insertOTRMessageFromClient:from toClient:to data:data];
                                     } nonce:nonce];

    // then
    XCTAssertNil(message.assetId); // We do not store the asset ID in the DB for v3 assets
    XCTAssertEqualObjects(message.genericAssetMessage.assetData.uploaded.assetId, assetID.transportString);
    XCTAssertEqual(message.version, 3);
    XCTAssertEqualObjects(message.nonce, nonce);
    XCTAssertEqual(message.transferState, AssetTransferStateUploaded);
}

#pragma mark Sending

- (void)testThatItSendsATextMessageAfterAFileMessage
{
    //given
    XCTAssertTrue([self login]);
    
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    XCTAssertNotNil(conversation);
    XCTAssertEqual(conversation.allMessages.count, 1lu);
    
    NSURL *fileURL = [self createTestFile:@"foo22cc"];
    
    // when
    __block ZMMessage *fileMessage;
    [self.userSession performChanges:^{
        fileMessage = (id)[conversation appendMessageWithFileMetadata:[[ZMFileMetadata alloc] initWithFileURL:fileURL thumbnail:nil]];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    __block ZMMessage *textMessage;
    [self.userSession performChanges:^{
        textMessage = (id)[conversation appendMessageWithText:@"foo22cc"];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    //then
    XCTAssertEqual(fileMessage.deliveryState, ZMDeliveryStateSent);
    //    XCTAssertEqual(fileMessage.fileMessageData.transferState, AssetTransferStateUploaded);
    XCTAssertEqual(textMessage.deliveryState, ZMDeliveryStateSent);
    XCTAssertEqual(conversation.allMessages.count, 3lu);
}

- (void)testThatItSendsAFileMessage_V3
{
    // given
    XCTAssertTrue([self login]);

    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    XCTAssertNotNil(conversation);
    XCTAssertEqual(conversation.allMessages.count, 1lu);
    [self prefetchRemoteClientByInsertingMessageInConversation:self.selfToUser1Conversation];

    NSURL *fileURL = [self createTestFile:@"foofile"];
    NSString *expectedMessageAddPath = [NSString stringWithFormat:@"/conversations/%@/otr/messages", conversation.remoteIdentifier.transportString];
    NSString *expectedAssetUploadPath = @"/assets/v3";

    // when
    [self.mockTransportSession resetReceivedRequests];

    __block ZMMessage *fileMessage;
    [self.userSession performChanges:^{
        fileMessage = (id)[conversation appendMessageWithFileMetadata:[[ZMFileMetadata alloc] initWithFileURL:fileURL thumbnail:nil]];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertEqual(fileMessage.deliveryState, ZMDeliveryStateSent);
    XCTAssertEqual(fileMessage.fileMessageData.downloadState, AssetDownloadStateDownloaded);

    NSArray <ZMTransportRequest *> *requests = [self filterOutRequestsForLastRead:self.mockTransportSession.receivedRequests];
    XCTAssertEqual(requests.count, 2lu); // Asset Upload (v3), Asset.Uploaded message
    ZMTransportRequest *fullAssetUploadRequest  = requests[0];
    ZMTransportRequest *fullAssetMessageRequest = requests[1];

    XCTAssertEqualObjects(fullAssetUploadRequest.path, expectedAssetUploadPath);
    XCTAssertEqualObjects(fullAssetMessageRequest.path, expectedMessageAddPath);

    ZMMessage *message = conversation.lastMessage;

    XCTAssertNotNil(message.fileMessageData);
    XCTAssertNil(message.imageMessageData);
    XCTAssertEqualObjects(message.fileMessageData.filename.stringByDeletingPathExtension, @"foofile");
    XCTAssertEqualObjects(message.fileMessageData.filename.pathExtension, @"dat");
    XCTAssertEqual(message.fileMessageData.size, 256lu);
}

- (void)testThatItSendsNoneVideoFileMessage_withThumbnail_V3
{
    // given
    XCTAssertTrue([self login]);

    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    XCTAssertNotNil(conversation);

    XCTAssertEqual(conversation.allMessages.count, 1lu);
    [self prefetchRemoteClientByInsertingMessageInConversation:self.selfToUser1Conversation];

    NSURL *fileURL = [self createTestFile:@"foogile"];
    NSString *expectedMessageAddPath = [NSString stringWithFormat:@"/conversations/%@/otr/messages", conversation.remoteIdentifier.transportString];
    NSString *expectedAssetUploadPath = @"/assets/v3";

    // when
    [self.mockTransportSession resetReceivedRequests];

    __block ZMMessage *fileMessage;
    [self.userSession performChanges:^{
        fileMessage = (id)[conversation appendMessageWithFileMetadata:[[ZMFileMetadata alloc] initWithFileURL:fileURL thumbnail:self.mediumJPEGData]];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertEqual(fileMessage.deliveryState, ZMDeliveryStateSent);
    XCTAssertEqual(fileMessage.fileMessageData.transferState, AssetTransferStateUploaded);

    NSArray <ZMTransportRequest *> *requests = [self filterOutRequestsForLastRead:self.mockTransportSession.receivedRequests];
    XCTAssertEqual(requests.count, 3lu); // Thumbnail Upload, Full Asset Upload, Asset.Uploaded

    ZMTransportRequest *thumbnailAssetUploadRequest = requests[0];
    ZMTransportRequest *fullAssetUploadRequest      = requests[1];
    ZMTransportRequest *fullAssetMessageRequest     = requests[2];

    XCTAssertEqualObjects(fullAssetMessageRequest.path, expectedMessageAddPath);
    XCTAssertEqualObjects(thumbnailAssetUploadRequest.path, expectedAssetUploadPath);
    XCTAssertEqualObjects(fullAssetUploadRequest.path, expectedAssetUploadPath);

    ZMMessage *message = conversation.lastMessage;

    XCTAssertNotNil(message.fileMessageData);
    XCTAssertNil(message.imageMessageData);
    XCTAssertEqualObjects(message.fileMessageData.filename.stringByDeletingPathExtension, @"foogile");
    XCTAssertEqualObjects(message.fileMessageData.filename.pathExtension, @"dat");
    XCTAssertEqual(message.fileMessageData.size, 256lu);
    
}

- (void)testThatItResendsAFailedFileMessage_V3
{
    // given
    XCTAssertTrue([self login]);

    [self prefetchRemoteClientByInsertingMessageInConversation:self.selfToUser1Conversation];

    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    XCTAssertNotNil(conversation);
    XCTAssertEqual(conversation.allMessages.count, 2lu);

    NSURL *fileURL = [self createTestFile:@"fooz"];

    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request) {
        if ([request.path isEqualToString:@"/assets/v3"]) {
            return [ZMTransportResponse responseWithPayload:nil HTTPStatus:400 transportSessionError:nil];
        }
        return nil;
    };

    // when
    __block ZMMessage *fileMessage;
    [self.userSession performChanges:^{
        fileMessage = (id)[conversation appendMessageWithFileMetadata:[[ZMFileMetadata alloc] initWithFileURL:fileURL thumbnail:nil]];
    }];
    WaitForAllGroupsToBeEmpty(1.0);

    // then
    XCTAssertEqual(fileMessage.deliveryState, ZMDeliveryStateFailedToSend);
    XCTAssertEqual(fileMessage.fileMessageData.transferState, AssetTransferStateUploadingFailed);

    // and when
    self.mockTransportSession.responseGeneratorBlock = nil;
    [self.userSession performChanges:^{
        [fileMessage resend];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertEqual(fileMessage.deliveryState, ZMDeliveryStateSent);
    XCTAssertEqual(fileMessage.fileMessageData.transferState, AssetTransferStateUploaded);
    
}

- (void)testThatItSendsATextMessageAfterAFileMessage_V3
{
    // given
    XCTAssertTrue([self login]);

    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    XCTAssertNotNil(conversation);
    XCTAssertEqual(conversation.allMessages.count, 1lu);

    NSURL *fileURL = [self createTestFile:@"foob"];

    // when
    __block ZMMessage *fileMessage;
    [self.userSession performChanges:^{
        fileMessage = (id)[conversation appendMessageWithFileMetadata:[[ZMFileMetadata alloc] initWithFileURL:fileURL thumbnail:nil]];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    __block ZMMessage *textMessage;
    [self.userSession performChanges:^{
        textMessage = (id)[conversation appendMessageWithText:self.name];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertEqual(fileMessage.deliveryState, ZMDeliveryStateSent);
    XCTAssertEqual(fileMessage.fileMessageData.transferState, AssetTransferStateUploaded);
    XCTAssertEqual(textMessage.deliveryState, ZMDeliveryStateSent);
    XCTAssertEqual(conversation.allMessages.count, 3lu);
    
}

- (void)testThatItDoesReuploadTheAssetMetadataAfterReceivingA_412_MissingClients_V3
{
    //given
    XCTAssertTrue([self login]);
    
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    XCTAssertEqual(conversation.allMessages.count, 1lu);
    XCTAssertNotNil(conversation);

    NSURL *fileURL = [self createTestFile:@"foo2432"];
    NSString *expectedMessageAddPath = [NSString stringWithFormat:@"/conversations/%@/otr/messages", conversation.remoteIdentifier.transportString];
    NSString *expectedAssetAddPath = @"/assets/v3";
    NSString *expectedFetchUserClientPath = [NSString stringWithFormat:@"/users/%@/clients/%@", self.user1.identifier, [(MockUserClient *)self.user1.clients.anyObject identifier]];

    // when
    __block ZMMessage *fileMessage;

    [self.mockTransportSession resetReceivedRequests];
    [self.userSession performChanges:^{
        fileMessage = (id)[conversation appendMessageWithFileMetadata:[[ZMFileMetadata alloc] initWithFileURL:fileURL thumbnail:nil]];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    //then
    XCTAssertEqual(fileMessage.deliveryState, ZMDeliveryStateSent);
    NSArray <ZMTransportRequest *> *requests = [self filterOutRequestsForLastRead:self.mockTransportSession.receivedRequests];

    XCTAssertEqual(requests.count, 5lu);

    if (requests.count < 4) {
        return;
    }

    ZMTransportRequest *assetAddRequest = requests[0];
    ZMTransportRequest *messageAddRequest = requests[1];
    ZMTransportRequest *missingPrekeysRequest = requests[2];
    ZMTransportRequest *fetchUserClientRequest = requests[3];
    ZMTransportRequest *secondMessageAddRequest = requests[4];

    XCTAssertEqualObjects(assetAddRequest.path, expectedAssetAddPath);
    XCTAssertEqualObjects(messageAddRequest.path, expectedMessageAddPath);
    XCTAssertEqualObjects(missingPrekeysRequest.path, @"/users/prekeys");
    XCTAssertEqualObjects(fetchUserClientRequest.path, expectedFetchUserClientPath);
    XCTAssertEqualObjects(secondMessageAddRequest.path, expectedMessageAddPath);
    XCTAssertEqual(conversation.allMessages.count, 2lu);

    ZMMessage *message = conversation.lastMessage;
    XCTAssertNotNil(message.fileMessageData);
    XCTAssertNil(message.imageMessageData);
}


#pragma mark Sending Video (Preview)

- (void)testThatItSendsAFileMessage_WithVideo_V3
{
    // given
    XCTAssertTrue([self login]);

    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    XCTAssertNotNil(conversation);
    XCTAssertEqual(conversation.allMessages.count, 1lu);

    [self prefetchRemoteClientByInsertingMessageInConversation:self.selfToUser1Conversation];

    NSURL *fileURL = self.testVideoFileURL;
    NSString *expectedMessageAddPath = [NSString stringWithFormat:@"/conversations/%@/otr/messages", conversation.remoteIdentifier.transportString];
    // Used for uploading the thumbnail and the full asset
    NSString *expectedAssetAddPath = @"/assets/v3";

    // when
    [self.mockTransportSession resetReceivedRequests];

    __block ZMMessage *fileMessage;
    [self.userSession performChanges:^{
        ZMVideoMetadata *metadata = [[ZMVideoMetadata alloc] initWithFileURL:fileURL thumbnail:self.mediumJPEGData];
        fileMessage = (id)[conversation appendMessageWithFileMetadata:metadata];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertEqual(fileMessage.deliveryState, ZMDeliveryStateSent);
    XCTAssertEqual(fileMessage.fileMessageData.transferState, AssetTransferStateUploaded);

    NSArray <ZMTransportRequest *> *requests = [self filterOutRequestsForLastRead:self.mockTransportSession.receivedRequests];

    //  Preview upload, Asset upload, generic message
    if (3 != requests.count) {
        return XCTFail(@"Wrong number of requests");
    }

    ZMTransportRequest *thumbnailRequest = requests[0];
    XCTAssertEqualObjects(thumbnailRequest.path, expectedAssetAddPath);

    ZMTransportRequest *fullAssetRequest = requests[1];
    XCTAssertEqualObjects(fullAssetRequest.path, expectedAssetAddPath);

    ZMTransportRequest *fullAssetGenericMessageRequest = requests[2];
    XCTAssertEqualObjects(fullAssetGenericMessageRequest.path, expectedMessageAddPath);

    ZMMessage *message = conversation.lastMessage;

    XCTAssertNotNil(message.fileMessageData);
    XCTAssertNil(message.imageMessageData);
    XCTAssertEqualObjects(message.fileMessageData.filename.stringByDeletingPathExtension, @"video");
    XCTAssertEqualObjects(message.fileMessageData.filename.pathExtension, @"mp4");

    NSError *error = nil;
    NSUInteger size = [NSFileManager.defaultManager attributesOfItemAtPath:fileURL.path error:&error].fileSize;

    XCTAssertNil(error);
    XCTAssertEqual(message.fileMessageData.size, size);
    
}

- (void)testThatItSendsAFileMessage_WithVideo_Ephemeral_V3
{
    //given
    XCTAssertTrue([self login]);
    
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    conversation.localMessageDestructionTimeout = 10;
    XCTAssertNotNil(conversation);
    XCTAssertEqual(conversation.allMessages.count, 1lu);
    
    [self prefetchRemoteClientByInsertingMessageInConversation:self.selfToUser1Conversation];
    
    NSURL *fileURL = self.testVideoFileURL;
    NSString *expectedMessageAddPath = [NSString stringWithFormat:@"/conversations/%@/otr/messages", conversation.remoteIdentifier.transportString];
    // Used for uploading the thumbnail and the full asset
    NSString *expectedAssetUploadPath = @"/assets/v3";
    
    // when
    [self.mockTransportSession resetReceivedRequests];
    
    __block ZMMessage *fileMessage;
    [self.userSession performChanges:^{
        fileMessage = (id)[conversation appendMessageWithFileMetadata:[[ZMVideoMetadata alloc] initWithFileURL:fileURL thumbnail:self.mediumJPEGData]];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    //then
    XCTAssertTrue(fileMessage.isEphemeral);
    XCTAssertEqual(fileMessage.deliveryState, ZMDeliveryStateSent);
    XCTAssertEqual(fileMessage.fileMessageData.downloadState, AssetDownloadStateDownloaded);
    
    NSArray <ZMTransportRequest *> *requests = [self filterOutRequestsForLastRead:self.mockTransportSession.receivedRequests];
    
    
    if (3 != requests.count) {
        return XCTFail(@"Wrong number of requests");
    }
    
    XCTAssertEqualObjects(requests[0].path, expectedAssetUploadPath);   // /assets/v3       (Preview)
    XCTAssertEqualObjects(requests[1].path, expectedAssetUploadPath);   // /assets/v3       (Medium)
    XCTAssertEqualObjects(requests[2].path, expectedMessageAddPath);    // /otr/messages    (Including Uploaded)
    
    ZMMessage *message = conversation.lastMessage;
    
    XCTAssertNotNil(message.fileMessageData);
    XCTAssertNil(message.imageMessageData);
    XCTAssertEqualObjects(message.fileMessageData.filename.stringByDeletingPathExtension, @"video");
    XCTAssertEqualObjects(message.fileMessageData.filename.pathExtension, @"mp4");
    
    NSError *error = nil;
    NSUInteger size = [NSFileManager.defaultManager attributesOfItemAtPath:fileURL.path error:&error].fileSize;
    
    XCTAssertNil(error);
    XCTAssertEqual(message.fileMessageData.size, size);
}

- (void)testThatItResendsAFailedFileMessage_WithVideo_V3
{
    //given
    XCTAssertTrue([self login]);

    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    XCTAssertNotNil(conversation);
    XCTAssertEqual(conversation.allMessages.count, 1lu);

    NSURL *fileURL = self.testVideoFileURL;

    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request) {
        // We fail the thumbnail asset upload
        if ([request.path isEqualToString:@"/assets/v3"]) {
            return [ZMTransportResponse responseWithPayload:nil HTTPStatus:400 transportSessionError:nil];
        }
        return nil;
    };

    // when
    __block ZMMessage *fileMessage;
    [self.userSession performChanges:^{
        ZMVideoMetadata *metadata = [[ZMVideoMetadata alloc] initWithFileURL:fileURL thumbnail:self.mediumJPEGData];
        fileMessage = (id)[conversation appendMessageWithFileMetadata:metadata];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertEqual(fileMessage.deliveryState, ZMDeliveryStateFailedToSend);
    XCTAssertEqual(fileMessage.fileMessageData.transferState, AssetTransferStateUploadingFailed);

    // and when
    self.mockTransportSession.responseGeneratorBlock = nil;
    [self.userSession performChanges:^{
        [fileMessage resend];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertEqual(fileMessage.deliveryState, ZMDeliveryStateSent);
    XCTAssertEqual(fileMessage.fileMessageData.transferState, AssetTransferStateUploaded);
    XCTAssertEqualObjects(fileMessage.fileMessageData.filename.stringByDeletingPathExtension, @"video");
    XCTAssertEqualObjects(fileMessage.fileMessageData.filename.pathExtension, @"mp4");

    NSError *error = nil;
    NSUInteger size = [NSFileManager.defaultManager attributesOfItemAtPath:fileURL.path error:&error].fileSize;

    XCTAssertNil(error);
    XCTAssertEqual(fileMessage.fileMessageData.size, size);
}

- (void)testThatItResendsAFailedFileMessage_UploadingFullAssetFails_V3
{
    //given
    XCTAssertTrue([self login]);

    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    XCTAssertNotNil(conversation);
    XCTAssertEqual(conversation.allMessages.count, 1lu);

    NSURL *fileURL = self.testVideoFileURL;
    __block NSUInteger assetUploadCounter = 0;

    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request) {
        // We fail the second post to `/assets/v3`, which is the upload of the full asset
        if ([request.path isEqualToString:@"/assets/v3"] && ++assetUploadCounter == 2) {
            return [ZMTransportResponse responseWithPayload:nil HTTPStatus:400 transportSessionError:nil];
        }
        return nil;
    };

    // when
    __block ZMMessage *fileMessage;
    [self.userSession performChanges:^{
        ZMVideoMetadata *metadata = [[ZMVideoMetadata alloc] initWithFileURL:fileURL thumbnail:self.mediumJPEGData];
        fileMessage = (id)[conversation appendMessageWithFileMetadata:metadata];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertEqual(fileMessage.deliveryState, ZMDeliveryStateFailedToSend);
    XCTAssertEqual(fileMessage.fileMessageData.transferState, AssetTransferStateUploadingFailed);

    // and when
    self.mockTransportSession.responseGeneratorBlock = nil;
    [self.userSession performChanges:^{
        [fileMessage resend];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    //then
    XCTAssertEqual(fileMessage.deliveryState, ZMDeliveryStateSent);
    XCTAssertEqual(fileMessage.fileMessageData.transferState, AssetTransferStateUploaded);
    XCTAssertEqualObjects(fileMessage.fileMessageData.filename.stringByDeletingPathExtension, @"video");
    XCTAssertEqualObjects(fileMessage.fileMessageData.filename.pathExtension, @"mp4");

    NSError *error = nil;
    NSUInteger size = [NSFileManager.defaultManager attributesOfItemAtPath:fileURL.path error:&error].fileSize;

    XCTAssertNil(error);
    XCTAssertEqual(fileMessage.fileMessageData.size, size);
}

- (void)testThatItResendsAFailedFileMessage_UploadingFullAssetGenericMessageFails_V3
{
    //given
    XCTAssertTrue([self login]);

    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    XCTAssertNotNil(conversation);
    XCTAssertEqual(conversation.allMessages.count, 1lu);

    NSURL *fileURL = self.testVideoFileURL;
    NSString *genericMessagePath = [NSString stringWithFormat:@"/conversations/%@/otr/messages", conversation.remoteIdentifier.transportString];

    __block NSUInteger genericMessageUploadCount = 0;

    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request) {
        // We fail the post to `/otr/messages`, which is the upload of the full asset generic message
        if ([request.path isEqualToString:genericMessagePath] && ++genericMessageUploadCount == 1) {
            return [ZMTransportResponse responseWithPayload:nil HTTPStatus:400 transportSessionError:nil];
        }
        return nil;
    };

    // when
    __block ZMMessage *fileMessage;
    [self.userSession performChanges:^{
        ZMVideoMetadata *metadata = [[ZMVideoMetadata alloc] initWithFileURL:fileURL thumbnail:self.mediumJPEGData];
        fileMessage = (id)[conversation appendMessageWithFileMetadata:metadata];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertEqual(fileMessage.deliveryState, ZMDeliveryStateFailedToSend);
    XCTAssertEqual(fileMessage.fileMessageData.transferState, AssetTransferStateUploaded);

    // and when
    self.mockTransportSession.responseGeneratorBlock = nil;
    [self.userSession performChanges:^{
        [fileMessage resend];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    //then
    XCTAssertEqual(fileMessage.deliveryState, ZMDeliveryStateSent);
    XCTAssertEqual(fileMessage.fileMessageData.transferState, AssetTransferStateUploaded);
    XCTAssertEqualObjects(fileMessage.fileMessageData.filename.stringByDeletingPathExtension, @"video");
    XCTAssertEqualObjects(fileMessage.fileMessageData.filename.pathExtension, @"mp4");

    NSError *error = nil;
    NSUInteger size = [NSFileManager.defaultManager attributesOfItemAtPath:fileURL.path error:&error].fileSize;

    XCTAssertNil(error);
    XCTAssertEqual(fileMessage.fileMessageData.size, size);

}

- (void)testThatItDoesReuploadTheAssetMetadataAfterReceivingA_412_MissingClients_WithVideo_V3
{
    //given
    XCTAssertTrue([self login]);


    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    XCTAssertEqual(conversation.allMessages.count, 1lu);

    NSURL *fileURL = self.testVideoFileURL;
    NSString *conversationIDString = conversation.remoteIdentifier.transportString;
    NSString *expectedMessageAddPath = [NSString stringWithFormat:@"/conversations/%@/otr/messages", conversationIDString];
    NSString *expectedAssetAddPath = @"/assets/v3";
    NSString *expectedFetchUserClientPath = [NSString stringWithFormat:@"/users/%@/clients/%@", self.user1.identifier, [(MockUserClient *)self.user1.clients.anyObject identifier]];

    // when
    __block ZMMessage *fileMessage;

    [self.mockTransportSession resetReceivedRequests];
    [self.userSession performChanges:^{
        ZMVideoMetadata *metadata = [[ZMVideoMetadata alloc] initWithFileURL:fileURL thumbnail:self.mediumJPEGData];
        fileMessage = (id)[conversation appendMessageWithFileMetadata:metadata];
    }];

    WaitForAllGroupsToBeEmpty(0.5);

    //then
    XCTAssertEqual(fileMessage.deliveryState, ZMDeliveryStateSent);
    XCTAssertEqual(fileMessage.fileMessageData.transferState, AssetTransferStateUploaded);

    NSArray <ZMTransportRequest *> *requests = [self filterOutRequestsForLastRead:self.mockTransportSession.receivedRequests];

    // Preview upload, Asset upload, generic message, Prekeys, fetch client, generic message
    XCTAssertEqual(requests.count, 6lu);
    if (requests.count < 6) {
        return;
    }

    ZMTransportRequest *thumbnailUploadRequest = requests[0];
    ZMTransportRequest *fullAssetUploadRequest = requests[1];
    ZMTransportRequest *firstAssetMessageRequest = requests[2];
    ZMTransportRequest *missingPrekeysRequest = requests[3];
    ZMTransportRequest *fetchUserClientRequest = requests[4];
    ZMTransportRequest *secondAssetMessageRequest = requests[5];
    
    XCTAssertEqualObjects(thumbnailUploadRequest.path, expectedAssetAddPath);
    XCTAssertEqualObjects(fullAssetUploadRequest.path, expectedAssetAddPath);
    XCTAssertEqualObjects(firstAssetMessageRequest.path, expectedMessageAddPath);
    XCTAssertEqualObjects(missingPrekeysRequest.path, @"/users/prekeys");
    XCTAssertEqualObjects(fetchUserClientRequest.path, expectedFetchUserClientPath);
    XCTAssertEqualObjects(secondAssetMessageRequest.path, expectedMessageAddPath);
    
    XCTAssertEqual(conversation.allMessages.count, 2lu);
    ZMMessage *message = conversation.lastMessage;
    XCTAssertNotNil(message.fileMessageData);
    XCTAssertNil(message.imageMessageData);
}

- (void)testThatItSendsARegularFileMessageForAFileWithVideoButNilThumbnail_V3
{
    //given
    XCTAssertTrue([self login]);

    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    XCTAssertNotNil(conversation);
    XCTAssertEqual(conversation.allMessages.count, 1lu);

    [self prefetchRemoteClientByInsertingMessageInConversation:self.selfToUser1Conversation];

    NSURL *fileURL = self.testVideoFileURL; // Video URL
    NSString *expectedMessageAddPath = [NSString stringWithFormat:@"/conversations/%@/otr/messages", conversation.remoteIdentifier.transportString];
    NSString *expectedAssetAddPath = @"/assets/v3";

    // when
    [self.mockTransportSession resetReceivedRequests];

    __block ZMMessage *fileMessage;
    [self.userSession performChanges:^{
        ZMVideoMetadata *metadata = [[ZMVideoMetadata alloc] initWithFileURL:fileURL thumbnail:nil]; // No thumbnail
        fileMessage = (id)[conversation appendMessageWithFileMetadata:metadata];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertEqual(fileMessage.deliveryState, ZMDeliveryStateSent);
    XCTAssertEqual(fileMessage.fileMessageData.transferState, AssetTransferStateUploaded);

    NSArray <ZMTransportRequest *> *requests = [self filterOutRequestsForLastRead:self.mockTransportSession.receivedRequests];
    XCTAssertEqual(requests.count, 2lu); // Asset.Uploaded asset upload & Asset.Uploaded generic message

    ZMTransportRequest *uploadAssetRequest = requests[0];
    ZMTransportRequest *uploadMessageRequest = requests[1];

    XCTAssertEqualObjects(uploadAssetRequest.path, expectedAssetAddPath);
    XCTAssertEqualObjects(uploadMessageRequest.path, expectedMessageAddPath);

    ZMMessage *message = conversation.lastMessage;

    XCTAssertNotNil(message.fileMessageData);
    XCTAssertNil(message.imageMessageData);
    XCTAssertEqualObjects(message.fileMessageData.filename.stringByDeletingPathExtension, @"video");
    XCTAssertEqualObjects(message.fileMessageData.filename.pathExtension, @"mp4");

    NSError *error = nil;
    NSUInteger size = [NSFileManager.defaultManager attributesOfItemAtPath:fileURL.path error:&error].fileSize;

    XCTAssertNil(error);
    XCTAssertEqual(message.fileMessageData.size, size);
    
}

#pragma mark Downloading

- (void)testThatItSendsTheRequestToDownloadAFileWhenItHasTheAssetID_AndSetsTheStateTo_Downloaded_AfterSuccesfullDecryption_V3
{
    // given
    XCTAssertTrue([self login]);

    NSUUID *nonce = NSUUID.createUUID;
    NSUUID *assetID = NSUUID.createUUID;
    NSData *otrKey = NSData.randomEncryptionKey;

    NSData *assetData = [NSData secureRandomDataOfLength:256];
    NSData *encryptedAsset = [assetData zmEncryptPrefixingPlainTextIVWithKey:otrKey];
    NSData *sha256 = encryptedAsset.zmSHA256Digest;

    ZMGenericMessage *uploaded = [[ZMGenericMessage messageWithContent:[ZMAsset assetWithUploadedOTRKey:otrKey sha256:sha256] nonce:nonce] updatedUploadedWithAssetId:assetID.transportString token:nil];

    // when
    ZMAssetClientMessage *message = [self remotelyInsertAssetOriginalAndUpdate:uploaded insertBlock:
                                     ^(__unused NSData *data, MockConversation *conversation, MockUserClient *from, MockUserClient *to) {
                                         [conversation insertOTRMessageFromClient:from toClient:to data:data];
                                     } nonce:nonce];
    WaitForAllGroupsToBeEmpty(0.5);
    __unused ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];

    // then
    XCTAssertNotNil(message);
    XCTAssertNil(message.assetId); // We do not store the asset ID in the DB for v3 assets
    XCTAssertEqualObjects(message.nonce, nonce);
    XCTAssertEqual(message.transferState, AssetTransferStateUploaded);
    WaitForAllGroupsToBeEmpty(0.5);

    // when
    // Mock the asset/v3 request
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request) {
        NSString *expectedPath = [NSString stringWithFormat:@"/assets/v3/%@", assetID.transportString];
        if ([request.path isEqualToString:expectedPath]) {
            return [[ZMTransportResponse alloc] initWithImageData:encryptedAsset HTTPStatus:200 transportSessionError:nil headers:nil];
        }
        return nil;
    };

    // when we request the file download
    [self.mockTransportSession resetReceivedRequests];
    [self.userSession performChanges:^{
        [message requestFileDownload];
    }];

    WaitForAllGroupsToBeEmpty(0.5);

    // then
    ZMTransportRequest *lastRequest = self.mockTransportSession.receivedRequests.lastObject;
    NSString *expectedPath = [NSString stringWithFormat:@"/assets/v3/%@", assetID.transportString];
    XCTAssertEqualObjects(lastRequest.path, expectedPath);
    XCTAssertEqual(message.transferState, AssetTransferStateUploaded);
    
}

- (void)testThatItSendsTheRequestToDownloadAFileWhenItHasTheAssetID_AndSetsTheStateTo_FailedDownload_AfterFailedDecryption_V3
{
    // given
    XCTAssertTrue([self login]);

    NSUUID *nonce = NSUUID.createUUID;
    NSUUID *assetID = NSUUID.createUUID;
    NSData *otrKey = NSData.randomEncryptionKey;

    NSData *assetData = [NSData secureRandomDataOfLength:256];
    NSData *encryptedAsset = [assetData zmEncryptPrefixingPlainTextIVWithKey:otrKey];
    NSData *sha256 = encryptedAsset.zmSHA256Digest;

    ZMGenericMessage *uploaded = [[ZMGenericMessage messageWithContent:[ZMAsset assetWithUploadedOTRKey:otrKey sha256:sha256] nonce:nonce] updatedUploadedWithAssetId:assetID.transportString token:nil];

    // when
    ZMAssetClientMessage *message = [self remotelyInsertAssetOriginalAndUpdate:uploaded insertBlock:
                                     ^(__unused NSData *data, MockConversation *conversation, MockUserClient *from, MockUserClient *to) {
                                         [conversation insertOTRMessageFromClient:from toClient:to data:data];
                                     } nonce:nonce];
    WaitForAllGroupsToBeEmpty(0.5);
    __unused ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];

    // then
    XCTAssertNotNil(message);
    XCTAssertNil(message.assetId); // We do not store the asset ID in the DB for v3 assets
    XCTAssertEqualObjects(message.nonce, nonce);
    XCTAssertEqual(message.transferState, AssetTransferStateUploaded);
    WaitForAllGroupsToBeEmpty(0.5);

    // when
    // Mock the asset/v3 request
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request) {
        NSString *expectedPath = [NSString stringWithFormat:@"/assets/v3/%@", assetID.transportString];
        if ([request.path isEqualToString:expectedPath]) {
            NSData *wrongData = [NSData secureRandomDataOfLength:128];
            return [[ZMTransportResponse alloc] initWithImageData:wrongData HTTPStatus:200 transportSessionError:nil headers:nil];
        }
        return nil;
    };

    // We log an error when we fail to decrypt the received data
    [self performIgnoringZMLogError:^{
        [self.userSession performChanges:^{
            [message requestFileDownload];
        }];

        WaitForAllGroupsToBeEmpty(0.5);
    }];

    // then
    ZMTransportRequest *lastRequest = self.mockTransportSession.receivedRequests.lastObject;
    NSString *expectedPath = [NSString stringWithFormat:@"/assets/v3/%@", assetID.transportString];
    XCTAssertEqualObjects(lastRequest.path, expectedPath);
    XCTAssertEqual(message.downloadState, AssetDownloadStateRemote);
}

@end
