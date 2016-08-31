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

#import "ZMClientMessageTranscoder+Internal.h"
#import "ZMMessageTranscoder+Internal.h"
#import "ZMUpstreamInsertedObjectSync.h"
#import "ZMMessageExpirationTimer.h"
#import "ZMUpstreamTranscoder.h"
#import "ZMImagePreprocessingTracker.h"
#import "ZMDownstreamObjectSyncWithWhitelist.h"

#import "ZMClientRegistrationStatus.h"
#import "ZMLocalNotificationDispatcher.h"

#import "CBCryptoBox+UpdateEvents.h"
#import <zmessaging/zmessaging-Swift.h>
#import "ZMOperationLoop.h"



@interface ZMAssetClientMessage (ImagePredicates)

+ (NSPredicate *)filterForUploadingImageMessages;
+ (NSPredicate *)filterForImagesToBeDownloaded;

@end



@interface ZMClientMessageTranscoder()

@property (nonatomic) ZMUpstreamModifiedObjectSync *assetModifiedSync;
@property (nonatomic) ZMDownstreamObjectSyncWithWhitelist *downstreamSync;
@property (nonatomic) ClientMessageRequestFactory *requestsFactory;
@property (nonatomic) ZMImagePreprocessingTracker *imagePreprocessor;
@property (nonatomic, weak) ZMClientRegistrationStatus *clientRegistrationStatus;

@end


@implementation ZMClientMessageTranscoder

- (instancetype)initWithManagedObjectContext:(NSManagedObjectContext *)moc
                 localNotificationDispatcher:(ZMLocalNotificationDispatcher *)dispatcher
                    clientRegistrationStatus:(ZMClientRegistrationStatus *)clientRegistrationStatus;
{
    ZMUpstreamInsertedObjectSync *clientTextMessageUpstreamSync = [[ZMUpstreamInsertedObjectSync alloc] initWithTranscoder:self entityName:[ZMClientMessage entityName] filter:nil managedObjectContext:moc];
    ZMMessageExpirationTimer *messageTimer = [[ZMMessageExpirationTimer alloc] initWithManagedObjectContext:moc entityName:[ZMClientMessage entityName] localNotificationDispatcher:dispatcher filter:nil];
    
    self = [super initWithManagedObjectContext:moc
                    upstreamInsertedObjectSync:clientTextMessageUpstreamSync
                   localNotificationDispatcher:dispatcher
                        messageExpirationTimer:messageTimer];
    if (self) {
        
        // Asset upload
        NSPredicate *insertPredicate = [NSPredicate predicateWithFormat:@"%K != %@", ZMAssetClientMessageUploadedStateKey, @(ZMAssetUploadStateDone)];
        self.assetModifiedSync = [[ZMUpstreamModifiedObjectSync alloc] initWithTranscoder:self
                                                                                                        entityName:[ZMAssetClientMessage entityName]
                                                                                                   updatePredicate:insertPredicate
                                                                                                            filter:ZMAssetClientMessage.filterForUploadingImageMessages
                                                                                                        keysToSync:nil
                                                                                              managedObjectContext:moc];

        // Asset download
        self.downstreamSync = [[ZMDownstreamObjectSyncWithWhitelist alloc] initWithTranscoder:self
                                                                                   entityName:[ZMAssetClientMessage entityName]
                                                                 predicateForObjectsToDownload:ZMAssetClientMessage.filterForImagesToBeDownloaded
                                                                         managedObjectContext:moc];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didWhitelistAssetDownload:) name:ZMAssetClientMessage.ImageDownloadNotificationName object:nil];
        
        // Image preprocessing
        NSPredicate *needToProcessPredicate = [NSPredicate predicateWithFormat:@"(mediumGenericMessage.image.width == 0 || previewGenericMessage.image.width == 0) && delivered == NO"];
        NSPredicate *fetchPredicate = [NSPredicate predicateWithFormat:@"delivered == NO"];
        NSOperationQueue *preprocessQueue = [[NSOperationQueue alloc] init];
        self.imagePreprocessor = [[ZMImagePreprocessingTracker alloc] initWithManagedObjectContext:moc
                                                                              imageProcessingQueue:preprocessQueue
                                                                                    fetchPredicate:fetchPredicate
                                                                          needsProcessingPredicate:needToProcessPredicate
                                                                                       entityClass:ZMAssetClientMessage.class];
        
        // Others
        self.requestsFactory = [ClientMessageRequestFactory new];
        self.clientRegistrationStatus = clientRegistrationStatus;
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)didWhitelistAssetDownload:(NSNotification *)note
{
    ZM_WEAK(self);
    [self.managedObjectContext performGroupedBlock:^{
        ZM_STRONG(self);
        if(self == nil) {
            return;
        }
        NSManagedObjectID *objectID = (NSManagedObjectID *)note.object;
        ZMAssetClientMessage *imageMessage = (ZMAssetClientMessage *)[self.managedObjectContext existingObjectWithID:objectID error:nil];
        if(imageMessage != nil) {
            [self.downstreamSync whiteListObject:imageMessage];
        }
        [ZMOperationLoop notifyNewRequestsAvailable:self];
    }];
}

