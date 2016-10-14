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
@import ZMTransport;
@import ZMUtilities;
@import ZMCDataModel;

#import "ZMLocalNotificationDispatcher+Testing.h"
#import "ZMLocalNotification.h"
#import "ZMPushRegistrant.h"
#import <zmessaging/zmessaging-Swift.h>

NSString * const ZMConversationCancelNotificationForIncomingCallNotificationName = @"ZMConversationCancelNotificationForIncomingCallNotification";

NSString * _Null_unspecified const ZMShouldHideNotificationContentKey = @"ZMShouldHideNotificationContentKey";


@interface ZMLocalNotificationDispatcher ()

@property (nonatomic) NSManagedObjectContext *syncMOC;
@property (nonatomic) ZMLocalNotificationSet *failedMessageNotifications;
@property (nonatomic) ZMLocalNotificationSet *eventsNotifications;
@property (nonatomic) ZMLocalNotificationSet *messageNotifications;
@property (nonatomic) SessionTracker *sessionTracker;
@property (nonatomic) id<ZMApplication> sharedApplication;
@property (nonatomic) BOOL isTornDown;

@end


@interface NSManagedObjectContext (KeyValueStore) <ZMSynchonizableKeyValueStore>
@end

@implementation ZMLocalNotificationDispatcher

ZM_EMPTY_ASSERTING_INIT();

- (instancetype)initWithManagedObjectContext:(NSManagedObjectContext *)moc
                           sharedApplication:(id<ZMApplication>)sharedApplication
{
    return [self initWithManagedObjectContext:moc sharedApplication:sharedApplication eventNotificationSet:nil failedNotificationSet:nil messageNotifications:nil];
}

- (instancetype)initWithManagedObjectContext:(NSManagedObjectContext *)moc
                           sharedApplication:(id<ZMApplication>)sharedApplication
                        eventNotificationSet:(ZMLocalNotificationSet *)eventNotificationSet
                       failedNotificationSet:(ZMLocalNotificationSet *)failedNotificationSet
                        messageNotifications:(ZMLocalNotificationSet *)messageNotifications
{
    self = [super init];
    if (self) {
        self.syncMOC = moc;
        self.eventsNotifications = eventNotificationSet ?:  [[ZMLocalNotificationSet alloc] initWithApplication:sharedApplication archivingKey:@"ZMLocalNotificationDispatcherEventNotificationsKey" keyValueStore:moc];
        self.messageNotifications = messageNotifications ?:  [[ZMLocalNotificationSet alloc] initWithApplication:sharedApplication archivingKey:@"ZMLocalNotificationDispatcherMessageNotificationsKey" keyValueStore:moc];
        self.failedMessageNotifications = failedNotificationSet ?: [[ZMLocalNotificationSet alloc] initWithApplication:sharedApplication archivingKey:@"ZMLocalNotificationDispatcherFailedNotificationsKey" keyValueStore:moc];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(cancelNotificationForIncomingCallInConversation:) name:ZMConversationCancelNotificationForIncomingCallNotificationName object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(cancelNotificationForLastReadChangedNotification:) name:ZMConversationLastReadDidChangeNotificationName object:nil];
        
        self.sharedApplication = sharedApplication;
        self.sessionTracker = [[SessionTracker alloc] initWithManagedObjectContext:self.syncMOC];
    }
    return self;
}

- (void)tearDown;
{
    self.isTornDown = YES;
    [self.sessionTracker tearDown];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self cancelAllNotifications];
}

- (void)dealloc
{
    Require(self.isTornDown);
}

- (id)sharedApplicationForSwift
{
    return self.sharedApplication;
}

- (void)cancelNotificationForLastReadChangedNotification:(NSNotification *)note
{
    ZMConversation *conversation = note.object;
    if (conversation == nil || ![conversation isKindOfClass:[ZMConversation class]]) {
        return;
    }
    
    BOOL isUIObject = conversation.managedObjectContext.zm_isUserInterfaceContext;
    
    [self.syncMOC performGroupedBlock:^{
        if (isUIObject) {
            // clear all notifications for this conversation
            NSError *error;
            ZMConversation *syncConversation = (id)[self.syncMOC existingObjectWithID:conversation.objectID error:&error];
            if (error == nil && syncConversation != nil) {
                [self cancelNotificationForConversation:syncConversation];
            }
        } else {
            [self cancelNotificationForConversation:conversation];
        }
    }];
}

- (void)cancelNotificationForIncomingCallInConversation:(NSNotification *)notification
{
    ZMConversation *conversation = (id)notification.object;
    if ([conversation isIgnoringCall]) {
        [self.eventsNotifications cancelNotificationForIncomingCall:conversation];
    }
}

- (void)cancelAllNotifications
{
    [self.eventsNotifications cancelAllNotifications];
    [self.failedMessageNotifications cancelAllNotifications];
    [self.messageNotifications cancelAllNotifications];
}

