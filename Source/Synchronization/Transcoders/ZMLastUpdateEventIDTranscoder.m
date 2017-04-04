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


@import WireTransport;

#import "ZMLastUpdateEventIDTranscoder+Internal.h"
#import "ZMObjectStrategyDirectory.h"
#import "ZMMissingUpdateEventsTranscoder+Internal.h"
#import <WireSyncEngine/WireSyncEngine-Swift.h>

@interface ZMLastUpdateEventIDTranscoder ()

@property (nonatomic) ZMSingleRequestSync *lastUpdateEventIDSync;
@property (nonatomic, weak) id<ZMObjectStrategyDirectory> directory;
@property (nonatomic) NSUUID *lastUpdateEventID;
@end


@implementation ZMLastUpdateEventIDTranscoder

- (instancetype)initWithManagedObjectContext:(NSManagedObjectContext *)moc {
    NOT_USED(moc);
    RequireString(NO, "Use the other init");
    return nil;
}

- (instancetype)initWithManagedObjectContext:(NSManagedObjectContext *)moc objectDirectory:(id<ZMObjectStrategyDirectory>)directory;
{
    self = [super initWithManagedObjectContext:moc];
    if(self) {
        self.directory = directory;
        self.lastUpdateEventIDSync = [[ZMSingleRequestSync alloc] initWithSingleRequestTranscoder:self managedObjectContext:moc];
    }
    return self;
}

- (void)startRequestingLastUpdateEventIDWithoutPersistingIt
{
    [self.lastUpdateEventIDSync resetCompletionState];
    [self.lastUpdateEventIDSync readyForNextRequest];
}

- (void)persistLastUpdateEventID
{
    if(self.lastUpdateEventID != nil) {
        ZMMissingUpdateEventsTranscoder *noteSync = [self.directory missingUpdateEventsTranscoder];
        noteSync.lastUpdateEventID = self.lastUpdateEventID;
    }
    self.lastUpdateEventID = nil;
}

- (BOOL)isDownloadingLastUpdateEventID
{
    return self.lastUpdateEventIDSync.status == ZMSingleRequestInProgress;
}

- (void)setNeedsSlowSync {
    // no-op
}

- (BOOL)isSlowSyncDone {
    return YES;
}

- (NSArray *)requestGenerators;
{
    return @[self.lastUpdateEventIDSync];
}

- (NSArray *)contextChangeTrackers
{
    return @[];
}

- (void)processEvents:(NSArray<ZMUpdateEvent *> __unused *)events
           liveEvents:(BOOL __unused)liveEvents
prefetchResult:(ZMFetchRequestBatchResult __unused *)prefetchResult;
{
    // no op
}

- (ZMTransportRequest *)requestForSingleRequestSync:(ZMSingleRequestSync *)sync
{
    NOT_USED(sync);
    NSURLComponents *components = [NSURLComponents componentsWithString:@"/notifications/last"];
    
    UserClient *selfClient = [ZMUser selfUserInContext:self.managedObjectContext].selfClient;
    if (selfClient.remoteIdentifier != nil) {
        components.queryItems = @[[NSURLQueryItem queryItemWithName:@"client" value:selfClient.remoteIdentifier]];
    }
    
    return [ZMTransportRequest requestGetFromPath:components.string];
}

- (void)didReceiveResponse:(ZMTransportResponse *)response forSingleRequest:(ZMSingleRequestSync *)sync
{
    NOT_USED(sync);
    if(response.payload != nil) {
        NSUUID *lastNotificationID = [[response.payload asDictionary] optionalUuidForKey:@"id"];
        if(lastNotificationID != nil) {
            self.lastUpdateEventID = lastNotificationID;
        }
    }
}

@end