- (NSArray *)contextChangeTrackers
{
    NSMutableArray *trackers = [[super contextChangeTrackers] mutableCopy];
    [trackers addObject:self.assetModifiedSync];
    [trackers addObject:self.downstreamSync];
    [trackers addObject:self.imagePreprocessor];
    return trackers;
}

- (NSArray * __nonnull)requestGenerators
{
    NSMutableArray *generators = [[super requestGenerators] mutableCopy];
    [generators addObject:self.assetModifiedSync];
    [generators addObject:self.downstreamSync];
    return generators;
}

- (ZMTransportRequest *)requestForInsertingObject:(ZMClientMessage *)message
{
    //should be called only for not-image client messages
    ZMTransportRequest *request = [self.requestsFactory upstreamRequestForMessage:message forConversationWithId:message.conversation.remoteIdentifier];
    return request;
}

- (BOOL)shouldCreateRequestToSyncObject:(ZMAssetClientMessage *)message forKeys:(NSSet *)keys withSync:(id)sync
{
    NOT_USED(sync);
    ZMImageFormat format = [self imageFormatForKeys:keys message:message];
    if(format == ZMImageFormatInvalid) {
        // we will ultimately crash here when trying to create the request
        return YES;
    }
    if ([message.imageAssetStorage shouldReprocessForFormat:format]) {
        // before we create an upstream request we should check if we can (and should) process image data again
        // if we can we reschedule processing
        // this might cause a loop if the message can not be processed whatsoever
        [self scheduleImageProcessingForMessage:message format:format];
        [self.managedObjectContext saveOrRollback];
        return NO;
    }
    return YES;
}

- (ZMImageFormat)imageFormatForKeys:(NSSet *)keys message:(ZMAssetClientMessage *)message
{
    ZMImageFormat format = ZMImageFormatInvalid;
    
    if ([keys containsObject:ZMAssetClientMessageUploadedStateKey]) {
        switch (message.uploadState) {
            case ZMAssetUploadStateUploadingPlaceholder:
                format = ZMImageFormatPreview;
                break;
                
            case ZMAssetUploadStateUploadingFullAsset:
                format = ZMImageFormatMedium;
                break;
                
            case ZMAssetUploadStateDone:
            case ZMAssetUploadStateUploadingFailed:
            case ZMAssetUploadStateUploadingThumbnail:
                break;
        }
    }
    
    return format;
}

- (ZMUpstreamRequest *)requestForUpdatingObject:(ZMAssetClientMessage *)message forKeys:(NSSet *)keys
{
    ZMImageFormat format = [self imageFormatForKeys:keys message:message];
    if (format == ZMImageFormatInvalid) {
        ZMTrapUnableToGenerateRequest(keys, self);
        return nil;
    }
    
    ZMUpstreamRequest *request = [self requestForUpdatingAssetClientMessage:message format:format];
    if (request == nil) {
        // We will crash, but we should still delete the image
        [message.managedObjectContext deleteObject:message];
        [self.managedObjectContext saveOrRollback];
    }
    return request;
}

- (void)scheduleImageProcessingForMessage:(ZMAssetClientMessage *)message format:(ZMImageFormat)format
{
    // to trigger image processing we reset image properties to nil
    // this will make asset preprocessortracker from client message transcoder to pick up this image again
    ZMGenericMessage *genericMessage = [ZMGenericMessage messageWithMediumImageProperties:nil
                                                    processedImageProperties:nil
                                                              encryptionKeys:nil
                                                                       nonce:message.nonce.transportString
                                                                      format:format];
    [message addGenericMessage:genericMessage];
    [ZMOperationLoop notifyNewRequestsAvailable:self];
}

