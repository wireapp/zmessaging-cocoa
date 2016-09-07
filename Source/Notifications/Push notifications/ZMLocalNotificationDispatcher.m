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
#import "ZMBadge.h"
#import "ZMPushRegistrant.h"
#import <zmessaging/zmessaging-Swift.h>

NSString * ZMLocalNotificationDispatcherUIApplicationClass = @"UIApplication";
NSString * const ZMConversationCancelNotificationForIncomingCallNotificationName = @"ZMConversationCancelNotificationForIncomingCallNotification";

NSString * _Null_unspecified const ZMShouldHideNotificationContentKey = @"ZMShouldHideNotificationContentKey";


@interface ZMLocalNotificationDispatcher ()

@property (nonatomic) NSManagedObjectContext *syncMOC;
@property (nonatomic) ZMLocalNotificationSet *failedMessageNotifications;
@property (nonatomic) ZMLocalNotificationSet *eventsNotifications;
@property (nonatomic) BOOL isTornDown;
@property (nonatomic) ZMApplication *sharedApplication;


@end


@interface NSManagedObjectContext (KeyValueStore) <ZMSynchonizableKeyValueStore>
@end

@implementation ZMLocalNotificationDispatcher

ZM_EMPTY_ASSERTING_INIT();

- (instancetype)initWithManagedObjectContext:(NSManagedObjectContext *)moc
                           sharedApplication:(ZMApplication *)sharedApplication
{
    return [self initWithManagedObjectContext:moc sharedApplication:sharedApplication eventNotificationSet:nil failedNotificationSet:nil];
}

- (instancetype)initWithManagedObjectContext:(NSManagedObjectContext *)moc
                           sharedApplication:(ZMApplication *)sharedApplication
                        eventNotificationSet:(ZMLocalNotificationSet *)eventNotificationSet
                       failedNotificationSet:(ZMLocalNotificationSet *)failedNotificationSet
{
    self = [super init];
    if (self) {
        self.syncMOC = moc;
        self.eventsNotifications = eventNotificationSet ?:  [[ZMLocalNotificationSet alloc] initWithApplication:sharedApplication archivingKey:@"ZMLocalNotificationDispatcherEventNotificationsKey" keyValueStore:moc];
        self.failedMessageNotifications = failedNotificationSet ?: [[ZMLocalNotificationSet alloc] initWithApplication:sharedApplication archivingKey:@"ZMLocalNotificationDispatcherFailedNotificationsKey" keyValueStore:moc];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(cancelNotificationForIncomingCallInConversation:) name:ZMConversationCancelNotificationForIncomingCallNotificationName object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(cancelNotificationForLastReadChangedNotification:) name:ZMConversationLastReadDidChangeNotificationName object:nil];
        
        self.sharedApplication = sharedApplication;
    }
    return self;
}

- (void)tearDown;
{
    self.isTornDown = YES;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self cancelAllNotifications];
}

- (void)dealloc
{
    Require(self.isTornDown);
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
}

- (void)cancelNotificationForConversation:(ZMConversation *)conversation
{
    [self.eventsNotifications cancelNotifications:conversation];
    [self.failedMessageNotifications cancelNotifications:conversation];
}

- (void)processEvents:(NSArray<ZMUpdateEvent *> *)events liveEvents:(BOOL)liveEvents prefetchResult:(ZMFetchRequestBatchResult *)prefetchResult;
{
    NOT_USED(liveEvents);
    
    if (self.sharedApplication.applicationState != UIApplicationStateBackground) {
        return;
    }
    
    NSArray *eventsToForward = [events filterWithBlock:^BOOL(ZMUpdateEvent *event) {
        // we only want to process events we received through Push
        if (event.source != ZMUpdateEventSourcePushNotification) {
            return NO;
        }
        // if the event is not a message, we want to process it in any case
        if (event.messageNonce == nil) {
            return YES;
        }
        // if the event is a message, we only want to process it if it does not have a preexisting message
        // TODO Sabine: Can this lead to multipart messages not being shown at all?
        // e.g. when we receive an asset message, we receive a preview and medium image message
        // However, we only process the preview. If under bad network, the medium image part arrives before the preview,
        // we would not display any notification at all, would we?
        NSSet <ZMMessage *>* prefetchedMessages = prefetchResult.messagesByNonce[event.messageNonce];
        if (nil != prefetchedMessages) {
            for (ZMMessage *prefetchedMessage in prefetchedMessages) {
                if ([prefetchedMessage isKindOfClass:[self class]]) {
                    return NO;
                }
            }
        }
        return YES;
    }];
    
    [self didReceiveUpdateEvents:eventsToForward notificationID:[events.firstObject uuid]];
}

- (void)didReceiveUpdateEvents:(NSArray <ZMUpdateEvent *>*)events notificationID:(NSUUID *)notificationID
{
    ZMLogPushKit(@"Processing push events (a) %p (count = %u)", events, (unsigned) events.count);
    for (ZMUpdateEvent *event in events) {
        ZMLocalNotificationForEvent *note = [self notificationForEvent:event];
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


- (ZMLocalNotificationForEvent *)notificationForEvent:(ZMUpdateEvent *)event
{
    switch (event.type) {
        case ZMUpdateEventConversationAssetAdd:
        case ZMUpdateEventConversationConnectRequest:
        case ZMUpdateEventConversationKnock:
        case ZMUpdateEventConversationMessageAdd:
        case ZMUpdateEventConversationMemberJoin:
        case ZMUpdateEventConversationMemberLeave:
        case ZMUpdateEventConversationRename:
        case ZMUpdateEventUserConnection:
        case ZMUpdateEventConversationCreate:
        case ZMUpdateEventConversationOtrMessageAdd:
        case ZMUpdateEventConversationOtrAssetAdd:
        case ZMUpdateEventUserContactJoin:
        case ZMUpdateEventCallState:
            return [self localNotificationForEvent:event];
            
        case ZMUpdateEventConversationVoiceChannel:
        case ZMUpdateEventCallCandidatesAdd:
        case ZMUpdateEventCallCandidatesUpdate:
        case ZMUpdateEventCallDeviceInfo:
        case ZMUpdateEventCallFlowActive:
        case ZMUpdateEventCallFlowAdd:
        case ZMUpdateEventCallFlowDelete:
        case ZMUpdateEventCallParticipants:
        case ZMUpdateEventCallRemoteSDP:
        case ZMUpdateEventConversationMemberUpdate:
        case ZMUpdateEventConversationTyping:
        case ZMUpdateEventUnknown:
        case ZMUpdateEventUserNew:
        case ZMUpdateEventUserUpdate:
        case ZMUpdateEvent_LAST:
            return nil;
            
        default:
            return nil;
    }
}

- (ZMLocalNotificationForEvent *)localNotificationForEvent:(ZMUpdateEvent *)event
{
    for (ZMLocalNotificationForEvent *note in self.eventsNotifications.notifications) {
        if ([note containsIdenticalEvent:event]) {
            return nil;
        }
    }
    
    ZMLocalNotificationForEvent *newNote = [self.eventsNotifications copyExistingNotification:event];
    if (newNote != nil) {
        return newNote;
    }
 
    newNote = [ZMLocalNotificationForEvent notificationForEvent:event managedObjectContext:self.syncMOC application:self.sharedApplication];
    if (newNote != nil) {
        [self.eventsNotifications addObject:newNote];
    }
    return newNote;
}


@end



