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


@import WireSystem;
@import WireUtilities;
@import WireDataModel;

#import "ZMCallFlowRequestStrategy.h"
#import "ZMAVSBridge.h"
#import <WireSyncEngine/WireSyncEngine-Swift.h>
#import "ZMUserSessionAuthenticationNotification.h"
#import "ZMOnDemandFlowManager.h"

static NSString * const DefaultMediaType = @"application/json";
id ZMCallFlowRequestStrategyInternalDeploymentEnvironmentOverride;

static NSString *ZMLogTag ZM_UNUSED = @"Calling";

@interface ZMCallFlowRequestStrategy ()

@property (nonatomic, readonly) NSMutableArray *requestStack; ///< inverted FIFO
@property (nonatomic) ZMOnDemandFlowManager *onDemandFlowManager;
@property (nonatomic, readonly) id mediaManager;
@property (nonatomic) NSNotificationQueue *voiceGainNotificationQueue;
@property (nonatomic) BOOL pushChannelIsOpen;
@property (nonatomic, readonly) NSManagedObjectContext *uiManagedObjectContext;
@property (nonatomic) id authenticationObserverToken;
@property (nonatomic, strong) dispatch_queue_t avsLogQueue;
@property (nonatomic, readonly, weak) id<ZMApplication> application;

@end



@interface ZMCallFlowRequestStrategy (FlowManagerDelegate) <AVSFlowManagerDelegate>
@end



@implementation ZMCallFlowRequestStrategy

- (instancetype)initWithMediaManager:(id)mediaManager
                 onDemandFlowManager:(ZMOnDemandFlowManager *)onDemandFlowManager
                managedObjectContext:(NSManagedObjectContext *)managedObjectContext
                   applicationStatus:(id<ZMApplicationStatus>)applicationStatus
                         application:(id<ZMApplication>)application
{
    self = [super initWithManagedObjectContext:managedObjectContext applicationStatus:applicationStatus];
    if(self != nil) {
        _uiManagedObjectContext = managedObjectContext.zm_userInterfaceContext;
        _mediaManager = mediaManager;
        _requestStack = [NSMutableArray array];
        _application = application;

        self.voiceGainNotificationQueue = [[NSNotificationQueue alloc] initWithNotificationCenter:[NSNotificationCenter defaultCenter]];
        self.onDemandFlowManager = onDemandFlowManager;
        
        [self setUpFlowManagerIfNeeded];
        
        [application registerObserverForDidBecomeActive:self selector:@selector(appDidBecomeActive:)];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(pushChannelDidChange:) name:ZMPushChannelStateChangeNotificationName object:nil];
        ZM_WEAK(self);
        self.authenticationObserverToken = [ZMUserSessionAuthenticationNotification addObserverWithBlock:^(ZMUserSessionAuthenticationNotification *note){
            ZM_STRONG(self);
            if (note.type == ZMAuthenticationNotificationAuthenticationDidSuceeded) {
                [self.managedObjectContext performGroupedBlock:^{
                    [self registerSelfUser];
                }];
            }
        }];
        self.pushChannelIsOpen = NO;
        self.avsLogQueue = dispatch_queue_create("AVSLog", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (ZMStrategyConfigurationOption)configuration
{
    return ZMStrategyConfigurationOptionAllowsRequestsDuringEventProcessing | ZMStrategyConfigurationOptionAllowsRequestsDuringSync | ZMStrategyConfigurationOptionAllowsRequestsWhileInBackground;
}

- (void)setUpFlowManagerIfNeeded
{
    [self.onDemandFlowManager initializeFlowManagerWithDelegate:self];
}

- (void)appDidBecomeActive:(NSNotification *)note
{
    NOT_USED(note);
    [self.managedObjectContext performGroupedBlock:^{
        [self setUpFlowManagerIfNeeded];
    }];
}

- (void)tearDown;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.application unregisterObserverForStateChange:self];
    [ZMUserSessionAuthenticationNotification removeObserver:self.authenticationObserverToken];
}

