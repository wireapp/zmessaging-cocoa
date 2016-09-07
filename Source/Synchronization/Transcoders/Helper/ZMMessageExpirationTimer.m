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


@import ZMCSystem;
@import ZMUtilities;
@import ZMCDataModel;

#import "ZMMessageExpirationTimer.h"
#import "ZMOperationLoop.h"

#import "ZMLocalNotificationDispatcher.h"

@interface ZMMessageExpirationTimer () <ZMTimerClient>

@property (nonatomic) NSMapTable *objectToTimerMap;
@property (nonatomic) BOOL tearDownCalled;
@property (nonatomic) NSManagedObjectContext *moc;
@property (nonatomic) ZMLocalNotificationDispatcher *localNotificationsDispatcher;
@property (nonatomic) NSString *entityName;
@property (nonatomic) NSPredicate *filter;

@end



@implementation ZMMessageExpirationTimer

ZM_EMPTY_ASSERTING_INIT()

- (instancetype)initWithManagedObjectContext:(NSManagedObjectContext *)moc entityName:(NSString *)entityName localNotificationDispatcher:(ZMLocalNotificationDispatcher *)notificationDispatcher
{
    return [self initWithManagedObjectContext:moc entityName:entityName localNotificationDispatcher:notificationDispatcher filter:nil];
}

- (instancetype)initWithManagedObjectContext:(NSManagedObjectContext *)moc entityName:(NSString *)entityName localNotificationDispatcher:(ZMLocalNotificationDispatcher *)notificationDispatcher filter:(NSPredicate *)filter;
{
    self = [super init];
    if (self) {
        self.localNotificationsDispatcher = notificationDispatcher;
        self.objectToTimerMap = [NSMapTable strongToStrongObjectsMapTable];
        self.moc = moc;
        self.entityName = entityName;
        self.filter = filter;
    }
    return self;
}

- (void)dealloc
{
    NSAssert(self.tearDownCalled == YES, @"Teardown was not called");
}

- (BOOL)hasMessageTimersRunning
{
    return self.objectToTimerMap.count > 0;
}

- (NSUInteger)runningTimersCount
{
    return [self.objectToTimerMap count];
}

- (NSFetchRequest *)fetchRequestForTrackedObjects
{
    NSPredicate *predicate = [ZMMessage predicateForMessagesThatWillExpire];
    return [ZMMessage sortedFetchRequestWithPredicate:predicate];
}

- (void)addTrackedObjects:(NSSet *)objects;
{
    [self startTimerForObjects:objects];
}

- (void)objectsDidChange:(NSSet *)objects
{
    [self startTimerForObjects:objects];
}

- (void)startTimerForStoredMessages
{
    NSPredicate *predicate = [ZMMessage predicateForMessagesThatWillExpire];
    NSFetchRequest *request = [ZMMessage sortedFetchRequestWithPredicate:predicate];
    NSArray *expiringMessages = [self.moc executeFetchRequestOrAssert:request];
    [self startTimerForObjects:[NSSet setWithArray:expiringMessages]];
}


- (void)startTimerForObjects:(NSSet *)managedObjects
{
    NSDate *now = [NSDate date];
    for (ZMManagedObject *object in managedObjects) {
        if (![[[object class] entityName] isEqual: self.entityName]) {
            continue;
        }
        
        BOOL passedFilter = (self.filter == nil ||
                             (self.filter != nil && [self.filter evaluateWithObject:object]));
        if (!passedFilter) {
            continue;
        }
        
        if (! [[[object class] entityName] isEqualToString:self.entityName]) {
            continue;
        }
        
        ZMMessage *message = (ZMMessage *)object;
        
        if (message.expirationDate == nil) {
            continue;
        }
        
        if ([message.expirationDate compare:now] == NSOrderedAscending) {
            [message expire];
            [message.managedObjectContext enqueueDelayedSave];
        }
        else if ( ![self isTimerRunningForMessage:message] ) {
            ZMTimer *timer = [ZMTimer timerWithTarget:self];
            timer.userInfo = @{ @"message": message };
            [self.objectToTimerMap setObject:timer forKey:message];
            
            [timer fireAtDate:message.expirationDate];
        }
    }
}

- (BOOL)isTimerRunningForMessage:(ZMMessage *)message {
    return [self.objectToTimerMap objectForKey:message] != nil;
}

- (void)timerDidFire:(ZMTimer *)timer
{
    ZMMessage *message = timer.userInfo[@"message"];
    
    RequireString(self.moc != nil, "MOC is nil");
    [self.moc performGroupedBlock:^{
        [self removeTimerForMessage:message];
        
        if (message == nil || message.isZombieObject) {
            return;
        }
        
        if (message.deliveryState != ZMDeliveryStateDelivered && message.deliveryState != ZMDeliveryStateSent) {
            [message expire];
            [message.managedObjectContext enqueueDelayedSave];
            [self.localNotificationsDispatcher didFailToSentMessage:message];
            [ZMOperationLoop notifyNewRequestsAvailable:self];
        }
    }];
}


- (void)stopTimerForMessage:(ZMMessage *)message;
{
    ZMTimer *timer = [self.objectToTimerMap objectForKey:message];
    if(timer == nil) {
        return;
    }
    
    [timer cancel];
    [self removeTimerForMessage:message];
}


- (void)removeTimerForMessage:(ZMMessage *)message {
    [self.objectToTimerMap removeObjectForKey:message];
}


- (void)tearDown;
{
    for (ZMTimer *timer in self.objectToTimerMap.objectEnumerator) {
        [timer cancel];
    }
    
    self.tearDownCalled = YES;
}

@end
