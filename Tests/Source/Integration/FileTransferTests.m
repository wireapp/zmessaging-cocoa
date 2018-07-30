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

- (NSArray *)filterOutRequestsForLastRead:(NSArray *)requests
{
    NSString *conversationPrefix = [NSString stringWithFormat:@"/conversations/%@/otr/messages",  [ZMConversation selfConversationInContext:self.userSession.managedObjectContext].remoteIdentifier.transportString];
    return [requests filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id  obj, NSDictionary __unused *bindings) {
        return ![((ZMTransportRequest *)obj).path hasPrefix:conversationPrefix];
    }]];
}

- (void)testThatItSendsATextMessageAfterAFileMessage
{
    //given
    XCTAssertTrue([self login]);
    
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    XCTAssertNotNil(conversation);
    XCTAssertEqual(conversation.messages.count, 1lu);
    
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
    XCTAssertEqual(fileMessage.fileMessageData.transferState, ZMFileTransferStateDownloaded);
    XCTAssertEqual(textMessage.deliveryState, ZMDeliveryStateSent);
    XCTAssertEqual(conversation.messages.count, 3lu);
}

#pragma mark Receiving

- (void)testThatItReceivesAVideoFileMessageThumbnailSentRemotely
{
    // given
    XCTAssertTrue([self login]);
    
    NSUUID *nonce = NSUUID.createUUID;
    NSUUID *thumbnailAssetID = NSUUID.createUUID;
    NSString *thumbnailIDString = thumbnailAssetID.transportString;
    NSData *otrKey = NSData.randomEncryptionKey;
    NSData *encryptedAsset = [self.mediumJPEGData zmEncryptPrefixingPlainTextIVWithKey:otrKey];
    NSData *sha256 = encryptedAsset.zmSHA256Digest;
    
    ZMAssetRemoteData *remote = [ZMAssetRemoteData remoteDataWithOTRKey:otrKey sha256:sha256 assetId:nil assetToken:nil];
    ZMAssetImageMetaData *image = [ZMAssetImageMetaData imageMetaDataWithWidth:1024 height:2048];
    ZMAssetPreview *preview = [ZMAssetPreview previewWithSize:256 mimeType:@"image/jpeg" remoteData:remote imageMetaData:image];
    ZMAsset *asset = [ZMAsset assetWithOriginal:nil preview:preview];
    ZMGenericMessage *updateMessage = [ZMGenericMessage genericMessageWithAsset:asset messageID:nonce expiresAfter:nil];
    
    
    // when
    __block MessageChangeObserver *observer;
    __block ZMConversation *conversation;
    
    id insertBlock = ^(NSData *data, MockConversation *mockConversation, MockUserClient *from, MockUserClient *to) {
        [mockConversation insertOTRAssetFromClient:from toClient:to metaData:data imageData:nil assetId:thumbnailAssetID isInline:NO];
        conversation = [self conversationForMockConversation:mockConversation];
        observer = [[MessageChangeObserver alloc] initWithMessage:conversation.messages.lastObject];
    };
    
    ZMAssetClientMessage *message = [self remotelyInsertAssetOriginalWithMimeType:@"video/mp4"
                                                                updateWithMessage:updateMessage
                                                                      insertBlock:insertBlock
                                                                            nonce:nonce
                                                                      isEphemeral:NO];
    
    // insert the thumbnail asset remotely
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [session createAssetWithData:encryptedAsset
                          identifier:thumbnailIDString
                         contentType:@"image/jpeg"
                     forConversation:conversation.remoteIdentifier.transportString];
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertNotNil(message);
    XCTAssertNotNil(observer);
    XCTAssertNotNil(conversation);

    // when
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
    XCTAssertEqual(message.transferState, ZMFileTransferStateUploading);

}

- (void)testThatAFileUpload_AssetOriginal_MessageIsReceivedWhenSentRemotely
{
    //given
    XCTAssertTrue([self login]);
    
    NSUUID *nonce = NSUUID.createUUID;
    ZMGenericMessage *original = [ZMGenericMessage genericMessageWithAssetSize:256
                                                                      mimeType:@"text/plain"
                                                                          name:@"foo228"
                                                                     messageID:nonce
                                                                  expiresAfter:nil];


    // when
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> * __unused session) {
        [self.selfToUser1Conversation encryptAndInsertDataFromClient:self.user1.clients.anyObject
                                                            toClient:self.selfUser.clients.anyObject
                                                                data:original.data];
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    XCTAssertEqual(conversation.messages.count, 2lu);
    
    if (! [conversation.messages.lastObject isKindOfClass:ZMAssetClientMessage.class]) {
        return XCTFail(@"Unexpected message type, expected ZMAssetClientMessage : %@", [conversation.messages.lastObject class]);
    }
    
    ZMAssetClientMessage *message = (ZMAssetClientMessage *)conversation.messages.lastObject;
    XCTAssertEqual(message.size, 256lu);
    XCTAssertEqualObjects(message.mimeType, @"text/plain");
    XCTAssertEqualObjects(message.filename, @"foo228");
    XCTAssertEqualObjects(message.nonce, nonce);
    XCTAssertNil(message.assetId);
    XCTAssertEqual(message.transferState, ZMFileTransferStateUploading);
}

- (void)testThatAFileUpload_AssetUploaded_MessageIsReceivedAndUpdatesTheOriginalMessageWhenSentRemotely
{
    //given
    XCTAssertTrue([self login]);
    
    NSUUID *nonce = NSUUID.createUUID;
    NSUUID *assetID = NSUUID.createUUID;
    NSData *otrKey = NSData.randomEncryptionKey;
    NSData *sha256 = NSData.zmRandomSHA256Key;
    ZMGenericMessage *uploaded = [ZMGenericMessage genericMessageWithUploadedOTRKey:otrKey sha256:sha256 messageID:nonce expiresAfter:nil];
    
    // when
    ZMAssetClientMessage *message = [self remotelyInsertAssetOriginalAndUpdate:uploaded insertBlock:
                                     ^(NSData *data, MockConversation *conversation, MockUserClient *from, MockUserClient *to) {
                                         [conversation insertOTRAssetFromClient:from toClient:to metaData:data imageData:nil assetId:assetID isInline:NO];
                                     } nonce:nonce];
    
    // then
    XCTAssertEqualObjects(message.assetId, assetID); // We should have received an asset ID to be able to download the file
    XCTAssertEqualObjects(message.nonce, nonce);
    XCTAssertEqual(message.transferState, ZMFileTransferStateUploaded);
}

- (void)testThatItDeletesAFileMessageWhenTheUploadIsCancelledRemotely
{
    //given
    XCTAssertTrue([self login]);
    
    NSUUID *nonce = NSUUID.createUUID;
    ZMGenericMessage *cancelled = [ZMGenericMessage genericMessageWithNotUploaded:ZMAssetNotUploadedCANCELLED messageID:nonce expiresAfter:nil];
    
    // when
    ZMAssetClientMessage *message = [self remotelyInsertAssetOriginalAndUpdate:cancelled insertBlock:
                                     ^(NSData *data, MockConversation *conversation, MockUserClient *from, MockUserClient *to) {
                                         [conversation insertOTRMessageFromClient:from toClient:to data:data];
                                     } nonce:nonce];
    
    // then
    XCTAssertTrue(message.isZombieObject);
}

- (void)testThatItUpdatesAFileMessageWhenTheUploadFailsRemotely
{
    //given
    XCTAssertTrue([self login]);
    
    NSUUID *nonce = NSUUID.createUUID;
    ZMGenericMessage *failed = [ZMGenericMessage genericMessageWithNotUploaded:ZMAssetNotUploadedFAILED messageID:nonce expiresAfter:nil];
    
    // when
    ZMAssetClientMessage *message = [self remotelyInsertAssetOriginalAndUpdate:failed insertBlock:
                                     ^(NSData *data, MockConversation *conversation, MockUserClient *from, MockUserClient *to) {
                                         [conversation insertOTRMessageFromClient:from toClient:to data:data];
                                     } nonce:nonce];
    
    // then
    XCTAssertNil(message.assetId);
    // As soon as we delete the message on cancelation we can remove this check
    // and assert the absence of the message instead
    XCTAssertEqual(message.transferState, ZMFileTransferStateFailedUpload);
}

#pragma mark Downloading