- (ZMUpstreamRequest *)requestForUpdatingAssetClientMessage:(ZMAssetClientMessage *)message format:(ZMImageFormat)format
{
    ZMTransportRequest *request = [self.requestsFactory upstreamRequestForAssetMessage:format message:message forConversationWithId:message.conversation.remoteIdentifier];
    if (request == nil) {
        return nil;
    }
    
    ZM_WEAK(self);
    [request addCompletionHandler:[ZMCompletionHandler handlerOnGroupQueue:self.managedObjectContext block:^(ZMTransportResponse *response) {
        if (response.result == ZMTransportResponseStatusSuccess) {
            ZM_STRONG(self);
            [message markAsSent];
            [ZMOperationLoop notifyNewRequestsAvailable:self]; //to send next image
        }
    }]];
    
    return [[ZMUpstreamRequest alloc] initWithKeys:[NSSet setWithObject:ZMAssetClientMessageUploadedStateKey] transportRequest:request];
}

- (void)updateInsertedObject:(ZMMessage *)message request:(ZMUpstreamRequest *)upstreamRequest response:(ZMTransportResponse *)response;
{
    [super updateInsertedObject:message request:upstreamRequest response:response];
    [(ZMClientMessage *)message parseUploadResponse:response clientDeletionDelegate:self.clientRegistrationStatus];
    
    // if it's reaction
    if ([message isKindOfClass:[ZMClientMessage class]] && ((ZMClientMessage *)message).genericMessage.hasReaction) {
        [message.managedObjectContext deleteObject:message];
    }

}

- (BOOL)updateUpdatedObject:(ZMAssetClientMessage *)message
            requestUserInfo:(NSDictionary *)requestUserInfo
                   response:(ZMTransportResponse *)response
                keysToParse:(NSSet *)keysToParse
{
    BOOL result = [super updateUpdatedObject:message requestUserInfo:requestUserInfo response:response keysToParse:keysToParse];
    
    if([keysToParse contains:ZMAssetClientMessageUploadedStateKey]) {
    
        switch (message.uploadState) {
            case ZMAssetUploadStateUploadingPlaceholder:
                message.uploadState = ZMAssetUploadStateUploadingFullAsset;
                [self.managedObjectContext.zm_imageAssetCache deleteAssetData:message.nonce format:ZMImageFormatPreview encrypted:NO];
                [self.managedObjectContext.zm_imageAssetCache deleteAssetData:message.nonce format:ZMImageFormatPreview encrypted:YES];
                result = YES; // We want to resynchronize this key in order to upload the full asset
                break;
                
            case ZMAssetUploadStateUploadingFullAsset: {
                message.uploadState = ZMAssetUploadStateDone;
                NSUUID *assetId = [NSUUID uuidWithTransportString:response.headers[@"Location"]];
                message.assetId = assetId;
                [self.managedObjectContext.zm_imageAssetCache deleteAssetData:message.nonce format:ZMImageFormatMedium encrypted:YES];
                [message resetLocallyModifiedKeys:[NSSet setWithObject:ZMAssetClientMessageUploadedStateKey]];
            }
                break;
                
            case ZMAssetUploadStateDone:
            case ZMAssetUploadStateUploadingFailed:
            case ZMAssetUploadStateUploadingThumbnail:
                break;
        }
    }
    
    [message parseUploadResponse:response clientDeletionDelegate:self.clientRegistrationStatus];    
    return result;
}

- (BOOL)shouldRetryToSyncAfterFailedToUpdateObject:(ZMClientMessage *)message request:(ZMUpstreamRequest *__unused)upstreamRequest response:(ZMTransportResponse *)response keysToParse:(NSSet * __unused)keys
{
    BOOL shouldRetry = [message parseUploadResponse:response clientDeletionDelegate:self.clientRegistrationStatus];
    if(!shouldRetry && [message isKindOfClass:ZMAssetClientMessage.class]) {
        ((ZMAssetClientMessage *)message).uploadState = ZMAssetUploadStateUploadingFailed;
    }
    return shouldRetry;
}


- (ZMManagedObject *)dependentObjectNeedingUpdateBeforeProcessingObject:(ZMClientMessage *)message;
{
    return message.dependendObjectNeedingUpdateBeforeProcessing;
}

