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

#import "ConversationTestsBase.h"
#import "MockLinkPreviewDetector.h"
#import "MockLinkPreviewDetector.h"
#import "WireSyncEngine_iOS_Tests-Swift.h"

@import WireUtilities;

@interface LinkPreviewTests : ConversationTestsBase
@property (nonatomic) MockLinkPreviewDetector *mockLinkPreviewDetector;

@end

@implementation LinkPreviewTests

- (void)setUp
{
    [super setUp];
    self.mockLinkPreviewDetector = [[MockLinkPreviewDetector alloc] initWithTestImageData:[self mediumJPEGData]];
    [LinkPreviewDetectorHelper setTest_debug_linkPreviewDetector:self.mockLinkPreviewDetector];
}

- (void)tearDown
{
    self.mockLinkPreviewDetector = nil;
    [super tearDown];
}

- (void)createEncryptionDataWithOrignalAssetData:(NSData *)assetData encryptedData:(NSData **)encryptedData otrKey:(NSData **)otrKey sha256:(NSData **)sha256;
{
    *otrKey = [NSData randomEncryptionKey];
    *encryptedData = [assetData zmEncryptPrefixingPlainTextIVWithKey:*otrKey];
    *sha256 = [*encryptedData zmSHA256Digest];

}

- (ZMAsset *)imageAssetWithAssetID:(NSUUID *)assetID assetToken:(NSUUID *)assetToken otrKey:(NSData *)otrKey sha256:(NSData *)sha256;
{
    ZMAssetRemoteDataBuilder *remoteDataBuilder = [ZMAssetRemoteDataBuilder new];
    remoteDataBuilder.otrKey = otrKey;
    remoteDataBuilder.sha256 = sha256;
    remoteDataBuilder.assetId = assetID.transportString;
    remoteDataBuilder.assetToken = assetToken.transportString;
    
    ZMAssetBuilder *assetBuilder = [ZMAssetBuilder new];
    assetBuilder.uploaded = [remoteDataBuilder build];
    
    return [assetBuilder build];
}

- (BOOL)checkForValidLinkPreviewInMessage:(ZMClientMessage *)message expectedLinkPreview:(ZMLinkPreview *)expectedLinkPreview failureRecorder:(ZMTFailureRecorder *)failureRecorder;
{
    void (^imageChecker)(ZMAsset *) = ^(ZMAsset *image) {
        FHAssertTrue(failureRecorder,   image.hasUploaded);
        FHAssertNotNil(failureRecorder, image.uploaded.assetId);
        FHAssertNotNil(failureRecorder, image.uploaded.otrKey);
        FHAssertNotNil(failureRecorder, image.uploaded.sha256);
    };
    
    FHAssertNotNil(failureRecorder, message.genericMessage);
    FHAssertNotNil(failureRecorder, message.genericMessage);
    FHAssertNotNil(failureRecorder, message.genericMessage.textData);
    FHAssertTrue(failureRecorder, message.genericMessage.textData.linkPreview.count > 0);
    
    ZMLinkPreview *preview = [message.genericMessage.textData.linkPreview firstObject];
    FHAssertEqualObjects(failureRecorder, preview.title, expectedLinkPreview.title);
    FHAssertEqualObjects(failureRecorder, preview.summary, expectedLinkPreview.summary);
    
    XCTAssertEqual(preview.hasArticle, expectedLinkPreview.hasArticle);
    if (preview.hasArticle) {
        FHAssertEqualObjects(failureRecorder, preview.article.title, expectedLinkPreview.article.title);
        FHAssertEqualObjects(failureRecorder, preview.article.summary, expectedLinkPreview.article.summary);
        FHAssertEqual(failureRecorder, preview.article.hasImage, preview.article.hasImage);
        if (preview.article.hasImage) {
            imageChecker(preview.article.image);
        }
    }
    
    XCTAssertEqual(preview.hasTweet, expectedLinkPreview.hasTweet);
    if (preview.hasTweet) {
        FHAssertEqualObjects(failureRecorder, preview.tweet.author, expectedLinkPreview.tweet.author);
        FHAssertEqualObjects(failureRecorder, preview.tweet.username, expectedLinkPreview.tweet.username);
    }
    
    XCTAssertEqual(preview.hasImage, expectedLinkPreview.hasImage);
    if (preview.hasImage) {
        imageChecker(preview.image);
    }

}