- (AVSFlowManager *)flowManager
{
    return self.onDemandFlowManager.flowManager;
}

- (ZMTransportRequest *)nextRequestIfAllowed
{
    if (!self.pushChannelIsOpen && ![ZMUserSession useCallKit] && ![self nextRequestIsCallsConfig]) {
        return nil;
    }
    if ((self.application.applicationState != UIApplicationStateBackground && self.flowManager == nil) || [ZMUserSession useCallKit]) {
        [self setUpFlowManagerIfNeeded];  // this should not happen, but we should recover after all
    }
    
    id firstRequest = [self.requestStack lastObject];
    [firstRequest setDebugInformationTranscoder:self];
    [firstRequest forceToVoipSession];
    [self.requestStack removeLastObject];
    
    return firstRequest;
}

- (BOOL)nextRequestIsCallsConfig
{
    ZMTransportRequest *request = self.requestStack.lastObject;
    return [request.path isEqualToString:@"/calls/config"];
}

- (void)requestCompletedWithResponse:(ZMTransportResponse *)response forContext:(void const*)context
{
    NSData *contentData;
    if(response.payload != nil) {
        contentData = [NSJSONSerialization dataWithJSONObject:response.payload options:0 error:nil];
    }
    [self.flowManager processResponseWithStatus:(int) response.HTTPStatus reason:[NSString stringWithFormat:@"%ld", (long)response.HTTPStatus] mediaType:DefaultMediaType content:contentData context:context];
}

- (void)setSessionIdentifier:(NSString *)sessionID forConversationIdentifier:(NSUUID *)conversationID;
{
    NSString *userID = [ZMUser selfUserInContext:self.managedObjectContext].remoteIdentifier.transportString ?: @"na";
    NSString *randomID = [NSUUID UUID].transportString;
    NSString *combinedID = [NSString stringWithFormat:@"%@_U-%@_D-%@", sessionID, userID, randomID];
    [self.flowManager setSessionId:combinedID forConversation:conversationID.transportString];
}

- (void)appendLogForConversationID:(NSUUID *)conversationID message:(NSString *)message;
{
    AVSFlowManager *flowManager = self.flowManager;
    dispatch_async(self.avsLogQueue, ^{
        [flowManager appendLogForConversation:conversationID.transportString message:message];
    });
}

- (void)pushChannelDidChange:(NSNotification *)note
{
    const BOOL oldValue = self.pushChannelIsOpen;
    BOOL newValue = [note.userInfo[ZMPushChannelIsOpenKey] boolValue];
    self.pushChannelIsOpen = newValue;
    
    if(self.pushChannelIsOpen) {
        [self.flowManager networkChanged];
    }
    
    if (!oldValue && newValue && self.requestStack.count > 0) {
        [ZMRequestAvailableNotification notifyNewRequestsAvailable:self];
    }
}

- (void)registerSelfUser
{
    NSString *selfUserID = [ZMUser selfUserInContext:self.managedObjectContext].remoteIdentifier.transportString;
    if (selfUserID == nil) {
        return;
    }
    [self.flowManager setSelfUser:selfUserID];
}

- (BOOL)isFlowManagerReady
{
    if (!self.flowManager.isReady) {
        ZMLogDebug(@"Flowmanager not ready");
        return NO;
    }
    return YES;
}

@end



@implementation ZMCallFlowRequestStrategy (FlowManagerDelegate)


