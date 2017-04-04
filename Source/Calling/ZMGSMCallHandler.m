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


@import CoreTelephony;
@import WireSystem;
@import WireDataModel;

#import "ZMGSMCallHandler.h"
#import "ZMCallStateLogger.h"
#import "ZMSyncStateMachine.h"
#import <WireSyncEngine/WireSyncEngine-Swift.h>

NSString *const ZMInterruptedCallConversationObjectIDKey = @"InterruptedCallConversationObjectID";

@interface ZMGSMCallHandler ()

@property (nonatomic) NSManagedObjectContext *uiManagedObjectContext;
@property (nonatomic) NSManagedObjectContext *syncManagedObjectContext;

@property (nonatomic) CTCallCenter *callCenter;
@property (nonatomic) ZMCallStateLogger *callStateLogger;

@property (nonatomic, readonly) ZMConversation *activeCallUIConversation;
@property (nonatomic) NSManagedObjectID *activeCallUIConversationObjectID;

@property (nonatomic) BOOL canUpdateCallState;
@property (nonatomic) BOOL tornDown;
@end



@implementation ZMGSMCallHandler

- (instancetype)initWithUIManagedObjectContext:(NSManagedObjectContext *)uiMOC
                      syncManagedObjectContext:(NSManagedObjectContext *)syncMOC
                               callStateLogger:(ZMCallStateLogger*)logger
{
    return [self initWithUIManagedObjectContext:uiMOC syncManagedObjectContext:syncMOC callStateLogger:logger callCenter:nil];
}


- (instancetype)initWithUIManagedObjectContext:(NSManagedObjectContext *)uiMOC
                      syncManagedObjectContext:(NSManagedObjectContext *)syncMOC
                               callStateLogger:(ZMCallStateLogger*)logger
                                    callCenter:(CTCallCenter *)callCenter
{
    Require(uiMOC != nil);
    
    self = [super init];
    if (self != nil){
        self.uiManagedObjectContext = uiMOC;
        self.syncManagedObjectContext = syncMOC;
        self.callStateLogger = logger;
        self.callCenter = callCenter ?: uiMOC.zm_callCenter;
        self.callCenter.callEventHandler = self.callEventHandler;
        self.canUpdateCallState = NO;
        self.activeCallUIConversationObjectID = [self storedConversationInContext:self.syncManagedObjectContext].objectID;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didFinishSync:) name:ZMApplicationDidEnterEventProcessingStateNotificationName object:nil];
    }
    return self;
}

- (void)tearDown
{
    self.tornDown = YES;
    self.callCenter.callEventHandler = nil;
    self.callCenter = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)dealloc
{
    Require(self.tornDown);
}

- (void)didFinishSync:(NSNotification *)note
{
    if ([ZMUserSession useCallKit]) {
        return;
    }

    NOT_USED(note);
    self.canUpdateCallState = YES;
    
    [self.uiManagedObjectContext performGroupedBlock:^{
        if (self.callCenter.currentCalls.count == 0 && self.hasStoredInterruptedCallConversation) {
            [self rejoinVoiceChannelAfterGSMInterruption];
        }
    }];
    
    
}

- (void (^)(CTCall *))callEventHandler
{
    ZM_WEAK(self);
    return ^void(CTCall *call){
        ZM_STRONG(self);
        BOOL isDialing = [call.callState isEqualToString:CTCallStateDialing];
        BOOL isIncoming = [call.callState isEqualToString:CTCallStateIncoming];
        BOOL isDisconnected = [call.callState isEqualToString:CTCallStateDisconnected];
        
        [self.uiManagedObjectContext performGroupedBlock:^{
            if (!self.canUpdateCallState) {
                return;
            }
            
            if ([ZMUserSession useCallKit]) {
                return;
            }
            
            if ((isDialing || isIncoming) &&
                self.activeCallUIConversationObjectID != nil &&
                (!self.hasStoredInterruptedCallConversation || ![[self storedConversationInContext:self.uiManagedObjectContext].objectID isEqual:self.activeCallUIConversationObjectID])
                )
            {
                [self interruptCall];
            }
            
            else if (isDisconnected && self.hasStoredInterruptedCallConversation)
            {
                [self rejoinVoiceChannelAfterGSMInterruption];
            }
        }];
    };
}

