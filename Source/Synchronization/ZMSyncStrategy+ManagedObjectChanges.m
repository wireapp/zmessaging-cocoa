//
//  ZMSyncStrategy+ManagedObjectChanges.m
//  zmessaging-cocoa
//
//  Created by Sabine Geithner on 08/12/16.
//  Copyright © 2016 Zeta Project Gmbh. All rights reserved.
//

#import "ZMSyncStrategy+Internal.h"
#import "ZMSyncStrategy+ManagedObjectChanges.h"
#import "ZMessagingLogs.h"

@implementation ZMSyncStrategy (ManagedObjectChanges)


- (void)managedObjectContextDidSave:(NSNotification *)note;
{
    if(self.tornDown || self.contextMergingDisabled) {
        return;
    }
    
    if([ZMSLog getLevelWithTag:ZMTAG_CORE_DATA] == ZMLogLevelDebug) {
        [self logDidSaveNotification:note];
    }
    
    NSManagedObjectContext *mocThatSaved = note.object;
    NSManagedObjectContext *strongUiMoc = self.uiMOC;
    ZMCallState *callStateChanges = mocThatSaved.zm_callState.createCopyAndResetHasChanges;
    
    if (mocThatSaved.zm_isUserInterfaceContext && strongUiMoc != nil) {
        if(mocThatSaved != strongUiMoc) {
            RequireString(mocThatSaved == strongUiMoc, "Not the right MOC!");
        }
        
        NSSet *conversationsWithCallChanges = [callStateChanges allContainedConversationsInContext:strongUiMoc];
        if (conversationsWithCallChanges != nil) {
            [strongUiMoc.globalManagedObjectContextObserver notifyUpdatedCallState:conversationsWithCallChanges notifyDirectly:YES];
        }
        
        ZM_WEAK(self);
        [self.syncMOC performGroupedBlock:^{
            ZM_STRONG(self);
            if(self == nil || self.tornDown) {
                return;
            }
            NSSet *changedConversations = [self.syncMOC mergeCallStateChanges:callStateChanges];
            [self.syncMOC mergeChangesFromContextDidSaveNotification:note];
            
            [self processSaveWithInsertedObjects:[NSSet set] updateObjects:changedConversations];
            [self.syncMOC processPendingChanges]; // We need this because merging sometimes leaves the MOC in a 'dirty' state
        }];
    } else if (mocThatSaved.zm_isSyncContext) {
        RequireString(mocThatSaved == self.syncMOC, "Not the right MOC!");
        
        ZM_WEAK(self);
        [strongUiMoc performGroupedBlock:^{
            ZM_STRONG(self);
            if(self == nil || self.tornDown) {
                return;
            }
            
            NSSet *changedConversations = [strongUiMoc mergeCallStateChanges:callStateChanges];
            [strongUiMoc.globalManagedObjectContextObserver notifyUpdatedCallState:changedConversations notifyDirectly:[self shouldForwardCallStateChangeDirectlyForNote:note]];
            
            [strongUiMoc mergeChangesFromContextDidSaveNotification:note];
            [strongUiMoc processPendingChanges]; // We need this because merging sometimes leaves the MOC in a 'dirty' state
        }];
    }
}

- (BOOL)processSaveWithInsertedObjects:(NSSet *)insertedObjects updateObjects:(NSSet *)updatedObjects
{
    NSSet *allObjects = [NSSet zmSetByCompiningSets:insertedObjects, updatedObjects, nil];
    
    for(id<ZMContextChangeTracker> tracker in self.allChangeTrackers)
    {
        [tracker objectsDidChange:allObjects];
    }
    
    return YES;
}

- (BOOL)shouldForwardCallStateChangeDirectlyForNote:(NSNotification *)note
{
    if ([(NSSet *)note.userInfo[NSInsertedObjectsKey] count] == 0 &&
        [(NSSet *)note.userInfo[NSDeletedObjectsKey] count] == 0 &&
        [(NSSet *)note.userInfo[NSUpdatedObjectsKey] count] == 0 &&
        [(NSSet *)note.userInfo[NSRefreshedObjectsKey] count] == 0) {
        return YES;
    }
    return NO;
}


- (void)logDidSaveNotification:(NSNotification *)note;
{
    NSManagedObjectContext * ZM_UNUSED moc = note.object;
    ZMLogWithLevelAndTag(ZMLogLevelDebug, ZMTAG_CORE_DATA, @"<%@: %p> did save. Context type = %@",
                         moc.class, moc,
                         moc.zm_isUserInterfaceContext ? @"UI" : moc.zm_isSyncContext ? @"Sync" : @"");
    NSSet *inserted = note.userInfo[NSInsertedObjectsKey];
    if (inserted.count > 0) {
        NSString * ZM_UNUSED description = [[inserted.allObjects mapWithBlock:^id(NSManagedObject *mo) {
            return mo.objectID.URIRepresentation;
        }] componentsJoinedByString:@", "];
        ZMLogWithLevelAndTag(ZMLogLevelDebug, ZMTAG_CORE_DATA, @"    Inserted: %@", description);
    }
    NSSet *updated = note.userInfo[NSUpdatedObjectsKey];
    if (updated.count > 0) {
        NSString * ZM_UNUSED description = [[updated.allObjects mapWithBlock:^id(NSManagedObject *mo) {
            return mo.objectID.URIRepresentation;
        }] componentsJoinedByString:@", "];
        ZMLogWithLevelAndTag(ZMLogLevelDebug, ZMTAG_CORE_DATA, @"    Updated: %@", description);
    }
    NSSet *deleted = note.userInfo[NSDeletedObjectsKey];
    if (deleted.count > 0) {
        NSString * ZM_UNUSED description = [[deleted.allObjects mapWithBlock:^id(NSManagedObject *mo) {
            return mo.objectID.URIRepresentation;
        }] componentsJoinedByString:@", "];
        ZMLogWithLevelAndTag(ZMLogLevelDebug, ZMTAG_CORE_DATA, @"    Deleted: %@", description);
    }
}


@end
