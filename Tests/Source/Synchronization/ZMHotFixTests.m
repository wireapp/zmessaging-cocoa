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
@import ZMCDataModel;

#import "MessagingTest.h"
#import "ZMHotFix.h"
#import "ZMHotFixDirectory.h"
#import <zmessaging/zmessaging-Swift.h>

@interface VersionNumberTests : MessagingTest
@end


@implementation VersionNumberTests

- (void)setUp {
    [super setUp];
}

- (void)tearDown
{
    [super tearDown];
}

- (void)testThatItComparesCorrectly
{
    // given
    NSString *version1String = @"0.1";
    NSString *version2String = @"1.0";
    NSString *version3String = @"1.0";
    NSString *version4String = @"1.0.1";
    NSString *version5String = @"1.1";
    
    ZMVersion *version1 = [[ZMVersion alloc] initWithVersionString:version1String];
    ZMVersion *version2 = [[ZMVersion alloc] initWithVersionString:version2String];
    ZMVersion *version3 = [[ZMVersion alloc] initWithVersionString:version3String];
    ZMVersion *version4 = [[ZMVersion alloc] initWithVersionString:version4String];
    ZMVersion *version5 = [[ZMVersion alloc] initWithVersionString:version5String];

    // then
    XCTAssertEqual([version1 compareWithVersion:version2], NSOrderedAscending);
    XCTAssertEqual([version1 compareWithVersion:version3], NSOrderedAscending);
    XCTAssertEqual([version1 compareWithVersion:version4], NSOrderedAscending);
    XCTAssertEqual([version1 compareWithVersion:version5], NSOrderedAscending);

    XCTAssertEqual([version2 compareWithVersion:version1], NSOrderedDescending);
    XCTAssertEqual([version2 compareWithVersion:version3], NSOrderedSame);
    XCTAssertEqual([version2 compareWithVersion:version4], NSOrderedAscending);
    XCTAssertEqual([version2 compareWithVersion:version5], NSOrderedAscending);

    XCTAssertEqual([version3 compareWithVersion:version1], NSOrderedDescending);
    XCTAssertEqual([version3 compareWithVersion:version2], NSOrderedSame);
    XCTAssertEqual([version3 compareWithVersion:version4], NSOrderedAscending);
    XCTAssertEqual([version3 compareWithVersion:version5], NSOrderedAscending);

    XCTAssertEqual([version4 compareWithVersion:version1], NSOrderedDescending);
    XCTAssertEqual([version4 compareWithVersion:version2], NSOrderedDescending);
    XCTAssertEqual([version4 compareWithVersion:version3], NSOrderedDescending);
    XCTAssertEqual([version4 compareWithVersion:version5], NSOrderedAscending);
    
    XCTAssertEqual([version5 compareWithVersion:version1], NSOrderedDescending);
    XCTAssertEqual([version5 compareWithVersion:version2], NSOrderedDescending);
    XCTAssertEqual([version5 compareWithVersion:version3], NSOrderedDescending);
    XCTAssertEqual([version5 compareWithVersion:version4], NSOrderedDescending);
}

@end




@interface FakeHotFixDirectory : ZMHotFixDirectory
@property (nonatomic) NSUInteger method1CallCount;
@property (nonatomic) NSUInteger method2CallCount;
@property (nonatomic) NSUInteger method3CallCount;

@end

@implementation FakeHotFixDirectory

- (void)methodOne:(NSObject *)object
{
    NOT_USED(object);
    self.method1CallCount++;
}

- (void)methodTwo:(NSObject *)object
{
    NOT_USED(object);
    self.method2CallCount++;
}

- (void)methodThree:(NSObject *)object
{
    NOT_USED(object);
    self.method3CallCount++;
}

- (NSArray *)patches
{
    return @[
             [ZMHotFixPatch patchWithVersion:@"1.0" patchCode:^(NSManagedObjectContext *moc){ [self methodOne:moc]; [self methodThree:moc]; }],
             [ZMHotFixPatch patchWithVersion:@"0.1" patchCode:^(NSManagedObjectContext *moc){ [self methodTwo:moc]; }],
    ];
}