- (ZMMessage *)messageFromUpdateEvent:(ZMUpdateEvent *)event
                       prefetchResult:(ZMFetchRequestBatchResult *)prefetchResult
{
    ZMMessage *message;
    switch (event.type) {
        case ZMUpdateEventConversationClientMessageAdd:
        case ZMUpdateEventConversationOtrMessageAdd:
        case ZMUpdateEventConversationOtrAssetAdd:
            message = [ZMOTRMessage createOrUpdateMessageFromUpdateEvent:event
                                                  inManagedObjectContext:self.managedObjectContext
                                                          prefetchResult:prefetchResult];
            break;
        default:
            return nil;
    }
    
    [message markAsSent];
    return message;
}

@end

@implementation ZMClientMessageTranscoder (ZMDownstreamMediumImageTranscoder)

- (ZMTransportRequest *)requestForFetchingObject:(ZMAssetClientMessage *)message downstreamSync:(ZMDownstreamObjectSync * __unused)downstreamSync;
{
    //if we have data stored already we don't need to make request
    //we just update message using this data
    NSData *existingData = [self.managedObjectContext.zm_imageAssetCache assetData:message.nonce format:ZMImageFormatMedium encrypted:NO];
    if (existingData == nil) {
        if (nil != message.imageMessageData) {
            return [self.requestsFactory requestToGetAsset:message.assetId.transportString inConversation:message.conversation.remoteIdentifier isEncrypted:message.isEncrypted];
        } else if (nil != message.fileMessageData) {
            return [self.requestsFactory requestToGetAsset:message.fileMessageData.thumbnailAssetID inConversation:message.conversation.remoteIdentifier isEncrypted:message.isEncrypted];
        }
        return nil;
    }
    else {
        [self updateObject:message withImageData:existingData];
        [self.managedObjectContext enqueueDelayedSave];
        return nil;
    }
}

- (void)updateObject:(ZMManagedObject *)object withResponse:(ZMTransportResponse *)response downstreamSync:(ZMDownstreamObjectSync * __unused)downstreamSync;
{
    [self updateObject:(ZMAssetClientMessage *)object withImageData:response.rawData];
}

- (void)deleteObject:(ZMAssetClientMessage *)imageMessage downstreamSync:(ZMDownstreamObjectSync * __unused)downstreamSync;
{
    [imageMessage.managedObjectContext deleteObject:imageMessage];
}

- (void)updateObject:(ZMAssetClientMessage *)imageMessage withImageData:(NSData *)mediumImageData;
{
    [imageMessage.imageAssetStorage updateMessageWithImageData:mediumImageData forFormat:ZMImageFormatMedium];
    // trigger change for image data (a computed property)
    NSManagedObjectContext *uiMOC = self.managedObjectContext.zm_userInterfaceContext;
    
    [uiMOC performGroupedBlock:^{
        ZMAssetClientMessage *message = [uiMOC existingObjectWithID:imageMessage.objectID error:nil];
        if (nil != message) {
            [uiMOC.globalManagedObjectContextObserver notifyNonCoreDataChangeInManagedObject:message];
        }
    }];
}

@end



@implementation ZMAssetClientMessage (ImagePredicates)

+ (NSPredicate *)filterForUploadingImageMessages
{
    return [NSPredicate predicateWithBlock:^BOOL(ZMAssetClientMessage  * _Nonnull message, __unused NSDictionary * _Nullable bindings) {
        return message.imageMessageData != nil &&
        (message.uploadState == ZMAssetUploadStateUploadingPlaceholder ||
         message.uploadState == ZMAssetUploadStateUploadingFullAsset) &&
        message.imageAssetStorage.mediumGenericMessage.image.width != 0 &&
        message.imageAssetStorage.previewGenericMessage.image.width != 0;
    }];
}

+ (NSPredicate *)filterForImagesToBeDownloaded
{
    return [NSPredicate predicateWithBlock:^BOOL(ZMAssetClientMessage * _Nonnull message, __unused NSDictionary * _Nullable bindings) {
        BOOL imageWithoutMedium = message.imageMessageData != nil && !message.hasDownloadedImage && message.assetId != nil;
        BOOL videoFileWithoutThumbnail = message.fileMessageData != nil && !message.hasDownloadedImage && message.fileMessageData.thumbnailAssetID != nil;
        return imageWithoutMedium || videoFileWithoutThumbnail;
    }];
}

@end
