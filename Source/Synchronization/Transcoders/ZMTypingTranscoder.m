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

#import "ZMTypingTranscoder.h"
#import "ZMTyping.h"
#import "ZMOperationLoop.h"
#import "ZMTypingTranscoder+Internal.h"



NSString * const ZMTypingNotificationName = @"ZMTypingNotification";
static NSString * const IsTypingKey = @"isTyping";
static NSString * const ClearIsTypingKey = @"clearIsTyping";

static NSString * const StatusKey = @"status";
static NSString * const StoppedKey = @"stopped";
static NSString * const StartedKey = @"started";






@interface ZMTypingTranscoder ()

@property (nonatomic) ZMTyping *typing;
@property (nonatomic) NSMutableDictionary *conversations;
@property (nonatomic) ZMTypingEvent *lastSentTypingEvent;

@end



@implementation ZMTypingTranscoder

- (instancetype)initWithManagedObjectContext:(NSManagedObjectContext *)moc;
{
    self = [self initWithManagedObjectContext:moc userInterfaceContext:nil typing:nil];
    NOT_USED(self);
    Require(NO);
    return nil;
}

- (instancetype)initWithManagedObjectContext:(NSManagedObjectContext *)moc userInterfaceContext:(NSManagedObjectContext *)uiMoc;
{
    return [self initWithManagedObjectContext:moc userInterfaceContext:uiMoc typing:nil];
}

- (instancetype)initWithManagedObjectContext:(NSManagedObjectContext *)moc
                         userInterfaceContext:(NSManagedObjectContext *)uiMoc
                                      typing:(ZMTyping *)typing;
{
    self = [super initWithManagedObjectContext:moc];
    if (self != nil) {
        self.typing = typing ?: [[ZMTyping alloc] initWithUserInterfaceManagedObjectContext:uiMoc syncManagedObjectContext:self.managedObjectContext];
        self.conversations = [NSMutableDictionary dictionary];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(addConversationForNextRequest:) name:ZMTypingNotificationName object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(shouldClearTypingForConversation:) name:ZMConversationClearTypingNotificationName object:nil];

    }
    return self;
}

- (void)tearDown
{
    [self.typing tearDown];
    self.typing = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super tearDown];
}

- (void)shouldClearTypingForConversation:(NSNotification *)note
{
    ZMConversation *conversation = note.object;
    if (conversation.remoteIdentifier == nil) {
        return;
    }
    [self addConversationForNextRequest:conversation isTypingNumber:@0 clearIsTyping:YES];
}

- (void)addConversationForNextRequest:(NSNotification *)note
{
    ZMConversation *conversation = note.object;
    if (conversation.remoteIdentifier == nil) {
        return;
    }
    NSNumber *isTyping = note.userInfo[IsTypingKey];
    NSNumber *clearIsTypingNumber = note.userInfo[ClearIsTypingKey];
    VerifyReturn(isTyping != nil || clearIsTypingNumber != nil);
    BOOL const clearIsTyping = [clearIsTypingNumber boolValue];

    [self addConversationForNextRequest:conversation isTypingNumber:isTyping clearIsTyping:clearIsTyping];
}

- (void)addConversationForNextRequest:(ZMConversation *)conversation isTypingNumber:(NSNumber *)isTypingNumber clearIsTyping:(BOOL)clearIsTyping
{
    if (conversation.remoteIdentifier == nil){
        return;
    }

    [self.managedObjectContext performGroupedBlock:^{
        if (clearIsTyping) {
            [self.conversations removeObjectForKey:conversation.objectID];
            self.lastSentTypingEvent = nil;
        } else {
            self.conversations[conversation.objectID] = isTypingNumber;
            [ZMOperationLoop notifyNewRequestsAvailable:self];
        }
    }];
}

- (BOOL)isSlowSyncDone;
{
    return YES;
}

- (NSArray *)contextChangeTrackers;
{
    return @[];
}

- (NSArray *)requestGenerators;
{
    return @[self];
}

- (void)setNeedsSlowSync;
{
    // no-op
}

- (ZMTransportRequest *)nextRequest;
{
    NSManagedObjectID *convObjectID = self.conversations.allKeys.firstObject;
    if (convObjectID == nil) {
        return nil;
    }
    BOOL isTyping = [self.conversations[convObjectID] boolValue];
    [self.conversations removeObjectForKey:convObjectID];
    
    ZMTypingEvent *newTypingEvent = [ZMTypingEvent typingEventWithObjectID:convObjectID isTyping:isTyping];
    if ([self.lastSentTypingEvent isRecentAndEqualToEvent:newTypingEvent]) {
        return nil;
    }
    
    ZMConversation *conversation = (id)[self.managedObjectContext objectWithID:convObjectID];
    VerifyReturnNil(conversation.remoteIdentifier != nil);
    
    NSString *path = [NSString pathWithComponents:@[@"/", @"conversations", conversation.remoteIdentifier.transportString, @"typing"]];
    NSDictionary *payload = @{StatusKey: isTyping ? StartedKey: StoppedKey};
    ZMTransportRequest *request = [ZMTransportRequest requestWithPath:path method:ZMMethodPOST payload:payload];
    self.lastSentTypingEvent = newTypingEvent;
    
    [request setDebugInformationTranscoder:self];

    return request;
}

