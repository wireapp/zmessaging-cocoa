//
//  ZMSyncStrategy+ManagedObjectChanges.h
//  zmessaging-cocoa
//
//  Created by Sabine Geithner on 08/12/16.
//  Copyright © 2016 Zeta Project Gmbh. All rights reserved.
//

#import "ZMSyncStrategy.h"

@interface ZMSyncStrategy (ManagedObjectChanges)

- (void)managedObjectContextDidSave:(NSNotification *)note;
- (BOOL)processSaveWithInsertedObjects:(NSSet *)insertedObjects updateObjects:(NSSet *)updatedObjects;

@end