- (void)testThatItSendsTheRequestToDownloadAFileWhenItHasTheAssetID_AndSetsTheStateTo_Downloaded_AfterSuccesfullDecryption
{
    //given
    XCTAssertTrue([self login]);
    
    NSUUID *nonce = NSUUID.createUUID;
    NSUUID *assetID = NSUUID.createUUID;
    NSData *otrKey = NSData.randomEncryptionKey;
    
    NSData *assetData = [NSData secureRandomDataOfLength:256];
    NSData *encryptedAsset = [assetData zmEncryptPrefixingPlainTextIVWithKey:otrKey];
    NSData *sha256 = encryptedAsset.zmSHA256Digest;
    
    ZMGenericMessage *uploaded = [ZMGenericMessage genericMessageWithUploadedOTRKey:otrKey sha256:sha256 messageID:nonce expiresAfter:nil];
    
    // when
    ZMAssetClientMessage *message = [self remotelyInsertAssetOriginalAndUpdate:uploaded insertBlock:
                                     ^(NSData *data, MockConversation *conversation, MockUserClient *from, MockUserClient *to) {
                                         [conversation insertOTRAssetFromClient:from toClient:to metaData:data imageData:assetData assetId:assetID isInline:NO];
                                     } nonce:nonce];
    WaitForAllGroupsToBeEmpty(0.5);
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    
    // creating the asset remotely
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [session createAssetWithData:encryptedAsset
                          identifier:assetID.transportString
                         contentType:@"text/plain"
                     forConversation:conversation.remoteIdentifier.transportString];
    }];
    
    // then
    XCTAssertEqualObjects(message.assetId, assetID); // We should have received an asset ID to be able to download the file
    XCTAssertEqualObjects(message.nonce, nonce);
    XCTAssertEqual(message.transferState, ZMFileTransferStateUploaded);
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    [self.mockTransportSession resetReceivedRequests];
    [self.userSession performChanges:^{
        [message requestFileDownload];
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    ZMTransportRequest *lastRequest = self.mockTransportSession.receivedRequests.lastObject;
    NSString *expectedPath = [NSString stringWithFormat:@"/conversations/%@/otr/assets/%@", conversation.remoteIdentifier.transportString, message.assetId.transportString];
    XCTAssertEqualObjects(lastRequest.path, expectedPath);
    XCTAssertEqualObjects(lastRequest.methodAsString, @"GET");
    XCTAssertEqual(message.transferState, ZMFileTransferStateDownloaded);
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
    
    ZMGenericMessage *uploaded = [ZMGenericMessage genericMessageWithUploadedOTRKey:otrKey sha256:sha256 messageID:nonce expiresAfter:nil];
    
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
    
    // then
    XCTAssertEqualObjects(message.assetId, assetID); // We should have received an asset ID to be able to download the file
    XCTAssertEqualObjects(message.nonce, nonce);
    XCTAssertEqual(message.transferState, ZMFileTransferStateUploaded);
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
    XCTAssertEqual(message.transferState, ZMFileTransferStateFailedDownload);
}

#pragma mark Helper

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
    
    ZMGenericMessage *original = [ZMGenericMessage genericMessageWithAssetSize:256
                                                                      mimeType:mimeType
                                                                          name:@"foo229"
                                                                     messageID:nonce
                                                                  expiresAfter:isEphemeral ? @20 : nil];
    
    // when
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *__unused session) {
        [mockConversation encryptAndInsertDataFromClient:senderClient toClient:selfClient data:original.data];
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
    
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    XCTAssertEqual(conversation.messages.count, 2lu);
    
    if (! [conversation.messages.lastObject isKindOfClass:ZMAssetClientMessage.class]) {
        XCTFail(@"Unexpected message type, expected ZMAssetClientMessage : %@", [conversation.messages.lastObject class]);
        return nil;
    }
    
    ZMAssetClientMessage *message = (ZMAssetClientMessage *)conversation.messages.lastObject;
    XCTAssertEqual(message.size, 256lu);
    XCTAssertEqualObjects(message.mimeType, mimeType);
    XCTAssertEqualObjects(message.filename, @"foo229");
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

@end


@implementation FileTransferTests (Ephemeral)

- (void)testThatItSendsAFileMessage_WithVideo_Ephemeral
{
    //given
    XCTAssertTrue([self login]);
    
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    conversation.localMessageDestructionTimeout = 10;
    XCTAssertNotNil(conversation);
    XCTAssertEqual(conversation.messages.count, 1lu);
    
    [self prefetchRemoteClientByInsertingMessageInConversation:self.selfToUser1Conversation];
    NSUInteger initialMessageCount = conversation.messages.count;
    
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
    XCTAssertEqual(fileMessage.fileMessageData.transferState, ZMFileTransferStateDownloaded);
    
    NSArray <ZMTransportRequest *> *requests = [self filterOutRequestsForLastRead:self.mockTransportSession.receivedRequests];
    

    if (5 != requests.count) {
        return XCTFail(@"Wrong number of requests");
    }

    XCTAssertEqualObjects(requests[0].path, expectedMessageAddPath);    // /otr/messages    (Only Asset.Original)
    XCTAssertEqualObjects(requests[1].path, expectedAssetUploadPath);   // /assets/v3       (Preview)
    XCTAssertEqualObjects(requests[2].path, expectedMessageAddPath);    // /otr.messages    (Including Asset.Preview)
    XCTAssertEqualObjects(requests[3].path, expectedAssetUploadPath);   // /assets/v3       (Medium)
    XCTAssertEqualObjects(requests[4].path, expectedMessageAddPath);    // /otr.messages    (Including Uploaded)

    XCTAssertEqual(conversation.messages.count - initialMessageCount, 1lu);
    
    ZMMessage *message = conversation.messages.lastObject;
    
    XCTAssertNotNil(message.fileMessageData);
    XCTAssertNil(message.imageMessageData);
    XCTAssertEqualObjects(message.fileMessageData.filename.stringByDeletingPathExtension, @"video");
    XCTAssertEqualObjects(message.fileMessageData.filename.pathExtension, @"mp4");
    
    NSError *error = nil;
    NSUInteger size = [NSFileManager.defaultManager attributesOfItemAtPath:fileURL.path error:&error].fileSize;
    
    XCTAssertNil(error);
    XCTAssertEqual(message.fileMessageData.size, size);
}

- (void)testThatAFileUpload_AssetOriginal_MessageIsReceivedWhenSentRemotely_Ephemeral
{
    //given
    XCTAssertTrue([self login]);
    
    [self establishSessionWithMockUser:self.user1];
    WaitForAllGroupsToBeEmpty(0.5);

    NSUUID *nonce = NSUUID.createUUID;
    ZMGenericMessage *original = [ZMGenericMessage genericMessageWithAssetSize:256
                                                                      mimeType:@"text/plain"
                                                                          name:self.name
                                                                     messageID:nonce
                                                                  expiresAfter:@30];
    
    // when
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> * __unused session) {
        [self.selfToUser1Conversation encryptAndInsertDataFromClient:self.user1.clients.anyObject
                                                            toClient:self.selfUser.clients.anyObject
                                                                data:original.data];
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    XCTAssertEqual(conversation.messages.count, 2lu);
    
    if (! [conversation.messages.lastObject isKindOfClass:ZMAssetClientMessage.class]) {
        return XCTFail(@"Unexpected message type, expected ZMAssetClientMessage : %@", [conversation.messages.lastObject class]);
    }
    
    ZMAssetClientMessage *message = (ZMAssetClientMessage *)conversation.messages.lastObject;
    XCTAssertTrue(message.isEphemeral);

    XCTAssertEqual(message.size, 256lu);
    XCTAssertEqualObjects(message.mimeType, @"text/plain");
    XCTAssertEqualObjects(message.filename, self.name);
    XCTAssertEqualObjects(message.nonce, nonce);
    XCTAssertNil(message.assetId);
    XCTAssertEqual(message.transferState, ZMFileTransferStateUploading);
}

- (void)testThatAFileUpload_AssetUploaded_MessageIsReceivedAndUpdatesTheOriginalMessageWhenSentRemotely_Ephemeral
{
    //given
    XCTAssertTrue([self login]);
    
    NSUUID *nonce = NSUUID.createUUID;
    NSUUID *assetID = NSUUID.createUUID;
    NSData *otrKey = NSData.randomEncryptionKey;
    NSData *sha256 = NSData.zmRandomSHA256Key;
    ZMGenericMessage *uploaded = [ZMGenericMessage genericMessageWithUploadedOTRKey:otrKey sha256:sha256 messageID:nonce expiresAfter:@30];
    
    // when
    ZMAssetClientMessage *message = [self remotelyInsertAssetOriginalAndUpdate:uploaded insertBlock:
                                     ^(NSData *data, MockConversation *conversation, MockUserClient *from, MockUserClient *to) {
                                         [conversation insertOTRAssetFromClient:from toClient:to metaData:data imageData:nil assetId:assetID isInline:NO];
                                     } nonce:nonce];
    XCTAssertTrue(message.isEphemeral);

    // then
    XCTAssertEqualObjects(message.assetId, assetID); // We should have received an asset ID to be able to download the file
    XCTAssertEqualObjects(message.nonce, nonce);
    XCTAssertEqual(message.transferState, ZMFileTransferStateUploaded);
    XCTAssertTrue(message.isEphemeral);
}

- (void)testThatItDeletesAFileMessageWhenTheUploadIsCancelledRemotely_Ephemeral
{
    //given
    XCTAssertTrue([self login]);
    
    NSUUID *nonce = NSUUID.createUUID;
    ZMGenericMessage *cancelled = [ZMGenericMessage genericMessageWithNotUploaded:ZMAssetNotUploadedCANCELLED messageID:nonce  expiresAfter:@30];
    
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
    ZMGenericMessage *failed = [ZMGenericMessage genericMessageWithNotUploaded:ZMAssetNotUploadedFAILED messageID:nonce expiresAfter:@30];
    
    // when
    ZMAssetClientMessage *message = [self remotelyInsertAssetOriginalAndUpdate:failed insertBlock:
                                     ^(NSData *data, MockConversation *conversation, MockUserClient *from, MockUserClient *to) {
                                         [conversation insertOTRMessageFromClient:from toClient:to data:data];
                                     } nonce:nonce];
    XCTAssertTrue(message.isEphemeral);

    // then
    XCTAssertNil(message.assetId);
    // As soon as we delete the message on cancelation we can remove this check
    // and assert the absence of the message instead
    XCTAssertEqual(message.transferState, ZMFileTransferStateFailedUpload);
    XCTAssertTrue(message.isEphemeral);
}

- (void)testThatItReceivesAVideoFileMessageThumbnailSentRemotely_Ephemeral
{
    // given
    XCTAssertTrue([self login]);
    
    NSUUID *nonce = NSUUID.createUUID;
    NSUUID *thumbnailAssetID = NSUUID.createUUID;
    NSString *thumbnailIDString = thumbnailAssetID.transportString;
    NSData *otrKey = NSData.randomEncryptionKey;
    NSData *encryptedAsset = [self.mediumJPEGData zmEncryptPrefixingPlainTextIVWithKey:otrKey];
    NSData *sha256 = encryptedAsset.zmSHA256Digest;
    
    ZMAssetRemoteData *remote = [ZMAssetRemoteData remoteDataWithOTRKey:otrKey sha256:sha256 assetId:nil assetToken:nil];
    ZMAssetImageMetaData *image = [ZMAssetImageMetaData imageMetaDataWithWidth:1024 height:2048];
    ZMAssetPreview *preview = [ZMAssetPreview previewWithSize:256 mimeType:@"image/jpeg" remoteData:remote imageMetaData:image];
    ZMAsset *asset = [ZMAsset assetWithOriginal:nil preview:preview];
    ZMGenericMessage *updateMessage = [ZMGenericMessage genericMessageWithAsset:asset messageID:nonce expiresAfter:@30];
    
    
    // when
    __block MessageChangeObserver *observer;
    __block ZMConversation *conversation;
    
    id insertBlock = ^(NSData *data, MockConversation *mockConversation, MockUserClient *from, MockUserClient *to) {
        [mockConversation insertOTRAssetFromClient:from toClient:to metaData:data imageData:nil assetId:thumbnailAssetID isInline:NO];
        conversation = [self conversationForMockConversation:mockConversation];
        observer = [[MessageChangeObserver alloc] initWithMessage:conversation.messages.lastObject];
    };
    
    ZMAssetClientMessage *message = [self remotelyInsertAssetOriginalWithMimeType:@"video/mp4"
                                                                updateWithMessage:updateMessage
                                                                      insertBlock:insertBlock
                                                                            nonce:nonce
                                                                      isEphemeral:YES];
    XCTAssertTrue(message.isEphemeral);
    
    // insert the thumbnail asset remotely
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [session createAssetWithData:encryptedAsset
                          identifier:thumbnailIDString
                         contentType:@"image/jpeg"
                     forConversation:conversation.remoteIdentifier.transportString];
    }];
    
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
    XCTAssertEqual(message.transferState, ZMFileTransferStateUploading);
    XCTAssertTrue(message.isEphemeral);

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
    
    ZMGenericMessage *uploaded = [ZMGenericMessage genericMessageWithUploadedOTRKey:otrKey sha256:sha256 messageID:nonce expiresAfter:@30];
    
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
    
    // then
    XCTAssertEqualObjects(message.assetId, assetID); // We should have received an asset ID to be able to download the file
    XCTAssertEqualObjects(message.nonce, nonce);
    XCTAssertEqual(message.transferState, ZMFileTransferStateUploaded);
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
    XCTAssertEqual(message.transferState, ZMFileTransferStateFailedDownload);
    XCTAssertTrue(message.isEphemeral);
}