- (void)cancelNotificationForConversation:(ZMConversation *)conversation
{
    [self.sessionTracker clearSessions:conversation];
    [self.eventsNotifications cancelNotifications:conversation];
    [self.failedMessageNotifications cancelNotifications:conversation];
    [self.messageNotifications cancelNotifications:conversation];
}

@end




@implementation ZMLocalNotificationDispatcher (EventProcessing)

- (void)processEvents:(NSArray<ZMUpdateEvent *> *)events liveEvents:(BOOL)liveEvents prefetchResult:(ZMFetchRequestBatchResult *)prefetchResult;
{
    NOT_USED(liveEvents);
    NOT_USED(prefetchResult);
    
    if (self.sharedApplication.applicationState != UIApplicationStateBackground) {
        return;
    }
    
    NSArray *eventsToForward = [events filterWithBlock:^BOOL(ZMUpdateEvent *event) {
        // we only want to process events we received through Push
        if (event.source != ZMUpdateEventSourcePushNotification) {
            return NO;
        }
        // TODO Sabine : Can we maybe filter message events here already for Reactions?
        return YES;
    }];
    [self didReceiveUpdateEvents:eventsToForward conversationMap:prefetchResult.conversationsByRemoteIdentifier notificationID:[events.firstObject uuid]];
}

- (void)didReceiveUpdateEvents:(NSArray <ZMUpdateEvent *>*)events conversationMap:(ZMConversationMapping *)conversationMap notificationID:(NSUUID *)notificationID
{
    ZMLogPushKit(@"Processing push events (a) %p (count = %u)", events, (unsigned) events.count);
    for (ZMUpdateEvent *event in events) {
        // Forward events to the session tracker which keeps track if the selfUser joined or not
        [self.sessionTracker addEvent:event];
        
        // The create the notification
        ZMLocalNotificationForEvent *note = [self notificationForEvent:event conversationMap:conversationMap];
        if (note != nil && note.uiNotifications.count > 0) {
            UILocalNotification *localNote = note.uiNotifications.lastObject;
            ZMLogPushKit(@"Scheduling local notification <%@: %p> '%@'", localNote.class, localNote, localNote.alertBody);
            [self.sharedApplication scheduleLocalNotification:localNote];
            if (notificationID != nil) {
                [APNSPerformanceTracker trackVOIPNotificationInNotificationDispatcher:notificationID analytics:self.syncMOC.analytics];
            }
        }
    }
}

- (ZMLocalNotificationForEvent *)notificationForEvent:(ZMUpdateEvent *)event conversationMap:(ZMConversationMapping *)conversationMap
{
    switch (event.type) {
        case ZMUpdateEventConversationCreate:
        case ZMUpdateEventUserConnection:
        case ZMUpdateEventConversationOtrMessageAdd: // Only for reactions
        case ZMUpdateEventUserContactJoin:
        case ZMUpdateEventCallState:
            return [self localNotificationForEvent:event conversationMap:conversationMap];
        default:
            return nil;
    }
}

- (ZMLocalNotificationForEvent *)localNotificationForEvent:(ZMUpdateEvent *)event conversationMap:(ZMConversationMapping *)conversationMap
{
    for (ZMLocalNotificationForEvent *note in self.eventsNotifications.notifications) {
        if ([note containsIdenticalEvent:event]) {
            return nil;
        }
    }
    
    ZMConversation *conversation;
    if (event.conversationUUID != nil) {
        // Fetch the conversation here to avoid refetching every time we try to create a notification
        conversation = conversationMap[event.conversationUUID] ?: [ZMConversation fetchObjectWithRemoteIdentifier:event.conversationUUID inManagedObjectContext: self.syncMOC];
    }
    if (conversation != nil) {
        ZMLocalNotificationForEvent *newNote = [self.eventsNotifications copyExistingEventNotification:event conversation:conversation];
        if (newNote != nil) {
            return newNote;
        }
    }
 
    ZMLocalNotificationForEvent *newNote = [ZMLocalNotificationForEvent notificationForEvent:event conversation:conversation managedObjectContext:self.syncMOC application:self.sharedApplication sessionTracker:self.sessionTracker];
    if (newNote != nil) {
        [self.eventsNotifications addObject:newNote];
    }
    return newNote;
}


@end




@implementation ZMLocalNotificationDispatcher (FailedMessages)

- (void)didFailToSentMessage:(ZMMessage *)message;
{
    if (message.visibleInConversation == nil || message.conversation.conversationType == ZMConversationTypeSelf) {
        return;
    }
    ZMLocalNotificationForExpiredMessage *note = [[ZMLocalNotificationForExpiredMessage alloc] initWithExpiredMessage:message];
    [self.sharedApplication scheduleLocalNotification:note.uiNotification];
    [self.failedMessageNotifications addObject:note];
}

- (void)didFailToSendMessageInConversation:(ZMConversation *)conversation;
{
    ZMLocalNotificationForExpiredMessage *note = [[ZMLocalNotificationForExpiredMessage alloc] initWithConversation:conversation];
    [self.sharedApplication scheduleLocalNotification:note.uiNotification];
    [self.failedMessageNotifications addObject:note];
}

@end