@end



@interface PushTokenNotificationObserver : NSObject
@property (nonatomic) NSUInteger notificationCount;
@end


@implementation PushTokenNotificationObserver

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.notificationCount = 0;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(notificationFired) name:ZMUserSessionResetPushTokensNotificationName object:nil];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)notificationFired
{
    self.notificationCount++;
}

@end



@interface ZMHotFixTests : MessagingTest

@property (nonatomic) FakeHotFixDirectory *fakeHotFixDirectory;
@property (nonatomic) ZMHotFix *sut;

@end


@implementation ZMHotFixTests

- (void)setUp {
    [super setUp];
    
    self.fakeHotFixDirectory = [[FakeHotFixDirectory alloc] init];
    self.sut = [[ZMHotFix alloc] initWithHotFixDirectory:self.fakeHotFixDirectory syncMOC:self.syncMOC];
    }

- (void)tearDown {
    self.fakeHotFixDirectory = nil;
    [super tearDown];
}

- (void)saveNewVersion
{
    [self.syncMOC setPersistentStoreMetadata:@"0.1" forKey:@"lastSavedVersion"];
}

- (void)testThatItOnlyCallsMethodsForVersionsNewerThanTheLastSavedVersion
{
    // given
    [self saveNewVersion];

    // when
    [self.sut applyPatchesForCurrentVersion:@"1.0"];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.fakeHotFixDirectory.method1CallCount, 1u);
    XCTAssertEqual(self.fakeHotFixDirectory.method3CallCount, 1u);
    XCTAssertEqual(self.fakeHotFixDirectory.method2CallCount, 0u);
}

- (void)testThatItCallsAllMethodsIfThereIsNoLastSavedVersion
{
    // when
    [self.sut applyPatchesForCurrentVersion:@"1.0"];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.fakeHotFixDirectory.method1CallCount, 1u);
    XCTAssertEqual(self.fakeHotFixDirectory.method2CallCount, 1u);
    XCTAssertEqual(self.fakeHotFixDirectory.method3CallCount, 1u);
}

- (void)testThatItRunsFixesOnlyOnce
{
    // given
    [self saveNewVersion];
    
    // when
    [self.sut applyPatchesForCurrentVersion:@"1.0"];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.fakeHotFixDirectory.method1CallCount, 1u);
    
    // and when
    [self.sut applyPatchesForCurrentVersion:@"1.0"];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.fakeHotFixDirectory.method1CallCount, 1u);
}

- (void)testThatItSetsTheCurrentVersionAfterApplyingTheFixes
{
    // given
    [self saveNewVersion];
    
    // when
    [self.sut applyPatchesForCurrentVersion:@"1.2"];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    NSString *newVersion = [self.syncMOC persistentStoreMetadataForKey:@"lastSavedVersion"];
    XCTAssertEqualObjects(newVersion, @"1.2");
}


@end




@implementation ZMHotFixTests (CurrentFixes)