- (void)testThatItInsertCorrectLinkPreviewMessage_ArticleWithoutImage;
{
    // need to check mock transport if we have the image
    XCTAssert([self login]);
    
    NSString *text = ZMTestURLArticleWithoutPictureString;
    

    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    
    ZMLinkPreview *expectedLinkPreview = [self.mockLinkPreviewDetector linkPreviewFromURLString:text includeAsset:NO includingTweet:NO];
    
    [self.userSession performChanges:^{
        [conversation appendMessageWithText:text];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssertEqual(conversation.messages.count, 2lu); //text message, then link preview message
    
    __block ZMClientMessage *message = conversation.messages.lastObject;
    [self checkForValidLinkPreviewInMessage:message expectedLinkPreview:expectedLinkPreview failureRecorder:NewFailureRecorder()];
}

- (void)testThatItInsertCorrectLinkPreviewMessage_ArticleWithImage;
{
    //given
    XCTAssert([self login]);
    NSString *text = ZMTestURLArticleWithPictureString;
    
    
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    
    ZMLinkPreview *expectedLinkPreview = [self.mockLinkPreviewDetector linkPreviewFromURLString:text includeAsset:YES includingTweet:NO];
    
    //when
    [self.userSession performChanges:^{
        [conversation appendMessageWithText:text];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    
    //then
    XCTAssertEqual(conversation.messages.count, 2lu); //text message, then link preview message
    
    __block ZMClientMessage *message = conversation.messages.lastObject;
    
    [self checkForValidLinkPreviewInMessage:message expectedLinkPreview:expectedLinkPreview failureRecorder:NewFailureRecorder()];
}


- (void)testThatItInsertCorrectLinkPreviewMessage_TweetWithoutImage;
{
    //given
        XCTAssert([self login]);
    
    NSString *text = ZMTestURLRegularTweetString;
    ZMLinkPreview *expectedLinkPreview = [self.mockLinkPreviewDetector linkPreviewFromURLString:text includeAsset:NO includingTweet:YES];
    
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    
    //when
    [self.userSession performChanges:^{
        [conversation appendMessageWithText:text];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    //then
    XCTAssertEqual(conversation.messages.count, 2lu); //text message, then link preview message
    
    __block ZMClientMessage *message = conversation.messages.lastObject;
    [self checkForValidLinkPreviewInMessage:message expectedLinkPreview:expectedLinkPreview failureRecorder:NewFailureRecorder()];
}

- (void)testThatItInsertCorrectLinkPreviewMessage_TweetWithImage;
{
    //given
        XCTAssert([self login]);
    
    NSString *text = ZMTestURLTweetWithPictureString;
    ZMLinkPreview *expectedLinkPreview = [self.mockLinkPreviewDetector linkPreviewFromURLString:text includeAsset:YES includingTweet:YES];
    
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    
    //when
    [self.userSession performChanges:^{
        [conversation appendMessageWithText:text];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    //then
    XCTAssertEqual(conversation.messages.count, 2lu); //text message, then link preview message
    
    __block ZMClientMessage *message = conversation.messages.lastObject;
    [self checkForValidLinkPreviewInMessage:message expectedLinkPreview:expectedLinkPreview failureRecorder:NewFailureRecorder()];
}

- (void)testThatItUpdateMessageWhenReceivingLinkPreviewFollowUp_WithoutImage;
{
    // given
        XCTAssert([self login]);
    
    MockConversation *mockConversation = self.selfToUser1Conversation;
    [self prefetchRemoteClientByInsertingMessageInConversation:mockConversation];
    WaitForAllGroupsToBeEmpty(0.5);
    
    
    ZMConversation *conversation = [self conversationForMockConversation:mockConversation];
    MockUserClient *selfClient = [self.selfUser.clients anyObject];
    MockUserClient *senderClient = [self.user1.clients anyObject];
    
    NSUUID *messageNonce = [NSUUID createUUID];
    NSString *urlText = ZMTestURLArticleWithoutPictureString;
    
    ZMGenericMessage *linkPreviewMessage = [ZMGenericMessage messageWithText:urlText nonce:messageNonce expiresAfter:nil];
    [self.mockTransportSession performRemoteChanges:^(__unused id<MockTransportSessionObjectCreation> session) {
        [mockConversation encryptAndInsertDataFromClient:senderClient toClient:selfClient data:linkPreviewMessage.data];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    //sanity check
    XCTAssertEqual(conversation.messages.count, 3lu);
    ZMClientMessage *message = [conversation.messages lastObject];
    XCTAssertEqualObjects(message.nonce, messageNonce);
    XCTAssertEqualObjects(message.textMessageData.messageText, urlText);
    XCTAssertNil(message.textMessageData.linkPreview);
    
    //when
    ZMLinkPreview *remoteLinkPreview = [self.mockLinkPreviewDetector linkPreviewFromURLString:urlText includeAsset:NO includingTweet:NO];
    linkPreviewMessage = [ZMGenericMessage messageWithText:urlText linkPreview:remoteLinkPreview nonce:messageNonce expiresAfter:nil];
    
    [self.mockTransportSession performRemoteChanges:^(__unused id<MockTransportSessionObjectCreation> session) {
        [mockConversation encryptAndInsertDataFromClient:senderClient toClient:selfClient data:linkPreviewMessage.data];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    //then
    [self checkForValidLinkPreviewInMessage:message expectedLinkPreview:remoteLinkPreview failureRecorder:NewFailureRecorder()];
}

- (void)testThatItUpdateMessageWhenReceivingLinkPreviewFollowUp_WithoutImage_onlyArticle;
{
    // given
    XCTAssert([self login]);
    
    MockConversation *mockConversation = self.selfToUser1Conversation;
    [self prefetchRemoteClientByInsertingMessageInConversation:mockConversation];
    WaitForAllGroupsToBeEmpty(0.5);
    
    ZMConversation *conversation = [self conversationForMockConversation:mockConversation];
    MockUserClient *selfClient = [self.selfUser.clients anyObject];
    MockUserClient *senderClient = [self.user1.clients anyObject];
    
    NSUUID *messageNonce = [NSUUID createUUID];
    NSString *urlText = ZMTestURLArticleWithoutPictureString;
    
    ZMGenericMessage *linkPreviewMessage = [ZMGenericMessage messageWithText:urlText nonce:messageNonce expiresAfter:nil];
    [self.mockTransportSession performRemoteChanges:^(__unused id<MockTransportSessionObjectCreation> session) {
        [mockConversation encryptAndInsertDataFromClient:senderClient toClient:selfClient data:linkPreviewMessage.data];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    //sanity check
    XCTAssertEqual(conversation.messages.count, 3lu);
    ZMClientMessage *message = [conversation.messages lastObject];
    XCTAssertEqualObjects(message.nonce, messageNonce);
    XCTAssertEqualObjects(message.textMessageData.messageText, urlText);
    XCTAssertNil(message.textMessageData.linkPreview);
    
    ZMArticleBuilder *articleBuilder = [ZMArticleBuilder new];
    articleBuilder.permanentUrl = urlText;
    articleBuilder.title = @"SomeTitle";
    articleBuilder.summary = @"SomeSummary";
    
    ZMLinkPreviewBuilder *builder = [ZMLinkPreviewBuilder new];
    builder.permanentUrl = builder.url = urlText;
    builder.urlOffset = 0;
    builder.article = [articleBuilder build];
    
    //when
    ZMLinkPreview *remoteLinkPreview = [builder build];
    linkPreviewMessage = [ZMGenericMessage messageWithText:urlText linkPreview:remoteLinkPreview nonce:messageNonce expiresAfter:nil];
    
    [self.mockTransportSession performRemoteChanges:^(__unused id<MockTransportSessionObjectCreation> session) {
        [mockConversation encryptAndInsertDataFromClient:senderClient toClient:selfClient data:linkPreviewMessage.data];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    //then
    [self checkForValidLinkPreviewInMessage:message expectedLinkPreview:remoteLinkPreview failureRecorder:NewFailureRecorder()];
}


- (void)testThatItUpdateMessageWhenReceivingLinkPreviewFollowUp_WithImage;
{
    // given
        XCTAssert([self login]);
    
    
    MockConversation *mockConversation = self.selfToUser1Conversation;
    [self prefetchRemoteClientByInsertingMessageInConversation:mockConversation];
    WaitForAllGroupsToBeEmpty(0.5);

    ZMConversation *conversation = [self conversationForMockConversation:mockConversation];
    MockUserClient *selfClient = [self.selfUser.clients anyObject];
    MockUserClient *senderClient = [self.user1.clients anyObject];
    
    NSUUID *messageNonce = [NSUUID createUUID];
    NSUUID *assetID = [NSUUID createUUID];
    NSString *urlText = ZMTestURLArticleWithPictureString;

    NSData *encryptedImageData, *otrKey, *sha256;
    [self createEncryptionDataWithOrignalAssetData:[self mediumJPEGData]
                                     encryptedData:&encryptedImageData otrKey:&otrKey sha256:&sha256];
    ZMAsset *imageAssetData = [self imageAssetWithAssetID:assetID assetToken:assetID otrKey:otrKey sha256:sha256];
    
    
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [session insertAssetWithID:assetID assetToken:assetID assetData:encryptedImageData contentType:@"image/jpeg"];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    
    ZMGenericMessage *linkPreviewMessage = [ZMGenericMessage messageWithText:urlText nonce:messageNonce expiresAfter:nil];
    [self.mockTransportSession performRemoteChanges:^(__unused id<MockTransportSessionObjectCreation> session) {
        [mockConversation encryptAndInsertDataFromClient:senderClient toClient:selfClient data:linkPreviewMessage.data];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    //sanity check
    XCTAssertEqual(conversation.messages.count, 3lu);
    ZMClientMessage *message = [conversation.messages lastObject];
    XCTAssertEqualObjects(message.nonce, messageNonce);
    XCTAssertEqualObjects(message.textMessageData.messageText, urlText);
    XCTAssertNil(message.textMessageData.linkPreview);
    
    //when
    ZMLinkPreview *remoteLinkPreview = [self.mockLinkPreviewDetector linkPreviewFromURLString:urlText asset:imageAssetData tweet:nil];
    linkPreviewMessage = [ZMGenericMessage messageWithText:urlText linkPreview:remoteLinkPreview nonce:messageNonce expiresAfter:nil];
    
    [self.mockTransportSession performRemoteChanges:^(__unused id<MockTransportSessionObjectCreation> session) {
        [mockConversation encryptAndInsertDataFromClient:senderClient toClient:selfClient data:linkPreviewMessage.data];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.userSession performChanges:^{
        [message requestImageDownload];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self checkForValidLinkPreviewInMessage:message expectedLinkPreview:remoteLinkPreview failureRecorder:NewFailureRecorder()];
}

@end


@implementation LinkPreviewTests (Ephemeral)

- (void)testThatItInsertCorrectLinkPreviewMessage_ArticleWithoutImage_ForEphemeral;
{
    // need to check mock transport if we have the image
    
        XCTAssert([self login]);
    
    NSString *text = ZMTestURLArticleWithoutPictureString;
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    conversation.localMessageDestructionTimeout = 10;
    
    ZMLinkPreview *expectedLinkPreview = [self.mockLinkPreviewDetector linkPreviewFromURLString:text includeAsset:NO includingTweet:NO];
    
    [self.userSession performChanges:^{
        [conversation appendMessageWithText:text];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssertEqual(conversation.messages.count, 2lu); //text message, then link preview message
    
    __block ZMClientMessage *message = conversation.messages.lastObject;
    XCTAssertTrue(message.isEphemeral);
    [self checkForValidLinkPreviewInMessage:message expectedLinkPreview:expectedLinkPreview failureRecorder:NewFailureRecorder()];

    NSManagedObjectContext *synMOC = self.userSession.syncManagedObjectContext;
    [synMOC performBlockAndWait:^{
        [synMOC zm_teardownMessageObfuscationTimer];
    }];
}

@end