- (void)processEvents:(NSArray<ZMUpdateEvent *> *)events
           liveEvents:(BOOL)liveEvents
       prefetchResult:(ZMFetchRequestBatchResult *)prefetchResult;
{
    if(!liveEvents) {
        return;
    }

    for(ZMUpdateEvent *event in events) {
        [self processUpdateEvent:event conversationsByID:prefetchResult.conversationsByRemoteIdentifier];
    }
}

- (void)processUpdateEvent:(ZMUpdateEvent *)event conversationsByID:(ZMConversationMapping *)conversationsByID;
{
    if (event.type != ZMUpdateEventConversationTyping && event.type != ZMUpdateEventConversationOtrMessageAdd) {
        return;
    }
    
    NSDictionary *payload = event.payload;

    NSUUID *userID = event.senderUUID;
    if (userID == nil) {
        return;
    }
    ZMUser *user = [ZMUser userWithRemoteID:userID createIfNeeded:YES inContext:self.managedObjectContext];
    
    NSUUID *convID = event.conversationUUID;
    if (convID == nil) {
        return;
    }
    
    ZMConversation *conversation = conversationsByID[convID];
    if (nil == conversation) {
        conversation = [ZMConversation conversationWithRemoteID:convID createIfNeeded:YES inContext:self.managedObjectContext];
    }

    if (event.type == ZMUpdateEventConversationTyping) {
        NSDictionary *payloadData = [payload optionalDictionaryForKey:@"data"];
        NSString *status = [payloadData optionalStringForKey:StatusKey];
        if (status == nil) {
            return;
        }
        [self processIsTypingUpdateEventForUser:user inConversation:conversation withStatus:status];
    } else if (event.type == ZMUpdateEventConversationOtrMessageAdd) {
        [self processMessageAddEventForUser:user inConversation:conversation];
    }

}

- (void)processIsTypingUpdateEventForUser:(ZMUser *)user inConversation:(ZMConversation *)conversation withStatus:(NSString *)status
{
    BOOL startedTyping = [status isEqualToString:StartedKey];
    BOOL stoppedTyping = [status isEqualToString:StoppedKey];
    if (startedTyping || stoppedTyping) {
        [self.typing setIsTyping:startedTyping forUser:user inConversation:conversation];
    }
}

- (void)processMessageAddEventForUser:(ZMUser *)user inConversation:(ZMConversation *)conversation
{
    [self.typing setIsTyping:NO forUser:user inConversation:conversation];
}

@end




@implementation ZMTypingTranscoder (ZMConversation)

+ (void)notifyTranscoderThatUserIsTyping:(BOOL)isTyping inConversation:(ZMConversation *)conversation;
{
    NSDictionary *userInfo = @{IsTypingKey: @(isTyping)};
    [[NSNotificationCenter defaultCenter] postNotificationName:ZMTypingNotificationName object:conversation userInfo:userInfo];
}

+ (void)clearTranscoderStateForTypingInConversation:(ZMConversation *)conversation;
{
    NSDictionary *userInfo = @{ClearIsTypingKey: @YES};
    [[NSNotificationCenter defaultCenter] postNotificationName:ZMTypingNotificationName object:conversation userInfo:userInfo];
}

@end



@implementation ZMTypingEvent

- (instancetype)init
{
    self = [super init];
    if (self) {
        _date = [NSDate date];
    }
    return self;
}

+ (instancetype)typingEventWithObjectID:(NSManagedObjectID *)moid isTyping:(BOOL)isTyping;
{
    ZMTypingEvent *e = [[self alloc] init];
    e.objectID = moid;
    e.isTyping = isTyping;
    return e;
}

- (BOOL)isRecentAndEqualToEvent:(ZMTypingEvent *)other;
{
    return ((other.isTyping == self.isTyping) &&
            [other.objectID isEqual:self.objectID] &&
            (fabs(other.date.timeIntervalSinceReferenceDate - self.date.timeIntervalSinceReferenceDate) < (ZMTypingDefaultTimeout / ZMTypingRelativeSendTimeout)));
}

@end