- (BOOL)requestWithPath:(NSString *)path
                 method:(NSString *)methodString
              mediaType:(NSString *)mtype
                content:(NSData *)content
                context:(void const *)ctx;
{
    VerifyActionString(path.length > 0,  return NO, "Path for AVSFlowManager request not set");
    VerifyActionString(methodString.length > 0, return NO, "Method for AVSFlowManager request not set");
    
    ZMTransportRequestMethod method = [ZMTransportRequest methodFromString:methodString];
    [self.managedObjectContext performGroupedBlock:^{
        ZMTransportRequest *request = [[ZMTransportRequest alloc] initWithPath:path method:method binaryData:content type:mtype contentDisposition:nil shouldCompress:YES];
        ZM_WEAK(self);
        
        [request addCompletionHandler:[ZMCompletionHandler handlerOnGroupQueue:self.managedObjectContext block:^(ZMTransportResponse *response) {
            ZM_STRONG(self);
            [self requestCompletedWithResponse:response forContext:ctx];
        }]];
        
        [self.requestStack insertObject:request atIndex:0];
        [ZMRequestAvailableNotification notifyNewRequestsAvailable:self];
    }];
    return YES;
}

- (void)didEstablishMediaInConversation:(NSString *)conversationIdentifier;
{
    NOT_USED(conversationIdentifier);
}

- (void)setFlowManagerActivityState:(AVSFlowActivityState)activityState;
{
    NOT_USED(activityState);
}

- (void)networkQuality:(float)q conversation:(NSString *)convid;
{
    NOT_USED(q);
    NOT_USED(convid);
}

- (void)mediaWarningOnConversation:(NSString *)conversationIdentifier;
{
    NOT_USED(conversationIdentifier);
}

- (void)errorHandler:(int)err
      conversationId:(NSString *)conversationIdentifier
             context:(void const*)ctx;
{
    NOT_USED(err);
    NOT_USED(conversationIdentifier);
    NOT_USED(ctx);
}

- (void)leaveCallInConversationWithRemoteID:(NSString *)remoteIDString reason:(NSString *)reason
{
    NOT_USED(remoteIDString);
    NOT_USED(reason);
}

- (void)didUpdateVolume:(double)volume conversationId:(NSString *)convid participantId:(NSString *)participantId
{
    [self.managedObjectContext performGroupedBlock:^{
        NSUUID *conversationUUID = convid.UUID;
        ZMConversation *conversation = [ZMConversation conversationWithRemoteID:conversationUUID createIfNeeded:NO inContext:self.managedObjectContext];
        if (conversation == nil) {
            return;
        }
        ZMUser *user;
        if ([participantId isEqualToString:FlowManagerSelfUserParticipantIdentifier]) {
            user = [ZMUser selfUserInContext:self.managedObjectContext];
        }
        else if ([participantId isEqualToString:FlowManagerOtherUserParticipantIdentifier]) {
            user = conversation.connectedUser;
        }
        
        else {
            NSUUID *participantUUID = [participantId UUID];
            user = [ZMUser userWithRemoteID:participantUUID createIfNeeded:NO inContext:self.managedObjectContext];
        }
        if (user == nil) {
            return;
        }
        
        NSUUID *conversationID = conversation.remoteIdentifier;
        NSUUID *userID = user.remoteIdentifier;
        
        VoiceGainNotification *voiceGainNotification = [[VoiceGainNotification alloc] initWithVolume:(float)volume conversationId:conversationID userId:userID];
        
        [self.uiManagedObjectContext performGroupedBlock:^{
            [self.voiceGainNotificationQueue enqueueNotification:voiceGainNotification.notification
                                                    postingStyle:NSPostWhenIdle
                                                    coalesceMask:NSNotificationCoalescingOnSender | NSNotificationCoalescingOnName
                                                        forModes:nil];
        }];
    }];

}

- (void)conferenceParticipantsDidChange:(NSArray *)participantIDStrings
                         inConversation:(NSString *)convId;
{
    NOT_USED(participantIDStrings);
    NOT_USED(convId);
}


- (void)vmStatushandler:(BOOL)is_playing current_time:(int)cur_time_ms length:(int)file_length_ms;
{
    NOT_USED(is_playing);
    NOT_USED(cur_time_ms);
    NOT_USED(file_length_ms);
}

+ (void)logMessage:(NSString *)msg;
{
    NOT_USED(msg);
}

@end


