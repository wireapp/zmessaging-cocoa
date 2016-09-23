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
@import ZMUtilities;
@import ZMCSystem;
@import ZMTransport;
@import CoreGraphics;
@import ImageIO;
@import ZMCDataModel;
@import WireRequestStrategy;

#import "ZMAssetTranscoder.h"

@interface ZMAssetTranscoder ()

@property (nonatomic) ZMDownstreamObjectSyncWithWhitelist *downstreamMediumImageSync;

@end



@interface ZMAssetTranscoder (ImagePreprocessing) <ZMDownstreamTranscoder>
@end



@implementation ZMAssetTranscoder

ZM_EMPTY_ASSERTING_INIT()

- (instancetype)initWithManagedObjectContext:(NSManagedObjectContext *)moc;
{
    self = [super initWithManagedObjectContext:moc];
    if (self) {
        
        NSPredicate *mediumDataNeedsToBeDownloaded = [NSPredicate predicateWithFormat:@"mediumDataLoaded == NO AND mediumRemoteIdentifier_data != NIL"];
        self.downstreamMediumImageSync = [[ZMDownstreamObjectSyncWithWhitelist alloc] initWithTranscoder:self
                                                                                              entityName:ZMImageMessage.entityName
                                                                           predicateForObjectsToDownload:mediumDataNeedsToBeDownloaded
                                                                                    managedObjectContext:self.managedObjectContext];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didWhitelistAssetDownload:) name:ZMAssetClientMessage.ImageDownloadNotificationName object:nil];
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
        ZMImageMessage *imageMessage = (ZMImageMessage *)[self.managedObjectContext existingObjectWithID:objectID error:nil];
        if(imageMessage != nil) {
            [self.downstreamMediumImageSync whiteListObject:imageMessage];
        }
        [ZMRequestAvailableNotification notifyNewRequestsAvailable:self];
    }];
}

- (BOOL)hasOutstandingItems;
{
    return (self.downstreamMediumImageSync.hasOutstandingItems);
}

- (BOOL)isSlowSyncDone;
{
    return YES;
}

- (void)setNeedsSlowSync;
{
}

- (NSArray *)requestGenerators;
{
    return @[self.downstreamMediumImageSync];
}

- (void)processEvents:(NSArray<ZMUpdateEvent *> *)events
           liveEvents:(__unused BOOL)liveEvents
       prefetchResult:(ZMFetchRequestBatchResult *)prefetchResult;
{
    NSArray *conversationAssetAddEvents = [events filterWithBlock:^BOOL(ZMUpdateEvent* event) {
        return event.type == ZMUpdateEventConversationAssetAdd;
    }];
    
    if(conversationAssetAddEvents.count == 0) {
        return;
    }
    
    NSMutableSet *conversationsToSort = [NSMutableSet set];
    for(ZMImageMessage *message in [self processAssetAddEvents:conversationAssetAddEvents prefetchResult:prefetchResult]) {
        if(message != nil && message.conversation != nil) {
            [conversationsToSort addObject:message.conversation];
        }
    }
    
    for(ZMConversation *conversation in conversationsToSort) {
        [conversation sortMessages];
    }
}

- (NSArray<ZMImageMessage *>*)processAssetAddEvents:(NSArray<ZMUpdateEvent *>*)events prefetchResult:(ZMFetchRequestBatchResult *)prefetchResult;
{
    return [events mapWithBlock:^id(ZMUpdateEvent *event) {
        return [ZMImageMessage createOrUpdateMessageFromUpdateEvent:event
                                             inManagedObjectContext:self.managedObjectContext
                                                     prefetchResult:prefetchResult];
    }];
}

- (NSArray *)contextChangeTrackers
{
    return @[self.downstreamMediumImageSync];
}

- (NSSet<NSUUID *> *)messageNoncesToPrefetchToProcessEvents:(NSArray<ZMUpdateEvent *> *)events
{
    return [events mapWithBlock:^NSUUID *(ZMUpdateEvent *event) {
        switch (event.type) {
            case ZMUpdateEventConversationAssetAdd:
                return event.messageNonce;
                
            default:
                return nil;
        }
    }].set;
}

@end





@implementation ZMAssetTranscoder (ZMDownstreamTranscoder)

- (ZMTransportRequest *)requestForFetchingObject:(ZMImageMessage *)imageMessage downstreamSync:(ZMDownstreamObjectSync * __unused)downstreamSync;
{
    NSString *lastURLPart = [NSString stringWithFormat:@"%@?conv_id=%@", imageMessage.mediumRemoteIdentifier.transportString, imageMessage.conversation.remoteIdentifier.transportString];
    NSString *path = [NSString pathWithComponents:@[@"/", @"assets", lastURLPart]];
    return [ZMTransportRequest imageGetRequestFromPath:path];
}

- (void)updateObject:(ZMManagedObject *)object withResponse:(ZMTransportResponse *)response downstreamSync:(ZMDownstreamObjectSync * __unused)downstreamSync;
{
    [self updateObject:(ZMImageMessage *)object withImageData:response.imageData];
}

- (void)deleteObject:(ZMImageMessage *)imageMessage downstreamSync:(ZMDownstreamObjectSync * __unused)downstreamSync;
{
    [imageMessage.managedObjectContext deleteObject:imageMessage];
}

- (void)updateObject:(ZMImageMessage *)imageMessage withImageData:(NSData *)mediumImageData;
{
    NSData *mediumData = mediumImageData ?: [NSData data];
    [imageMessage setImageData:mediumData forFormat:ZMImageFormatMedium properties:nil];
}

@end
