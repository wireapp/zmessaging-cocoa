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

#import "ZMRemovedSuggestedPeopleTranscoder.h"



@interface ZMRemovedSuggestedPeopleTranscoder ()

@property (nonatomic, readonly) ZMRemoteIdentifierObjectSync *remoteIDSync;

@end



@interface ZMRemovedSuggestedPeopleTranscoder (ZMRemoteIdentifierObjectTranscoder) <ZMRemoteIdentifierObjectTranscoder>
@end


@implementation ZMRemovedSuggestedPeopleTranscoder

- (instancetype)initWithManagedObjectContext:(NSManagedObjectContext *)moc;
{
    self = [super initWithManagedObjectContext:moc];
    if (self != nil) {
        _remoteIDSync = [[ZMRemoteIdentifierObjectSync alloc] initWithTranscoder:self managedObjectContext:self.managedObjectContext];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(remoteIdentifiersDidChange:) name:ZMRemovedSuggestedContactRemoteIdentifiersDidChange object:nil];
    }
    return self;
}

- (void)tearDown;
{
    [super tearDown];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)isSlowSyncDone;
{
    return YES;
}

- (void)setNeedsSlowSync;
{
    // no-op
}

- (void)processEvents:(NSArray<ZMUpdateEvent *> __unused *)events
           liveEvents:(BOOL __unused)liveEvents
       prefetchResult:(__unused ZMFetchRequestBatchResult *)prefetchResult;
{
    // no-op
}

- (NSArray *)requestGenerators;
{
    return @[self.remoteIDSync];
}

- (NSArray *)contextChangeTrackers;
{
    return @[];
}

- (void)remoteIdentifiersDidChange:(NSNotification *)note;
{
    NOT_USED(note);
    [self.managedObjectContext performGroupedBlock:^{
        NSArray *identifiers = self.managedObjectContext.removedSuggestedContactRemoteIdentifiers;
        [self.remoteIDSync addRemoteIdentifiersThatNeedDownload:[NSSet setWithArray:identifiers]];
        [ZMRequestAvailableNotification notifyNewRequestsAvailable:self];
    }];
}

- (void)didCompleteRemoteIdentifiers:(NSSet *)identifiers;
{
    NSMutableArray *result = [NSMutableArray arrayWithArray:self.managedObjectContext.removedSuggestedContactRemoteIdentifiers];
    [result removeObjectsInArray:identifiers.allObjects];
    self.managedObjectContext.removedSuggestedContactRemoteIdentifiers = result;
    [self.managedObjectContext enqueueDelayedSave];
}

@end



@implementation ZMRemovedSuggestedPeopleTranscoder (ZMRemoteIdentifierObjectTranscoder)

- (NSUInteger)maximumRemoteIdentifiersPerRequestForObjectSync:(ZMRemoteIdentifierObjectSync *)sync;
{
    NOT_USED(sync);
    return 1;
}

- (ZMTransportRequest *)requestForObjectSync:(ZMRemoteIdentifierObjectSync *)sync remoteIdentifiers:(NSSet *)identifiers;
{
    NOT_USED(sync);
    Require(identifiers.count == 1u);
    
    NSUUID *remoteID = identifiers.anyObject;
    NSString *path = [NSString pathWithComponents:@[@"/", @"search", @"suggestions", remoteID.transportString, @"ignore"]];
    return [ZMTransportRequest emptyPutRequestWithPath:path];
}

- (void)didReceiveResponse:(ZMTransportResponse *)response remoteIdentifierObjectSync:(ZMRemoteIdentifierObjectSync *)sync forRemoteIdentifiers:(NSSet *)remoteIdentifiers;
{
    NOT_USED(sync);

    switch (response.result) {
        case ZMTransportResponseStatusSuccess:
        case ZMTransportResponseStatusPermanentError:
            [self didCompleteRemoteIdentifiers:remoteIdentifiers];
            break;
        case ZMTransportResponseStatusTemporaryError:
        case ZMTransportResponseStatusExpired:
        case ZMTransportResponseStatusTryAgainLater:
            break;
    }
}

@end