- (void)testThatItSetsTheLastReadOfAPendingConnectionRequest
{
    // given
    ZMEventID *lastReadEventID = self.createEventID;
    ZMEventID *lastEventID = self.createEventID;
    XCTAssertEqual([lastEventID compare:lastReadEventID], NSOrderedDescending);
    
    __block ZMConversation *conversation;
    
    [self.syncMOC performGroupedBlockAndWait:^{
        conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.connection = [ZMConnection insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.connection.status = ZMConnectionStatusPending;
        conversation.remoteIdentifier = [NSUUID UUID];
        conversation.conversationType = ZMConversationTypeConnection;
        
        conversation.lastReadEventID = lastReadEventID;
        conversation.lastEventID = lastEventID;
        
        [self.syncMOC saveOrRollback];
        XCTAssertNotEqualObjects(conversation.lastReadEventID, lastEventID);
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    self.sut = [[ZMHotFix alloc] initWithSyncMOC:self.syncMOC];
    [self.sut applyPatchesForCurrentVersion:@"1.0"];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqualObjects(conversation.lastReadEventID, lastEventID);
}

- (void)testThatItSetsTheLastReadOfClearedConversationsWithZeroMessages
{
    // given
    ZMEventID *lastReadEventID = self.createEventID;
    ZMEventID *lastEventID = self.createEventID;
    XCTAssertEqual([lastEventID compare:lastReadEventID], NSOrderedDescending);
    
    __block ZMConversation *conversation;
    
    [self.syncMOC performGroupedBlockAndWait:^{
        conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.remoteIdentifier = [NSUUID UUID];
        conversation.conversationType = ZMConversationTypeOneOnOne;
        
        conversation.clearedEventID = lastReadEventID;
        conversation.lastReadEventID = lastReadEventID;
        conversation.lastEventID = lastEventID;
        
        [self.syncMOC saveOrRollback];
        XCTAssertNotEqualObjects(conversation.lastReadEventID, lastEventID);
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    self.sut = [[ZMHotFix alloc] initWithSyncMOC:self.syncMOC];
    [self.sut applyPatchesForCurrentVersion:@"1.0"];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqualObjects(conversation.lastReadEventID, lastEventID);
}

- (void)testThatItRemovesTheFirstAddedSystemMessagesWhenUpdatingTo1_26
{
    // given
    __block ZMConversation *conversation;
    __block ZMSystemMessage *addedMessage;
    __block NSOrderedSet <ZMMessage *>*messages;
    NSString *text = @"Some Text";
    
    [self.syncMOC performGroupedBlockAndWait:^{
        conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.conversationType = ZMConversationTypeGroup;
    
        addedMessage = [ZMSystemMessage insertNewObjectInManagedObjectContext:self.syncMOC];
        addedMessage.systemMessageType = ZMSystemMessageTypeParticipantsAdded;
        addedMessage.eventID = [ZMEventID eventIDWithMajor:1 minor:3];
        [conversation sortedAppendMessage:addedMessage];
        
        [conversation appendMessageWithText:text];
        ZMSystemMessage *secondAddedMessage = [ZMSystemMessage insertNewObjectInManagedObjectContext:self.syncMOC];
        secondAddedMessage.systemMessageType = ZMSystemMessageTypeParticipantsAdded;
        secondAddedMessage.eventID = [ZMEventID eventIDWithMajor:3 minor:3];
        [conversation sortedAppendMessage:secondAddedMessage];
        
        messages = conversation.messages;
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertEqual(messages.count, 3lu);
    XCTAssertEqualObjects(messages.firstObject, addedMessage);
    XCTAssertEqualObjects(messages.lastObject.class, ZMSystemMessage.class);
    
    // when
    self.sut = [[ZMHotFix alloc] initWithSyncMOC:self.syncMOC];
    [self.sut applyPatchesForCurrentVersion:@"38.58"];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(conversation.messages.count, 3lu);
    XCTAssertEqualObjects((messages[1]).textMessageData.messageText, text);
    XCTAssertEqualObjects(messages.firstObject.class, ZMSystemMessage.class);
}

- (void)testThatItRemovesConnectionRequestSystemMessagesWhenUpdatingTo1_26
{
    // given
    __block ZMConversation *conversation;
    __block ZMSystemMessage *addedMessage;
    __block NSOrderedSet <ZMMessage *>*messages;
    NSString *text = @"Some Text";
    
    [self.syncMOC performGroupedBlockAndWait:^{
        conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.conversationType = ZMConversationTypeOneOnOne;
        
        addedMessage = [ZMSystemMessage insertNewObjectInManagedObjectContext:self.syncMOC];
        addedMessage.systemMessageType = ZMSystemMessageTypeConnectionRequest;
        [conversation sortedAppendMessage:addedMessage];
        
        [conversation appendMessageWithText:text];
        messages = conversation.messages;
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertEqual(messages.count, 2lu);
    XCTAssertEqual(messages.firstObject.systemMessageData.systemMessageType, ZMSystemMessageTypeConnectionRequest);
    XCTAssertEqualObjects(messages.firstObject, addedMessage);
    XCTAssertEqualObjects(messages.lastObject.textMessageData.messageText, text);
    
    // when
    self.sut = [[ZMHotFix alloc] initWithSyncMOC:self.syncMOC];
    [self.sut applyPatchesForCurrentVersion:@"38.58"];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(conversation.messages.count, 1lu);
    XCTAssertEqualObjects(messages.lastObject.textMessageData.messageText, text);
}

- (void)testThatItSetsTheLastReadOfALeftConversation
{
    // given
    ZMEventID *lastReadEventID = self.createEventID;
    ZMEventID *lastEventID = self.createEventID;
    XCTAssertEqual([lastEventID compare:lastReadEventID], NSOrderedDescending);
    
    __block ZMConversation *conversation;
    
    [self.syncMOC performGroupedBlockAndWait:^{
        conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.remoteIdentifier = [NSUUID UUID];
        conversation.conversationType = ZMConversationTypeGroup;
        [conversation appendMessageWithText:@"foo"];
        [conversation appendMessageWithText:@"bar"];
        conversation.isSelfAnActiveMember = NO;
        
        conversation.clearedEventID = lastReadEventID;
        conversation.lastReadEventID = lastReadEventID;
        conversation.lastEventID = lastEventID;
        
        [self.syncMOC saveOrRollback];
        XCTAssertNotEqualObjects(conversation.lastReadEventID, lastEventID);
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    self.sut = [[ZMHotFix alloc] initWithSyncMOC:self.syncMOC];
    [self.sut applyPatchesForCurrentVersion:@"1.0"];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqualObjects(conversation.lastReadEventID, lastEventID);
}

- (void)testThatItSendsOutResetPushTokenNotificationVersion_40_4
{
    // given
    PushTokenNotificationObserver *observer = [[PushTokenNotificationObserver alloc] init];
    
    // when
    self.sut = [[ZMHotFix alloc] initWithSyncMOC:self.syncMOC];
    [self.sut applyPatchesForCurrentVersion:@"40.4"];
    WaitForAllGroupsToBeEmpty(0.5);

    NSString *newVersion = [self.syncMOC persistentStoreMetadataForKey:@"lastSavedVersion"];
    XCTAssertEqualObjects(newVersion, @"40.4");
    
    [self.sut applyPatchesForCurrentVersion:@"40.4"];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(observer.notificationCount, 1lu);
    
    // when
    [self.sut applyPatchesForCurrentVersion:@"40.5"];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(observer.notificationCount, 1lu);
}

- (void)testThatItRemovesTheSharingExtensionURLs
{
    // given
    NSURL *directoryURL = [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:[NSUserDefaults groupName]];
    NSURL *imageURL = [directoryURL URLByAppendingPathComponent:@"profile_images"];
    NSURL *conversationUrl = [directoryURL URLByAppendingPathComponent:@"conversations"];
    
    [[NSFileManager defaultManager] createDirectoryAtURL:imageURL withIntermediateDirectories:YES attributes:nil error:nil];
    [[NSFileManager defaultManager] createDirectoryAtURL:conversationUrl withIntermediateDirectories:YES attributes:nil error:nil];

    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:[imageURL relativePath]]);
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:[conversationUrl relativePath]]);
    
    // when
    self.sut = [[ZMHotFix alloc] initWithSyncMOC:self.syncMOC];
    [self.sut applyPatchesForCurrentVersion:@"40.23"];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:[imageURL relativePath]]);
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:[conversationUrl relativePath]]);
}

- (void)testThatItCopiesTheAPSDecryptionKeysFromKeyChainToSelfClient_41_43
{
    // given
    UserClient *userClient = [self createSelfClient];
    NSData *encryptionKey = [NSData randomEncryptionKey];
    NSData *verificationKey = [NSData randomEncryptionKey];
    
    [ZMKeychain setData:verificationKey forAccount:@"APSVerificationKey"];
    [ZMKeychain setData:encryptionKey forAccount:@"APSDecryptionKey"];

    // when
    self.sut = [[ZMHotFix alloc] initWithSyncMOC:self.syncMOC];
    [self.sut applyPatchesForCurrentVersion:@"41.42"];
    WaitForAllGroupsToBeEmpty(0.5);
    
    NSString *newVersion = [self.syncMOC persistentStoreMetadataForKey:@"lastSavedVersion"];
    XCTAssertEqualObjects(newVersion, @"41.42");
    
    // then
    XCTAssertEqualObjects(userClient.apsVerificationKey, verificationKey);
    XCTAssertEqualObjects(userClient.apsDecryptionKey, encryptionKey);
    XCTAssertFalse(userClient.needsToUploadSignalingKeys);
    XCTAssertFalse([userClient hasLocalModificationsForKey:@"needsToUploadSignalingKeys"]);
    
    // and when
    // the keys change and afterwards we are updating again
    userClient.apsDecryptionKey = [NSData randomEncryptionKey];
    userClient.apsVerificationKey = [NSData randomEncryptionKey];
    
    [self.sut applyPatchesForCurrentVersion:@"41.43"];
    WaitForAllGroupsToBeEmpty(0.5);
    
    NSString *newVersion2 = [self.syncMOC persistentStoreMetadataForKey:@"lastSavedVersion"];
    XCTAssertEqualObjects(newVersion2, @"41.43");
    
    // then
    // we didn't overwrite the keys witht the old ones stored in the keychain
    XCTAssertNotEqualObjects(userClient.apsVerificationKey, verificationKey);
    XCTAssertNotEqualObjects(userClient.apsDecryptionKey, encryptionKey);
    
    [ZMKeychain deleteAllKeychainItemsWithAccountName:@"APSVerificationKey"];
    [ZMKeychain deleteAllKeychainItemsWithAccountName:@"APSDecryptionKey"];
}

- (void)testThatItSetsNeedsToUploadSignalingKeysIfKeysNotPresentInKeyChain_41_43
{
    // given
    UserClient *userClient = [self createSelfClient];
    XCTAssertFalse(userClient.needsToUploadSignalingKeys);
    XCTAssertFalse([userClient hasLocalModificationsForKey:@"needsToUploadSignalingKeys"]);
    
    // when
    self.sut = [[ZMHotFix alloc] initWithSyncMOC:self.syncMOC];
    [self.sut applyPatchesForCurrentVersion:@"41.42"];
    WaitForAllGroupsToBeEmpty(0.5);
    
    NSString *newVersion = [self.syncMOC persistentStoreMetadataForKey:@"lastSavedVersion"];
    XCTAssertEqualObjects(newVersion, @"41.42");
    
    // then
    XCTAssertTrue(userClient.needsToUploadSignalingKeys);
    XCTAssertTrue([userClient hasLocalModificationsForKey:@"needsToUploadSignalingKeys"]);
    
    // and when
    // we created and stored signaling keys and are updatign again
    userClient.apsVerificationKey = [NSData randomEncryptionKey];
    userClient.needsToUploadSignalingKeys = NO;
    [userClient resetLocallyModifiedKeys:[NSSet setWithObject:@"needsToUploadSignalingKeys"]];
    
    [self.sut applyPatchesForCurrentVersion:@"41.43"];
    WaitForAllGroupsToBeEmpty(0.5);
    
    NSString *newVersion2 = [self.syncMOC persistentStoreMetadataForKey:@"lastSavedVersion"];
    XCTAssertEqualObjects(newVersion2, @"41.43");

    // then
    // we are not reuploading the keys
    XCTAssertFalse(userClient.needsToUploadSignalingKeys);
    XCTAssertFalse([userClient hasLocalModificationsForKey:@"needsToUploadSignalingKeys"]);
}

- (void)testThatItSetsNotUploadedAssetClientMessagesToFailedAndAlsoExpiresFailedImageMessages_42_11
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
    conversation.conversationType = ZMConversationTypeOneOnOne;
    
    ZMAssetClientMessage *uploadedImageMessage = [conversation appendOTRMessageWithImageData:self.mediumJPEGData nonce:NSUUID.createUUID];
    [uploadedImageMessage markAsSent];
    uploadedImageMessage.uploadState = ZMAssetUploadStateDone;
    uploadedImageMessage.assetId = NSUUID.createUUID;
    XCTAssertTrue(uploadedImageMessage.delivered);
    XCTAssertTrue(uploadedImageMessage.hasDownloadedImage);
    XCTAssertEqual(uploadedImageMessage.uploadState, ZMAssetUploadStateDone);
    
    ZMAssetClientMessage *notUploadedImageMessage = [conversation appendOTRMessageWithImageData:self.mediumJPEGData nonce:NSUUID.createUUID];
    notUploadedImageMessage.uploadState = ZMAssetUploadStateUploadingFullAsset;
    XCTAssertFalse(notUploadedImageMessage.delivered);
    XCTAssertTrue(notUploadedImageMessage.hasDownloadedImage);
    XCTAssertEqual(notUploadedImageMessage.uploadState, ZMAssetUploadStateUploadingFullAsset);
    
    ZMAssetClientMessage *uploadedFileMessage = (id)[conversation appendMessageWithFileMetadata:[[ZMVideoMetadata alloc] initWithFileURL:self.testVideoFileURL thumbnail:self.verySmallJPEGData]];
    [uploadedFileMessage markAsSent];
    uploadedFileMessage.uploadState = ZMAssetUploadStateDone;
    uploadedFileMessage.assetId = NSUUID.createUUID;
    XCTAssertTrue(uploadedFileMessage.delivered);
    XCTAssertTrue(uploadedFileMessage.hasDownloadedImage);
    XCTAssertEqual(uploadedFileMessage.uploadState, ZMAssetUploadStateDone);
    
    ZMAssetClientMessage *notUploadedFileMessage = (id)[conversation appendMessageWithFileMetadata:[[ZMVideoMetadata alloc] initWithFileURL:self.testVideoFileURL thumbnail:self.verySmallJPEGData]];
    [notUploadedFileMessage markAsSent];
    notUploadedFileMessage.uploadState = ZMAssetUploadStateDone;
    XCTAssertTrue(notUploadedFileMessage.delivered);
    XCTAssertTrue(notUploadedFileMessage.hasDownloadedImage);
    XCTAssertEqual(notUploadedFileMessage.uploadState, ZMAssetUploadStateDone);
    
    XCTAssertTrue([self.syncMOC saveOrRollback]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    self.sut = [[ZMHotFix alloc] initWithSyncMOC:self.syncMOC];
    [self.sut applyPatchesForCurrentVersion:@"42.11"];
    WaitForAllGroupsToBeEmpty(0.5);
    
    NSString *newVersion = [self.syncMOC persistentStoreMetadataForKey:@"lastSavedVersion"];
    XCTAssertEqualObjects(newVersion, @"42.11");
    
    // then
    XCTAssertTrue(uploadedImageMessage.delivered);
    XCTAssertTrue(uploadedImageMessage.hasDownloadedImage);
    XCTAssertEqual(uploadedImageMessage.uploadState, ZMAssetUploadStateDone);
    
    XCTAssertFalse(notUploadedImageMessage.delivered);
    XCTAssertTrue(notUploadedImageMessage.hasDownloadedImage);
    XCTAssertEqual(notUploadedImageMessage.uploadState, ZMAssetUploadStateUploadingFailed);
    
    XCTAssertTrue(uploadedFileMessage.delivered);
    XCTAssertTrue(uploadedFileMessage.hasDownloadedImage);
    XCTAssertEqual(uploadedFileMessage.uploadState, ZMAssetUploadStateDone);
    
    XCTAssertTrue(notUploadedFileMessage.delivered);
    XCTAssertTrue(notUploadedFileMessage.hasDownloadedImage);
    XCTAssertEqual(notUploadedFileMessage.uploadState, ZMAssetUploadStateUploadingFailed);
}

- (void)testThatItAddANewConversationSystemMessageForAllOneOnOneAndGroupConversation_HasHistory_44_4;
{
    // given
    [self.syncMOC setPersistentStoreMetadata:@YES forKey:@"HasHistory"];
    
    ZMConversation *oneOnOneConversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
    oneOnOneConversation.conversationType = ZMConversationTypeOneOnOne;
    
    ZMConversation *groupConversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
    groupConversation.conversationType = ZMConversationTypeGroup;
    
    ZMConversation *selfConversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
    selfConversation.conversationType = ZMConversationTypeSelf;
    
    ZMConversation *connectionConversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
    connectionConversation.conversationType = ZMConversationTypeConnection;
    XCTAssertTrue([self.syncMOC saveOrRollback]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssertEqual(oneOnOneConversation.messages.count, 0u);
    XCTAssertEqual(groupConversation.messages.count, 0u);
    XCTAssertEqual(selfConversation.messages.count, 0u);
    XCTAssertEqual(connectionConversation.messages.count, 0u);
    
    // when
    self.sut = [[ZMHotFix alloc] initWithSyncMOC:self.syncMOC];
    [self.sut applyPatchesForCurrentVersion:@"44.4"];
    WaitForAllGroupsToBeEmpty(0.5);
    
    NSString *newVersion = [self.syncMOC persistentStoreMetadataForKey:@"lastSavedVersion"];
    XCTAssertEqualObjects(newVersion, @"44.4");
    
    // then
    XCTAssertEqual(oneOnOneConversation.messages.count, 0u);
    
    XCTAssertEqual(groupConversation.messages.count, 1u);
    ZMSystemMessage *message = groupConversation.messages.lastObject;
    XCTAssertEqual(message.systemMessageType, ZMSystemMessageTypeNewConversation);
    
    XCTAssertEqual(selfConversation.messages.count, 0u);

    XCTAssertEqual(connectionConversation.messages.count, 0u);
}

- (void)testThatItRemovesPendingConfirmationsForDeletedMessages_54_0_1
{
    // given
    [self.syncMOC setPersistentStoreMetadata:@YES forKey:@"HasHistory"];
    
    ZMConversation *oneOnOneConversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
    oneOnOneConversation.conversationType = ZMConversationTypeOneOnOne;
    oneOnOneConversation.remoteIdentifier = [NSUUID UUID];
    
    ZMUser *otherUser = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
    otherUser.remoteIdentifier = [NSUUID UUID];
    ZMClientMessage* incomingMessage = (ZMClientMessage *)[oneOnOneConversation appendMessageWithText:@"Test"];
    incomingMessage.sender = otherUser;
    
    ZMClientMessage* confirmation = [incomingMessage confirmReception];
    [self.syncMOC saveOrRollback];

    XCTAssertNotNil(confirmation);
    XCTAssert(!confirmation.isDeleted);
    
    [incomingMessage setVisibleInConversation:nil];
    [incomingMessage setHiddenInConversation:oneOnOneConversation];
    
    // when
    self.sut = [[ZMHotFix alloc] initWithSyncMOC:self.syncMOC];
    [self.sut applyPatchesForCurrentVersion:@"54.0.1"];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.syncMOC saveOrRollback];
    
    // then
    XCTAssertNil(confirmation.managedObjectContext);
}

- (NSURL *)testVideoFileURL
{
    NSBundle *bundle = [NSBundle bundleForClass:self.class];
    
    NSURL *url = [bundle URLForResource:@"video" withExtension:@"mp4"];
    if (nil == url) XCTFail("Unable to load video fixture from disk");
    return url;
}

@end