@end


#pragma mark - Asset V3
#pragma mark - Receiving

@implementation FileTransferTests (V3)

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
    ZMAssetPreview *preview = [ZMAssetPreview previewWithSize:256 mimeType:@"image/jpeg" remoteData:remote imageMetaData:image];
    ZMAsset *asset = [ZMAsset assetWithOriginal:nil preview:preview];
    ZMGenericMessage *updateMessage = [ZMGenericMessage genericMessageWithAsset:asset messageID:nonce expiresAfter:nil];


    // when
    __block MessageChangeObserver *observer;
    __block ZMConversation *conversation;

    id insertBlock = ^(NSData *data, MockConversation *mockConversation, MockUserClient *from, MockUserClient *to) {
        [mockConversation insertOTRMessageFromClient:from toClient:to data:data];
        conversation = [self conversationForMockConversation:mockConversation];
        observer = [[MessageChangeObserver alloc] initWithMessage:conversation.messages.lastObject];
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
    XCTAssertEqual(message.transferState, ZMFileTransferStateUploading);
    
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
    ZMAssetPreview *preview = [ZMAssetPreview previewWithSize:256 mimeType:@"image/jpeg" remoteData:remote imageMetaData:image];
    ZMAsset *asset = [ZMAsset assetWithOriginal:nil preview:preview];
    ZMGenericMessage *updateMessage = [ZMGenericMessage genericMessageWithAsset:asset messageID:nonce expiresAfter:@20];

    // when
    __block MessageChangeObserver *observer;
    __block ZMConversation *conversation;

    id insertBlock = ^(NSData *data, MockConversation *mockConversation, MockUserClient *from, MockUserClient *to) {
        [mockConversation insertOTRMessageFromClient:from toClient:to data:data];
        conversation = [self conversationForMockConversation:mockConversation];
        observer = [[MessageChangeObserver alloc] initWithMessage:conversation.messages.lastObject];
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
    XCTAssertEqual(message.transferState, ZMFileTransferStateUploading);
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
    ZMGenericMessage *uploaded = [[ZMGenericMessage genericMessageWithUploadedOTRKey:otrKey sha256:sha256 messageID:nonce expiresAfter:nil] updatedUploadedWithAssetId:assetID.transportString token:nil];

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
    XCTAssertEqual(message.transferState, ZMFileTransferStateUploaded);
}

#pragma mark Sending

- (void)testThatItSendsAFileMessage_V3
{
    // given
    XCTAssertTrue([self login]);

    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    XCTAssertNotNil(conversation);
    XCTAssertEqual(conversation.messages.count, 1lu);
    [self prefetchRemoteClientByInsertingMessageInConversation:self.selfToUser1Conversation];
    NSUInteger initialMessageCount = conversation.messages.count;

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
    XCTAssertEqual(fileMessage.fileMessageData.transferState, ZMFileTransferStateDownloaded);

    NSArray <ZMTransportRequest *> *requests = [self filterOutRequestsForLastRead:self.mockTransportSession.receivedRequests];
    XCTAssertEqual(requests.count, 3lu); // Asset.Original, Asset Upload (v3), Asset.Uploaded message
    ZMTransportRequest *originalMessageRequest  = requests[0];
    ZMTransportRequest *fullAssetUploadRequest  = requests[1];
    ZMTransportRequest *fullAssetMessageRequest = requests[2];

    XCTAssertEqualObjects(originalMessageRequest.path, expectedMessageAddPath);
    XCTAssertEqualObjects(fullAssetMessageRequest.path, expectedMessageAddPath);
    XCTAssertEqualObjects(fullAssetUploadRequest.path, expectedAssetUploadPath);

    XCTAssertEqual(conversation.messages.count - initialMessageCount, 1lu);
    ZMMessage *message = conversation.messages.lastObject;

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

    XCTAssertEqual(conversation.messages.count, 1lu);
    [self prefetchRemoteClientByInsertingMessageInConversation:self.selfToUser1Conversation];
    NSUInteger initialMessageCount = conversation.messages.count;

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
    XCTAssertEqual(fileMessage.fileMessageData.transferState, ZMFileTransferStateDownloaded);

    NSArray <ZMTransportRequest *> *requests = [self filterOutRequestsForLastRead:self.mockTransportSession.receivedRequests];
    XCTAssertEqual(requests.count, 5lu); // Asset.Original, Thumbnail Upload, Asset.Preview, Full Asset Upload, Asset.Uploaded

    ZMTransportRequest *originalMessageRequest      = requests[0];
    ZMTransportRequest *thumbnailAssetUploadRequest = requests[1];
    ZMTransportRequest *thumbnailMessageRequest     = requests[2];
    ZMTransportRequest *fullAssetUploadRequest      = requests[3];
    ZMTransportRequest *fullAssetMessageRequest     = requests[4];

    XCTAssertEqualObjects(originalMessageRequest.path, expectedMessageAddPath);
    XCTAssertEqualObjects(thumbnailMessageRequest.path, expectedMessageAddPath);
    XCTAssertEqualObjects(fullAssetMessageRequest.path, expectedMessageAddPath);

    XCTAssertEqualObjects(thumbnailAssetUploadRequest.path, expectedAssetUploadPath);
    XCTAssertEqualObjects(fullAssetUploadRequest.path, expectedAssetUploadPath);

    XCTAssertEqual(conversation.messages.count - initialMessageCount, 1lu);
    ZMMessage *message = conversation.messages.lastObject;

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
    XCTAssertEqual(conversation.messages.count, 2lu);

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
    XCTAssertEqual(fileMessage.fileMessageData.transferState, ZMFileTransferStateFailedUpload);

    // and when
    self.mockTransportSession.responseGeneratorBlock = nil;
    [self.userSession performChanges:^{
        [fileMessage resend];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertEqual(fileMessage.deliveryState, ZMDeliveryStateSent);
    XCTAssertEqual(fileMessage.fileMessageData.transferState, ZMFileTransferStateDownloaded);
    
}

- (void)testThatItSendsATextMessageAfterAFileMessage_V3
{
    // given
    XCTAssertTrue([self login]);

    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    XCTAssertNotNil(conversation);
    XCTAssertEqual(conversation.messages.count, 1lu);

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
    XCTAssertEqual(fileMessage.fileMessageData.transferState, ZMFileTransferStateDownloaded);
    XCTAssertEqual(textMessage.deliveryState, ZMDeliveryStateSent);
    XCTAssertEqual(conversation.messages.count, 3lu);
    
}

- (void)testThatItDoesNotSendAFileWhenTheOriginalRequestFails_V3
{
    // given
    XCTAssertTrue([self login]);

    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    XCTAssertNotNil(conversation);
    XCTAssertEqual(conversation.messages.count, 1lu);

    NSURL *fileURL = [self createTestFile:@"foo22"];
    NSString *expectedMessageAddPath = [NSString stringWithFormat:@"/conversations/%@/otr/messages", conversation.remoteIdentifier.transportString];

    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request) {
        if ([request.path isEqualToString:expectedMessageAddPath]) {
            return [ZMTransportResponse responseWithPayload:nil HTTPStatus:401 transportSessionError:nil];
        }
        return nil;
    };

    // when
    [self.mockTransportSession resetReceivedRequests];

    __block ZMMessage *fileMessage;
    [self.userSession performChanges:^{
        fileMessage = (id)[conversation appendMessageWithFileMetadata:[[ZMFileMetadata alloc] initWithFileURL:fileURL thumbnail:nil]];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertEqual(fileMessage.deliveryState, ZMDeliveryStateFailedToSend);
    XCTAssertEqual(fileMessage.fileMessageData.transferState, ZMFileTransferStateFailedUpload);

    NSArray <ZMTransportRequest *> *requests = [self filterOutRequestsForLastRead:self.mockTransportSession.receivedRequests];
    XCTAssertEqual(requests.count, 1lu); // Asset.Original
    XCTAssertEqualObjects(requests.firstObject.path, expectedMessageAddPath);
    
}

- (void)testThatItDoesSendAFailedUploadMessageWhenTheFileDataUploadFails_400_V3
{
    // given
    XCTAssertTrue([self login]);

    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    XCTAssertNotNil(conversation);
    XCTAssertEqual(conversation.messages.count, 1lu);

    [self prefetchRemoteClientByInsertingMessageInConversation:self.selfToUser1Conversation];
    NSUInteger initialMessageCount = conversation.messages.count;


    NSURL *fileURL = [self createTestFile:@"foo43"];
    NSString *expectedMessageAddPath = [NSString stringWithFormat:@"/conversations/%@/otr/messages", conversation.remoteIdentifier.transportString];
    NSString *expectedAssetAddPath = @"/assets/v3";

    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request) {
        if ([request.path isEqualToString:expectedAssetAddPath]) {
            return [ZMTransportResponse responseWithPayload:nil HTTPStatus:401 transportSessionError:nil];
        }
        return nil;
    };

    // when
    [self.mockTransportSession resetReceivedRequests];

    __block ZMMessage *fileMessage;
    [self.userSession performChanges:^{
        fileMessage = (id)[conversation appendMessageWithFileMetadata:[[ZMFileMetadata alloc] initWithFileURL:fileURL thumbnail:nil]];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertEqual(fileMessage.deliveryState, ZMDeliveryStateFailedToSend);
    XCTAssertEqual(fileMessage.fileMessageData.transferState, ZMFileTransferStateFailedUpload);

    NSArray <ZMTransportRequest *> *requests = [self filterOutRequestsForLastRead:self.mockTransportSession.receivedRequests];
    XCTAssertEqual(requests.count, 3lu); // Asset.Original
    XCTAssertEqualObjects(requests[0].path, expectedMessageAddPath);
    XCTAssertEqualObjects(requests[1].path, expectedAssetAddPath);
    XCTAssertEqualObjects(requests[2].path, expectedMessageAddPath);

    XCTAssertEqual(conversation.messages.count - initialMessageCount , 1lu);
    ZMMessage *message = conversation.messages.lastObject;
    XCTAssertNotNil(message.fileMessageData);
    XCTAssertNil(message.imageMessageData);
    
}

- (void)testThatItDoesSendAFailedUploadMessageWhenTheFileDataUploadFails_NetworkError_V3
{
    // given
    XCTAssertTrue([self login]);

    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    XCTAssertNotNil(conversation);
    XCTAssertEqual(conversation.messages.count, 1lu);

    [self prefetchRemoteClientByInsertingMessageInConversation:self.selfToUser1Conversation];
    NSUInteger initialMessageCount = conversation.messages.count;

    NSURL *fileURL = [self createTestFile:@"foo45"];
    NSString *expectedMessageAddPath = [NSString stringWithFormat:@"/conversations/%@/otr/messages", conversation.remoteIdentifier.transportString];
    NSString *expectedAssetAddPath = @"/assets/v3";

    NSError *error = [NSError errorWithDomain:ZMTransportSessionErrorDomain code:ZMTransportSessionErrorCodeTryAgainLater userInfo:nil];
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request) {
        if ([request.path isEqualToString:expectedAssetAddPath]) {
            return [ZMTransportResponse responseWithPayload:nil HTTPStatus:0 transportSessionError:error];
        }
        return nil;
    };

    // when
    [self.mockTransportSession resetReceivedRequests];

    __block ZMMessage *fileMessage;
    [self.userSession performChanges:^{
        fileMessage = (id)[conversation appendMessageWithFileMetadata:[[ZMFileMetadata alloc] initWithFileURL:fileURL thumbnail:nil]];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertEqual(fileMessage.deliveryState, ZMDeliveryStateFailedToSend);
    XCTAssertEqual(fileMessage.fileMessageData.transferState, ZMFileTransferStateFailedUpload);

    NSArray <ZMTransportRequest *> *requests = [self filterOutRequestsForLastRead:self.mockTransportSession.receivedRequests];
    XCTAssertEqual(requests.count, 3lu); // Asset.Original
    XCTAssertEqualObjects(requests[0].path, expectedMessageAddPath);
    XCTAssertEqualObjects(requests[1].path, expectedAssetAddPath);
    XCTAssertEqualObjects(requests[2].path, expectedMessageAddPath);

    XCTAssertEqual(conversation.messages.count - initialMessageCount, 1lu);
    ZMMessage *message = conversation.messages.lastObject;
    XCTAssertNotNil(message.fileMessageData);
    XCTAssertNil(message.imageMessageData);
    
}

- (void)testThatItDoesSendACancelledUploadMessageWhenTheFileDataUploadIsCancelled_V3
{
    // given
    XCTAssertTrue([self login]);

    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    XCTAssertNotNil(conversation);
    XCTAssertEqual(conversation.messages.count, 1lu);

    [self prefetchRemoteClientByInsertingMessageInConversation:self.selfToUser1Conversation];
    NSUInteger initialMessageCount = conversation.messages.count;

    NSURL *fileURL = [self createTestFile:@"foo112"];
    NSString *expectedMessageAddPath = [NSString stringWithFormat:@"/conversations/%@/otr/messages", conversation.remoteIdentifier.transportString];
    NSString *expectedAssetAddPath = @"/assets/v3";

    __block ZMMessage *fileMessage;

    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request) {
        if ([request.path isEqualToString:expectedAssetAddPath]) {
            return ResponseGenerator.ResponseNotCompleted;
        }
        return nil;
    };

    // when
    [self.mockTransportSession resetReceivedRequests];

    [self.userSession performChanges:^{
        fileMessage = (id)[conversation appendMessageWithFileMetadata:[[ZMFileMetadata alloc] initWithFileURL:fileURL thumbnail:nil]];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    [self.userSession performChanges:^{
        [fileMessage.fileMessageData cancelTransfer];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertEqual(fileMessage.deliveryState, ZMDeliveryStateFailedToSend);
    XCTAssertEqual(fileMessage.fileMessageData.transferState, ZMFileTransferStateCancelledUpload);

    NSArray <ZMTransportRequest *> *requests = [self filterOutRequestsForLastRead:self.mockTransportSession.receivedRequests];
    XCTAssertEqual(requests.count, 3lu); // Asset.Original
    XCTAssertEqualObjects(requests[0].path, expectedMessageAddPath);
    XCTAssertEqualObjects(requests[1].path, expectedAssetAddPath);
    XCTAssertEqualObjects(requests[2].path, expectedMessageAddPath);

    XCTAssertEqual(conversation.messages.count - initialMessageCount, 1lu);
    ZMMessage *message = conversation.messages.lastObject;
    XCTAssertNotNil(message.fileMessageData);
    XCTAssertNil(message.imageMessageData);
    
}

- (void)testThatItDoesNotSendACancelledUploadMessageWhenThePlaceholderUploadFails_V3
{
    //given
    XCTAssertTrue([self login]);

    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    XCTAssertNotNil(conversation);
    XCTAssertEqual(conversation.messages.count, 1lu);

    NSURL *fileURL = [self createTestFile:@"foo2332"];
    NSString *expectedMessageAddPath = [NSString stringWithFormat:@"/conversations/%@/otr/messages", conversation.remoteIdentifier.transportString];

    __block ZMMessage *fileMessage;

    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request) {
        if ([request.path isEqualToString:expectedMessageAddPath]) {
            return [ZMTransportResponse responseWithPayload:nil HTTPStatus:401 transportSessionError:nil];
        }
        return nil;
    };

    // when
    [self.mockTransportSession resetReceivedRequests];

    [self.userSession performChanges:^{
        fileMessage = (id)[conversation appendMessageWithFileMetadata:[[ZMFileMetadata alloc] initWithFileURL:fileURL thumbnail:nil]];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    //then
    XCTAssertEqual(fileMessage.deliveryState, ZMDeliveryStateFailedToSend);
    XCTAssertEqual(fileMessage.fileMessageData.transferState, ZMFileTransferStateFailedUpload);

    NSArray <ZMTransportRequest *> *requests = [self filterOutRequestsForLastRead:self.mockTransportSession.receivedRequests];
    XCTAssertEqual(requests.count, 1lu); // Asset.Original
    XCTAssertEqualObjects(requests[0].path, expectedMessageAddPath);

    XCTAssertEqual(conversation.messages.count, 2lu);
    ZMMessage *message = conversation.messages.lastObject;
    XCTAssertNotNil(message.fileMessageData);
    XCTAssertNil(message.imageMessageData);
    
}

- (void)testThatItDoesReuploadTheAssetMetadataAfterReceivingA_412_MissingClients_V3
{
    //given
    XCTAssertTrue([self login]);
    
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    XCTAssertEqual(conversation.messages.count, 1lu);
    XCTAssertNotNil(conversation);

    NSURL *fileURL = [self createTestFile:@"foo2432"];
    NSString *expectedMessageAddPath = [NSString stringWithFormat:@"/conversations/%@/otr/messages", conversation.remoteIdentifier.transportString];
    NSString *expectedAssetAddPath = @"/assets/v3";

    // when
    // register other users client
    [self.mockTransportSession performRemoteChanges:^(id<MockTransportSessionObjectCreation> _Nonnull session) {
        [session registerClientForUser:self.user1 label:@"Android!" type:@"permanent"];
    }];
    __block ZMMessage *fileMessage;

    [self.mockTransportSession resetReceivedRequests];
    [self.userSession performChanges:^{
        fileMessage = (id)[conversation appendMessageWithFileMetadata:[[ZMFileMetadata alloc] initWithFileURL:fileURL thumbnail:nil]];
    }];

    WaitForAllGroupsToBeEmpty(0.5);

    //then
    XCTAssertEqual(fileMessage.deliveryState, ZMDeliveryStateSent);
    NSArray <ZMTransportRequest *> *requests = [self filterOutRequestsForLastRead:self.mockTransportSession.receivedRequests];

    XCTAssertEqual(requests.count, 5lu); // Asset.Original, Asset.Original reuploading, Asset uploading (/v3), Asset.Uploaded message

    if (requests.count < 5) {
        return;
    }

    ZMTransportRequest *firstOriginalUploadRequest = requests[0];
    ZMTransportRequest *missingPrekeysRequest = requests[1];
    ZMTransportRequest *secondOriginalUploadRequest = requests[2];
    ZMTransportRequest *uploadedUploadRequest = requests[3];
    ZMTransportRequest *uploadedMessageRequest = requests[4];

    XCTAssertEqualObjects(firstOriginalUploadRequest.path, expectedMessageAddPath);
    XCTAssertEqualObjects(secondOriginalUploadRequest.path, expectedMessageAddPath);
    XCTAssertEqualObjects(missingPrekeysRequest.path, @"/users/prekeys");
    XCTAssertEqualObjects(uploadedUploadRequest.path, expectedAssetAddPath);
    XCTAssertEqualObjects(uploadedMessageRequest.path, expectedMessageAddPath);
    XCTAssertEqual(conversation.messages.count, 2lu);

    ZMMessage *message = conversation.messages.lastObject;
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
    XCTAssertEqual(conversation.messages.count, 1lu);

    [self prefetchRemoteClientByInsertingMessageInConversation:self.selfToUser1Conversation];
    NSUInteger initialMessageCount = conversation.messages.count;

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
    XCTAssertEqual(fileMessage.fileMessageData.transferState, ZMFileTransferStateDownloaded);

    NSArray <ZMTransportRequest *> *requests = [self filterOutRequestsForLastRead:self.mockTransportSession.receivedRequests];

    // Asset.Original, Asset.Preview upload, generic message, Asset.Uploaded upload, generic message
    if (5 != requests.count) {
        return XCTFail(@"Wrong number of requests");
    }

    XCTAssertEqualObjects(requests.firstObject.path, expectedMessageAddPath);

    ZMTransportRequest *thumbnailRequest = requests[1];
    XCTAssertEqualObjects(thumbnailRequest.path, expectedAssetAddPath);

    ZMTransportRequest *thumbnailGenericMessageRequest = requests[2];
    XCTAssertEqualObjects(thumbnailGenericMessageRequest.path, expectedMessageAddPath);

    ZMTransportRequest *fullAssetRequest = requests[3];
    XCTAssertEqualObjects(fullAssetRequest.path, expectedAssetAddPath);

    ZMTransportRequest *fullAssetGenericMessageRequest = requests[4];
    XCTAssertEqualObjects(fullAssetGenericMessageRequest.path, expectedMessageAddPath);

    XCTAssertEqual(conversation.messages.count - initialMessageCount, 1lu);

    ZMMessage *message = conversation.messages.lastObject;

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
    XCTAssertEqual(conversation.messages.count, 1lu);

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
    XCTAssertEqual(fileMessage.fileMessageData.transferState, ZMFileTransferStateFailedUpload);

    // and when
    self.mockTransportSession.responseGeneratorBlock = nil;
    [self.userSession performChanges:^{
        [fileMessage resend];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertEqual(fileMessage.deliveryState, ZMDeliveryStateSent);
    XCTAssertEqual(fileMessage.fileMessageData.transferState, ZMFileTransferStateDownloaded);
    XCTAssertEqualObjects(fileMessage.fileMessageData.filename.stringByDeletingPathExtension, @"video");
    XCTAssertEqualObjects(fileMessage.fileMessageData.filename.pathExtension, @"mp4");

    NSError *error = nil;
    NSUInteger size = [NSFileManager.defaultManager attributesOfItemAtPath:fileURL.path error:&error].fileSize;

    XCTAssertNil(error);
    XCTAssertEqual(fileMessage.fileMessageData.size, size);
    
}

- (void)testThatItResendsAFailedFileMessage_WithVideo_ThumbnailGenericMessageUploadFailed_V3
{
    //given
    XCTAssertTrue([self login]);

    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    XCTAssertNotNil(conversation);
    XCTAssertEqual(conversation.messages.count, 1lu);

    NSURL *fileURL = self.testVideoFileURL;
    NSString *genericMessagePath = [NSString stringWithFormat:@"/conversations/%@/otr/messages", conversation.remoteIdentifier.transportString];

    __block NSUInteger genericMessageUploadCount = 0;

    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request) {
        // We fail the thumbnail asset generic message, which is the second /otr/messages post
        if ([request.path isEqualToString:genericMessagePath] && ++genericMessageUploadCount == 2) {
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
    XCTAssertEqual(genericMessageUploadCount, 2lu);

    // then
    XCTAssertEqual(fileMessage.deliveryState, ZMDeliveryStateFailedToSend);
    XCTAssertEqual(fileMessage.fileMessageData.transferState, ZMFileTransferStateFailedUpload);

    // and when
    self.mockTransportSession.responseGeneratorBlock = nil;
    [self.userSession performChanges:^{
        [fileMessage resend];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertEqual(fileMessage.deliveryState, ZMDeliveryStateSent);
    XCTAssertEqual(fileMessage.fileMessageData.transferState, ZMFileTransferStateDownloaded);
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
    XCTAssertEqual(conversation.messages.count, 1lu);

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
    XCTAssertEqual(fileMessage.fileMessageData.transferState, ZMFileTransferStateFailedUpload);

    // and when
    self.mockTransportSession.responseGeneratorBlock = nil;
    [self.userSession performChanges:^{
        [fileMessage resend];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    //then
    XCTAssertEqual(fileMessage.deliveryState, ZMDeliveryStateSent);
    XCTAssertEqual(fileMessage.fileMessageData.transferState, ZMFileTransferStateDownloaded);
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
    XCTAssertEqual(conversation.messages.count, 1lu);

    NSURL *fileURL = self.testVideoFileURL;
    NSString *genericMessagePath = [NSString stringWithFormat:@"/conversations/%@/otr/messages", conversation.remoteIdentifier.transportString];

    __block NSUInteger genericMessageUploadCount = 0;

    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request) {
        // We fail the third post to `/otr/messages`, which is the upload of the full asset generic message
        if ([request.path isEqualToString:genericMessagePath] && ++genericMessageUploadCount == 3) {
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
    // Asset.Original, Asset.Preview, Asset.Uploaded, Asset.NOTUploaded
    XCTAssertEqual(genericMessageUploadCount, 4lu);

    // then
    XCTAssertEqual(fileMessage.deliveryState, ZMDeliveryStateFailedToSend);
    XCTAssertEqual(fileMessage.fileMessageData.transferState, ZMFileTransferStateFailedUpload);

    // and when
    self.mockTransportSession.responseGeneratorBlock = nil;
    [self.userSession performChanges:^{
        [fileMessage resend];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    //then
    XCTAssertEqual(fileMessage.deliveryState, ZMDeliveryStateSent);
    XCTAssertEqual(fileMessage.fileMessageData.transferState, ZMFileTransferStateDownloaded);
    XCTAssertEqualObjects(fileMessage.fileMessageData.filename.stringByDeletingPathExtension, @"video");
    XCTAssertEqualObjects(fileMessage.fileMessageData.filename.pathExtension, @"mp4");

    NSError *error = nil;
    NSUInteger size = [NSFileManager.defaultManager attributesOfItemAtPath:fileURL.path error:&error].fileSize;

    XCTAssertNil(error);
    XCTAssertEqual(fileMessage.fileMessageData.size, size);
    
}

- (void)testThatItDoesNotSendAFileWhenTheOriginalRequestFails_WithVideo_V3
{
    //given
    XCTAssertTrue([self login]);

    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    XCTAssertNotNil(conversation);
    XCTAssertEqual(conversation.messages.count, 1lu);

    NSURL *fileURL = self.testVideoFileURL;
    NSString *expectedMessageAddPath = [NSString stringWithFormat:@"/conversations/%@/otr/messages", conversation.remoteIdentifier.transportString];

    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request) {
        if ([request.path isEqualToString:expectedMessageAddPath]) {
            return [ZMTransportResponse responseWithPayload:nil HTTPStatus:401 transportSessionError:nil];
        }
        return nil;
    };

    // when
    [self.mockTransportSession resetReceivedRequests];

    __block ZMMessage *fileMessage;
    [self.userSession performChanges:^{
        ZMVideoMetadata *metadata = [[ZMVideoMetadata alloc] initWithFileURL:fileURL thumbnail:self.mediumJPEGData];
        fileMessage = (id)[conversation appendMessageWithFileMetadata:metadata];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    //then
    XCTAssertEqual(fileMessage.deliveryState, ZMDeliveryStateFailedToSend);
    XCTAssertEqual(fileMessage.fileMessageData.transferState, ZMFileTransferStateFailedUpload);

    NSArray <ZMTransportRequest *> *requests = [self filterOutRequestsForLastRead:self.mockTransportSession.receivedRequests];
    XCTAssertEqual(requests.count, 1lu); // Asset.Original
    XCTAssertEqualObjects(requests.firstObject.path, expectedMessageAddPath);
    
}

- (void)testThatItDoesSendAFailedUploadMessageWhenTheThumbnailUploadFails_400_WithVideo_V3
{
    //given
    XCTAssertTrue([self login]);

    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    XCTAssertNotNil(conversation);
    XCTAssertEqual(conversation.messages.count, 1lu);

    [self prefetchRemoteClientByInsertingMessageInConversation:self.selfToUser1Conversation];
    NSUInteger initialMessageCount = conversation.messages.count;

    NSURL *fileURL = self.testVideoFileURL;
    NSString *transportString = conversation.remoteIdentifier.transportString;
    NSString *expectedMessageAddPath = [NSString stringWithFormat:@"/conversations/%@/otr/messages", transportString];
    NSString *expectedAssetAddPath = @"/assets/v3";

    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request) {
        if ([request.path isEqualToString:expectedAssetAddPath]) {
            return [ZMTransportResponse responseWithPayload:nil HTTPStatus:401 transportSessionError:nil];
        }
        return nil;
    };

    // when
    [self.mockTransportSession resetReceivedRequests];

    __block ZMMessage *fileMessage;
    [self.userSession performChanges:^{
        ZMVideoMetadata *metadata = [[ZMVideoMetadata alloc] initWithFileURL:fileURL thumbnail:self.mediumJPEGData];
        fileMessage = (id)[conversation appendMessageWithFileMetadata:metadata];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    //then
    XCTAssertEqual(fileMessage.deliveryState, ZMDeliveryStateFailedToSend);
    XCTAssertEqual(fileMessage.fileMessageData.transferState, ZMFileTransferStateFailedUpload);

    NSArray <ZMTransportRequest *> *requests = [self filterOutRequestsForLastRead:self.mockTransportSession.receivedRequests];
    XCTAssertEqual(requests.count, 3lu);
    XCTAssertEqualObjects(requests[0].path, expectedMessageAddPath);  // Asset.Original
    XCTAssertEqualObjects(requests[1].path, expectedAssetAddPath);    // Asset.Preview Asset upload (v3)
    XCTAssertEqualObjects(requests[2].path, expectedMessageAddPath);  // Asset.NotUploaded

    XCTAssertEqual(conversation.messages.count - initialMessageCount, 1lu);

    ZMMessage *message = conversation.messages.lastObject;
    XCTAssertNotNil(message.fileMessageData);
    XCTAssertNil(message.imageMessageData);
    
}

- (void)testThatItDoesSendAFailedUploadMessageWhenTheFullAssetUploadFails_400_WithVideo_V3
{
    //given
    XCTAssertTrue([self login]);

    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    XCTAssertNotNil(conversation);
    XCTAssertEqual(conversation.messages.count, 1lu);

    [self prefetchRemoteClientByInsertingMessageInConversation:self.selfToUser1Conversation];
    NSUInteger initialMessageCount = conversation.messages.count;

    NSURL *fileURL = self.testVideoFileURL;
    NSString *expectedMessageAddPath = [NSString stringWithFormat:@"/conversations/%@/otr/messages", conversation.remoteIdentifier.transportString];
    NSString *expectedAssetAddPath = @"/assets/v3";

    __block NSUInteger assetCallCount = 0;
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request) {
        if ([request.path isEqualToString:expectedAssetAddPath]) {
            if (++assetCallCount == 2) {
                return [ZMTransportResponse responseWithPayload:nil HTTPStatus:401 transportSessionError:nil];
            }
        }
        return nil;
    };

    // when
    [self.mockTransportSession resetReceivedRequests];

    __block ZMMessage *fileMessage;
    [self.userSession performChanges:^{
        ZMVideoMetadata *metadata = [[ZMVideoMetadata alloc] initWithFileURL:fileURL thumbnail:self.mediumJPEGData];
        fileMessage = (id)[conversation appendMessageWithFileMetadata:metadata];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    //then
    XCTAssertEqual(assetCallCount, 2lu);
    XCTAssertEqual(fileMessage.deliveryState, ZMDeliveryStateFailedToSend);
    XCTAssertEqual(fileMessage.fileMessageData.transferState, ZMFileTransferStateFailedUpload);

    NSArray <ZMTransportRequest *> *requests = [self filterOutRequestsForLastRead:self.mockTransportSession.receivedRequests];
    XCTAssertEqual(requests.count, 5lu);
    XCTAssertEqualObjects(requests[0].path, expectedMessageAddPath);  // Asset.Original    generic message
    XCTAssertEqualObjects(requests[1].path, expectedAssetAddPath);    // Asset.Preview     asset upload
    XCTAssertEqualObjects(requests[2].path, expectedMessageAddPath);  // Asset.Preview     generic message
    XCTAssertEqualObjects(requests[3].path, expectedAssetAddPath);    // Asset.FullAsset   asset upload
    XCTAssertEqualObjects(requests[4].path, expectedMessageAddPath);  // Asset.NotUploaded generic message

    XCTAssertEqual(conversation.messages.count - initialMessageCount, 1lu);

    ZMMessage *message = conversation.messages.lastObject;
    XCTAssertNotNil(message.fileMessageData);
    XCTAssertNil(message.imageMessageData);
    
}

- (void)testThatItDoesSendAFailedUploadMessageWhenTheThumbnailUploadFails_NetworkError_WithVideo_V3
{
    //given
    XCTAssertTrue([self login]);

    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    XCTAssertNotNil(conversation);
    XCTAssertEqual(conversation.messages.count, 1lu);

    [self prefetchRemoteClientByInsertingMessageInConversation:self.selfToUser1Conversation];
    NSUInteger initialMessageCount = conversation.messages.count;

    NSURL *fileURL = self.testVideoFileURL;
    NSString *expectedMessageAddPath = [NSString stringWithFormat:@"/conversations/%@/otr/messages", conversation.remoteIdentifier.transportString];
    NSString *expectedAssetAddPath = @"/assets/v3";
    NSError *error = [NSError errorWithDomain:ZMTransportSessionErrorDomain code:ZMTransportSessionErrorCodeTryAgainLater userInfo:nil];
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request) {
        if ([request.path isEqualToString:expectedAssetAddPath]) {
            return [ZMTransportResponse responseWithPayload:nil HTTPStatus:0 transportSessionError:error];
        }
        return nil;
    };

    // when
    [self.mockTransportSession resetReceivedRequests];

    __block ZMMessage *fileMessage;
    [self.userSession performChanges:^{
        ZMVideoMetadata *metadata = [[ZMVideoMetadata alloc] initWithFileURL:fileURL thumbnail:self.mediumJPEGData];
        fileMessage = (id)[conversation appendMessageWithFileMetadata:metadata];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    //then
    XCTAssertEqual(fileMessage.deliveryState, ZMDeliveryStateFailedToSend);
    XCTAssertEqual(fileMessage.fileMessageData.transferState, ZMFileTransferStateFailedUpload);

    NSArray <ZMTransportRequest *> *requests = [self filterOutRequestsForLastRead:self.mockTransportSession.receivedRequests];
    XCTAssertEqual(requests.count, 3lu);
    XCTAssertEqualObjects(requests[0].path, expectedMessageAddPath);  // Asset.Original    generic message
    XCTAssertEqualObjects(requests[1].path, expectedAssetAddPath);    // Asset.Preview     asset upload
    XCTAssertEqualObjects(requests[2].path, expectedMessageAddPath);  // Asset.NotUploaded generic message

    XCTAssertEqual(conversation.messages.count - initialMessageCount, 1lu);

    ZMMessage *message = conversation.messages.lastObject;
    XCTAssertNotNil(message.fileMessageData);
    XCTAssertNil(message.imageMessageData);
    
}

- (void)testThatItDoesSendAFailedUploadMessageWhenTheFileDataUploadFails_NetworkError_WithVideo_V3
{
    //given
    XCTAssertTrue([self login]);

    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    XCTAssertNotNil(conversation);
    XCTAssertEqual(conversation.messages.count, 1lu);

    [self prefetchRemoteClientByInsertingMessageInConversation:self.selfToUser1Conversation];
    NSUInteger initialMessageCount = conversation.messages.count;

    NSURL *fileURL = self.testVideoFileURL;
    NSString *expectedMessageAddPath = [NSString stringWithFormat:@"/conversations/%@/otr/messages", conversation.remoteIdentifier.transportString];
    NSString *expectedAssetAddPath = @"/assets/v3";
    __block NSUInteger assetCallCount = 0;
    NSError *error = [NSError errorWithDomain:ZMTransportSessionErrorDomain code:ZMTransportSessionErrorCodeTryAgainLater userInfo:nil];
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request) {
        if ([request.path isEqualToString:expectedAssetAddPath]) {
            if (++assetCallCount == 2) {
                return [ZMTransportResponse responseWithPayload:nil HTTPStatus:0 transportSessionError:error];
            }
        }
        return nil;
    };

    // when
    [self.mockTransportSession resetReceivedRequests];

    __block ZMMessage *fileMessage;
    [self.userSession performChanges:^{
        ZMVideoMetadata *metadata = [[ZMVideoMetadata alloc] initWithFileURL:fileURL thumbnail:self.mediumJPEGData];
        fileMessage = (id)[conversation appendMessageWithFileMetadata:metadata];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    //then
    XCTAssertEqual(assetCallCount, 2lu);
    XCTAssertEqual(fileMessage.deliveryState, ZMDeliveryStateFailedToSend);
    XCTAssertEqual(fileMessage.fileMessageData.transferState, ZMFileTransferStateFailedUpload);

    NSArray <ZMTransportRequest *> *requests = [self filterOutRequestsForLastRead:self.mockTransportSession.receivedRequests];
    XCTAssertEqual(requests.count, 5lu);
    XCTAssertEqualObjects(requests[0].path, expectedMessageAddPath);  // Asset.Original    generic message
    XCTAssertEqualObjects(requests[1].path, expectedAssetAddPath);    // Asset.Preview     asset upload
    XCTAssertEqualObjects(requests[2].path, expectedMessageAddPath);  // Asset.Preview     generic message
    XCTAssertEqualObjects(requests[3].path, expectedAssetAddPath);    // Asset.FullAsset   asset upload
    XCTAssertEqualObjects(requests[4].path, expectedMessageAddPath);  // Asset.NotUploaded generic message

    XCTAssertEqual(conversation.messages.count - initialMessageCount, 1lu);

    ZMMessage *message = conversation.messages.lastObject;
    XCTAssertNotNil(message.fileMessageData);
    XCTAssertNil(message.imageMessageData);
    
}

- (void)testThatItDoesSendACancelledUploadMessageWhenTheThumbnailDataUploadIsCancelled_WithVideo_V3
{
    //given
    XCTAssertTrue([self login]);

    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    XCTAssertNotNil(conversation);
    XCTAssertEqual(conversation.messages.count, 1lu);

    [self prefetchRemoteClientByInsertingMessageInConversation:self.selfToUser1Conversation];
    NSUInteger initialMessageCount = conversation.messages.count;

    NSURL *fileURL = self.testVideoFileURL;
    NSString *expectedMessageAddPath = [NSString stringWithFormat:@"/conversations/%@/otr/messages", conversation.remoteIdentifier.transportString];
    NSString *expectedAssetAddPath = @"/assets/v3";

    __block ZMMessage *fileMessage;

    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request) {
        if ([request.path isEqualToString:expectedAssetAddPath]) {
            return ResponseGenerator.ResponseNotCompleted;
        }
        return nil;
    };

    // when
    [self.mockTransportSession resetReceivedRequests];

    [self.userSession performChanges:^{
        ZMVideoMetadata *metadata = [[ZMVideoMetadata alloc] initWithFileURL:fileURL thumbnail:self.mediumJPEGData];
        fileMessage = (id)[conversation appendMessageWithFileMetadata:metadata];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    [self.userSession performChanges:^{
        [fileMessage.fileMessageData cancelTransfer];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    //then
    XCTAssertEqual(fileMessage.deliveryState, ZMDeliveryStateFailedToSend);
    XCTAssertEqual(fileMessage.fileMessageData.transferState, ZMFileTransferStateCancelledUpload);

    NSArray <ZMTransportRequest *> *requests = [self filterOutRequestsForLastRead:self.mockTransportSession.receivedRequests];
    XCTAssertEqual(requests.count, 3lu);
    XCTAssertEqualObjects(requests[0].path, expectedMessageAddPath);  // Asset.Original
    XCTAssertEqualObjects(requests[1].path, expectedAssetAddPath);    // Asset.Preview upload
    XCTAssertEqualObjects(requests[2].path, expectedMessageAddPath);  // Asset.NotUploaded

    XCTAssertEqual(conversation.messages.count - initialMessageCount, 1lu);

    ZMMessage *message = conversation.messages.lastObject;
    XCTAssertNotNil(message.fileMessageData);
    XCTAssertNil(message.imageMessageData);

    XCTAssertEqualObjects(message.fileMessageData.filename.stringByDeletingPathExtension, @"video");
    XCTAssertEqualObjects(message.fileMessageData.filename.pathExtension, @"mp4");

    NSError *error = nil;
    NSUInteger size = [NSFileManager.defaultManager attributesOfItemAtPath:fileURL.path error:&error].fileSize;

    XCTAssertNil(error);
    XCTAssertEqual(message.fileMessageData.size, size);
    
}

- (void)testThatItDoesSendACancelledUploadMessageWhenTheFileDataUploadIsCancelled_WithVideo_V3
{
    // given
    XCTAssertTrue([self login]);

    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    XCTAssertNotNil(conversation);
    XCTAssertEqual(conversation.messages.count, 1lu);

    [self prefetchRemoteClientByInsertingMessageInConversation:self.selfToUser1Conversation];

    NSUInteger initialMessageCount = conversation.messages.count;
    NSURL *fileURL = self.testVideoFileURL;
    NSString *expectedMessageAddPath = [NSString stringWithFormat:@"/conversations/%@/otr/messages", conversation.remoteIdentifier.transportString];
    NSString *expectedAssetAddPath = @"/assets/v3";

    __block ZMMessage *fileMessage;
    __block NSUInteger assetCallCount = 0;
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request) {
        if ([request.path isEqualToString:expectedAssetAddPath]) {
            if (++assetCallCount == 2) {
                return ResponseGenerator.ResponseNotCompleted;
            }
        }
        return nil;
    };

    // when
    [self.mockTransportSession resetReceivedRequests];

    [self.userSession performChanges:^{
        ZMVideoMetadata *metadata = [[ZMVideoMetadata alloc] initWithFileURL:fileURL thumbnail:self.mediumJPEGData];
        fileMessage = (id)[conversation appendMessageWithFileMetadata:metadata];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    [self.userSession performChanges:^{
        [fileMessage.fileMessageData cancelTransfer];
    }];
    WaitForAllGroupsToBeEmpty(5);

    //then
    XCTAssertEqual(assetCallCount, 2lu);
    XCTAssertEqual(fileMessage.deliveryState, ZMDeliveryStateFailedToSend);
    XCTAssertEqual(fileMessage.fileMessageData.transferState, ZMFileTransferStateCancelledUpload);

    NSArray <ZMTransportRequest *> *requests = [self filterOutRequestsForLastRead:self.mockTransportSession.receivedRequests];
    XCTAssertEqual(requests.count, 5lu);
    XCTAssertEqualObjects(requests[0].path, expectedMessageAddPath);  // Asset.Original     generic message
    XCTAssertEqualObjects(requests[1].path, expectedAssetAddPath);    // Asset.Preview      upload (v3)
    XCTAssertEqualObjects(requests[2].path, expectedMessageAddPath);  // Asset.Preview      generic message
    XCTAssertEqualObjects(requests[3].path, expectedAssetAddPath);    // Asset.Uploaded     upload (v3)
    XCTAssertEqualObjects(requests[4].path, expectedMessageAddPath);  // Asset.NotUploaded  generic message

    XCTAssertEqual(conversation.messages.count - initialMessageCount, 1lu);

    ZMMessage *message = conversation.messages.lastObject;
    XCTAssertNotNil(message.fileMessageData);
    XCTAssertNil(message.imageMessageData);

    XCTAssertEqualObjects(message.fileMessageData.filename.stringByDeletingPathExtension, @"video");
    XCTAssertEqualObjects(message.fileMessageData.filename.pathExtension, @"mp4");

    NSError *error = nil;
    NSUInteger size = [NSFileManager.defaultManager attributesOfItemAtPath:fileURL.path error:&error].fileSize;

    XCTAssertNil(error);
    XCTAssertEqual(message.fileMessageData.size, size);
    
}

- (void)testThatItDoesNotSendACancelledUploadMessageWhenThePlaceholderUploadFails_WithVideo_V3
{
    //given
    XCTAssertTrue([self login]);

    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    XCTAssertNotNil(conversation);
    XCTAssertEqual(conversation.messages.count, 1lu);

    NSURL *fileURL = self.testVideoFileURL;
    NSString *expectedMessageAddPath = [NSString stringWithFormat:@"/conversations/%@/otr/messages", conversation.remoteIdentifier.transportString];

    __block ZMMessage *fileMessage;

    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request) {
        if ([request.path isEqualToString:expectedMessageAddPath]) {
            return [ZMTransportResponse responseWithPayload:nil HTTPStatus:401 transportSessionError:nil];
        }
        return nil;
    };

    // when
    [self.mockTransportSession resetReceivedRequests];

    [self.userSession performChanges:^{
        ZMVideoMetadata *metadata = [[ZMVideoMetadata alloc] initWithFileURL:fileURL thumbnail:self.mediumJPEGData];
        fileMessage = (id)[conversation appendMessageWithFileMetadata:metadata];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    //then
    XCTAssertEqual(fileMessage.deliveryState, ZMDeliveryStateFailedToSend);
    XCTAssertEqual(fileMessage.fileMessageData.transferState, ZMFileTransferStateFailedUpload);

    NSArray <ZMTransportRequest *> *requests = [self filterOutRequestsForLastRead:self.mockTransportSession.receivedRequests];
    XCTAssertEqual(requests.count, 1lu); // Asset.Original
    XCTAssertEqualObjects(requests[0].path, expectedMessageAddPath);

    XCTAssertEqual(conversation.messages.count, 2lu);
    ZMMessage *message = conversation.messages.lastObject;
    XCTAssertNotNil(message.fileMessageData);
    XCTAssertNil(message.imageMessageData);
    
}

- (void)testThatItDoesReuploadTheAssetMetadataAfterReceivingA_412_MissingClients_WithVideo_V3
{
    //given
    XCTAssertTrue([self login]);


    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    XCTAssertEqual(conversation.messages.count, 1lu);

    NSURL *fileURL = self.testVideoFileURL;
    NSString *conversationIDString = conversation.remoteIdentifier.transportString;
    NSString *expectedMessageAddPath = [NSString stringWithFormat:@"/conversations/%@/otr/messages", conversationIDString];

    NSString *expectedAssetAddPath = @"/assets/v3";

    // when
    // register other users client
    [self.mockTransportSession performRemoteChanges:^(id<MockTransportSessionObjectCreation> _Nonnull session) {
        [session registerClientForUser:self.user1 label:@"Android!" type:@"permanent"];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    __block ZMMessage *fileMessage;

    [self.mockTransportSession resetReceivedRequests];
    [self.userSession performChanges:^{
        ZMVideoMetadata *metadata = [[ZMVideoMetadata alloc] initWithFileURL:fileURL thumbnail:self.mediumJPEGData];
        fileMessage = (id)[conversation appendMessageWithFileMetadata:metadata];
    }];

    WaitForAllGroupsToBeEmpty(0.5);

    //then
    XCTAssertEqual(fileMessage.deliveryState, ZMDeliveryStateSent);
    XCTAssertEqual(fileMessage.fileMessageData.transferState, ZMFileTransferStateDownloaded);

    NSArray <ZMTransportRequest *> *requests = [self filterOutRequestsForLastRead:self.mockTransportSession.receivedRequests];

    // Asset.Original, Prekeys, Asset.Original reuploading, Asset.Preview upload, generic message, Asset.Uploaded upload, generic message
    XCTAssertEqual(requests.count, 7lu);
    if (requests.count < 7) {
        return;
    }

    ZMTransportRequest *firstOriginalUploadRequest = requests[0];
    ZMTransportRequest *missingPrekeysRequest = requests[1];
    ZMTransportRequest *secondOriginalUploadRequest = requests[2];
    ZMTransportRequest *thumbnailUploadRequest = requests[3];
    ZMTransportRequest *thumbnailGenericMessageRequest = requests[4];
    ZMTransportRequest *fullAssetUploadRequest = requests[5];
    ZMTransportRequest *fullAssetGenericMessageRequest = requests[6];

    XCTAssertEqualObjects(firstOriginalUploadRequest.path, expectedMessageAddPath);
    XCTAssertEqualObjects(secondOriginalUploadRequest.path, expectedMessageAddPath);
    XCTAssertEqualObjects(missingPrekeysRequest.path, @"/users/prekeys");
    XCTAssertEqualObjects(thumbnailUploadRequest.path, expectedAssetAddPath);
    XCTAssertEqualObjects(thumbnailGenericMessageRequest.path, expectedMessageAddPath);
    XCTAssertEqualObjects(fullAssetUploadRequest.path, expectedAssetAddPath);
    XCTAssertEqualObjects(fullAssetGenericMessageRequest.path, expectedMessageAddPath);
    XCTAssertEqual(conversation.messages.count, 2lu);

    ZMMessage *message = conversation.messages.lastObject;
    XCTAssertNotNil(message.fileMessageData);
    XCTAssertNil(message.imageMessageData);
    
}

- (void)testThatItSendsARegularFileMessageForAFileWithVideoButNilThumbnail_V3
{
    //given
    XCTAssertTrue([self login]);

    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    XCTAssertNotNil(conversation);
    XCTAssertEqual(conversation.messages.count, 1lu);

    [self prefetchRemoteClientByInsertingMessageInConversation:self.selfToUser1Conversation];
    NSUInteger initialMessageCount = conversation.messages.count;

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
    XCTAssertEqual(fileMessage.fileMessageData.transferState, ZMFileTransferStateDownloaded);

    NSArray <ZMTransportRequest *> *requests = [self filterOutRequestsForLastRead:self.mockTransportSession.receivedRequests];
    XCTAssertEqual(requests.count, 3lu); // Asset.Original & Asset.Uploaded asset upload & Asset.Uploaded generic message

    ZMTransportRequest *originalMessageRequest = requests[0];
    ZMTransportRequest *uploadAssetRequest = requests[1];
    ZMTransportRequest *uploadMessageRequest = requests[2];

    XCTAssertEqualObjects(originalMessageRequest.path, expectedMessageAddPath);
    XCTAssertEqualObjects(uploadAssetRequest.path, expectedAssetAddPath);
    XCTAssertEqualObjects(uploadMessageRequest.path, expectedMessageAddPath);
    XCTAssertEqual(conversation.messages.count - initialMessageCount, 1lu);

    ZMMessage *message = conversation.messages.lastObject;

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

    ZMGenericMessage *uploaded = [[ZMGenericMessage genericMessageWithUploadedOTRKey:otrKey sha256:sha256 messageID:nonce expiresAfter:nil] updatedUploadedWithAssetId:assetID.transportString token:nil];

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
    XCTAssertEqual(message.transferState, ZMFileTransferStateUploaded);
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
    XCTAssertEqual(message.transferState, ZMFileTransferStateDownloaded);
    
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

    ZMGenericMessage *uploaded = [[ZMGenericMessage genericMessageWithUploadedOTRKey:otrKey sha256:sha256 messageID:nonce expiresAfter:nil] updatedUploadedWithAssetId:assetID.transportString token:nil];

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
    XCTAssertEqual(message.transferState, ZMFileTransferStateUploaded);
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
    XCTAssertEqual(message.transferState, ZMFileTransferStateFailedDownload);
    
}

@end