- (void)interruptCall
{
    [self logIsInterrupted:YES];
    
    // store the conversationObjectID in the persistenStore metaData so when the app restarts
    // because it was killed during the call it can resume / end the active call
    [self setStoredConversation:self.activeCallUIConversation managedObjectContext:self.uiManagedObjectContext];
    
    // when the activeCallConversation is set, we need to send a call/state request to the backend with the state
    //  {
    //    self: {state: joined,
    //           suspended: true},
    //    cause: interrupted
    //  }
    //
    [self.activeCallUIConversation.voiceChannelRouter.v2 join];
    [self.uiManagedObjectContext saveOrRollback];
}

- (void)rejoinVoiceChannelAfterGSMInterruption
{
    [self logIsInterrupted:NO];
    
    ZMConversation *storedConversation = self.activeCallUIConversation;
    // we need to reset the stored conversation before sending out the next call state request
    // otherwise the call state transcoder will
    // (1) set the wrong flag for join and
    // (2) not update flows when receiving the response from the BE
    [self setStoredConversation:nil managedObjectContext:self.uiManagedObjectContext];
    
    
    if (storedConversation.voiceChannel.participants.count > 0) {
        [storedConversation.voiceChannelRouter.v2 join];
    } else if (storedConversation.callDeviceIsActive) {
        // in case we received a force idle (disconnected) without the self dictionary (bug on the BE)
        // we would have no call participants, but callDeviceIsActive would be still set
        // we need to hang up properly
        [storedConversation.voiceChannelRouter.v2 leave];
    }
    [self.uiManagedObjectContext enqueueDelayedSave];
}

- (BOOL)hasStoredInterruptedCallConversation
{
    return ([self.uiManagedObjectContext persistentStoreMetadataForKey:ZMInterruptedCallConversationObjectIDKey] != nil);
}

- (ZMConversation *)storedConversationInContext:(NSManagedObjectContext *)moc
{
    NSString *objectIDURLString = [moc persistentStoreMetadataForKey:ZMInterruptedCallConversationObjectIDKey];
    if (objectIDURLString == nil) {
        return nil;
    }
    ZMConversation *conv = [ZMConversation existingObjectWithObjectIdentifier:objectIDURLString inManagedObjectContext:moc];
    return conv;
}

- (void)setStoredConversation:(ZMConversation *)storedConversation managedObjectContext:(NSManagedObjectContext *)moc
{
    [moc setPersistentStoreMetadata:[storedConversation objectIDURLString]
                                                     forKey:ZMInterruptedCallConversationObjectIDKey];
}


- (ZMConversation *)activeCallUIConversation
{
    if (self.activeCallUIConversationObjectID == nil) {
        return nil;
    }
    return (id)[self.uiManagedObjectContext objectWithID:self.activeCallUIConversationObjectID];
}

- (void)setActiveCallSyncConversation:(ZMConversation *)conversation
{
    if (conversation == nil || conversation.objectID.isTemporaryID) {
        self.activeCallUIConversationObjectID = nil;
        [self.uiManagedObjectContext performGroupedBlock:^{
            // when a wire call ends during a GSM call, we need to reset the storedConversation as well
            // otherwise on next app launch the app might initiate call automatically
            [self setStoredConversation:nil managedObjectContext:self.uiManagedObjectContext];
        }];
        return;
    }
    self.activeCallUIConversationObjectID = conversation.objectID;
}


- (BOOL)isInterruptedCallConversation:(ZMConversation *)conversation
{
    if ([ZMUserSession useCallKit]) {
        return NO;
    }
    
    return [conversation.objectID isEqual:[self storedConversationInContext:conversation.managedObjectContext].objectID];
}

- (void)logIsInterrupted:(BOOL)isInterrupted
{
    if (self.activeCallUIConversation != nil) {
        [self.syncManagedObjectContext performGroupedBlock:^{
            ZMConversation *syncConv = (id)[self.syncManagedObjectContext objectWithID:self.activeCallUIConversationObjectID];
            [self.callStateLogger logCallInterruptionForConversation:syncConv isInterrupted:isInterrupted];
        }];
    }
}


@end
