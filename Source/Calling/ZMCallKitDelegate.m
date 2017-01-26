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

@import ZMCDataModel;
@import CallKit;
@import UIKit;
@import ZMCSystem;
@import Intents;
@import avs;
#import "ZMCallKitDelegate.h"
#import "ZMUserSession.h"
#import "ZMUserSession+Internal.h"
#import "VoiceChannelV2+CallFlow.h"
#import "ZMCallKitDelegate+TypeConformance.h"
#import <zmessaging/zmessaging-Swift.h>

/**
 @c ZMCallKitDelegate is the main logical part of CallKit integration of wire-ios-sync-engine. 
 CallKit is the iOS VoIP calling integration framework that allows to place VoIP calls with the same priority level
 as other (GSM) calls.
 
 CallKit is supported from iOS 10. On the devices that do not support it we still show the notifications.
 
 It is possible to disable CallKit and use old-style notifications logic: `+[ZMUserSession setUseCallKit:]`.
 
 CallKit integration consists of 2 parts:
 I.  Showing iOS calling UI when call happens
     I.a Receive calls
     I.b Place calls
 II. Interaction with Phone app and redialing existing calls from there
 
 Using CallKit means asking iOS to start and end the call, so it can show the proper calling UI and play the ringtone.
 
 Flow for receieving the call (I.a):
 1. BE sends the new call state in conversation via push
 2. @c ZMCallStateTranscoder decode the payload and update the conversation/VoiceChannelV2 fields
 3. @c VoiceChannelV2 observer sends the update to @c ZMCallKitDelegate -[ZMCallKitDelegate voiceChannelStateDidChange:]
 4. @c ZMCallKitDelegate indicates the call to CallKit's @c CXProvider in -[ZMCallKitDelegate indicateIncomingCallInConversation:]
 5. @c CXProvider approves the call and informs @c ZMCallKitDelegate that call is possible in -[ZMCallKitDelegate provider:performStartCallAction:]
 6. @c ZMCallKitDelegate joins the call with -[VoiceChannelV2 join]
 
 Flow for sending the call (I.b):
 1. API consumer (UI app) calls -[VoiceChannelV2 joinInUserSession:]. This call is forwarded to -[ZMCallKitDelegate requestStartCallInConversation:]
 2. @c ZMCallKitDelegate indicates the call to CallKit's @c CXCallController, that asks @c CXProvider if call is possible. 
 3. @c CXProvider is indicating the call is possible with the callback -[ZMCallKitDelegate provider:performStartCallAction:]
 4. @c ZMCallKitDelegate joins the call with -[VoiceChannelV2 join]
 
 Flow for interaction with last calls / Phone app:
 1. The app is launched or brought to foreground
 2. @c UIApplicationDelegate receives the call for continuing the User Activity that is forwarded to @c ZMUserSession
 3. @c ZMUserSession forwards the call to -[ZMCallKitDelegate continueUserActivity:]
 4. @c ZMCallKitDelegate looks up the caller from the NSUserActivity and starts the call
 
 */


static NSString * const ZMCallKitDelegateCallStartedInGroup = @"callkit.call.started";

static NSString * const ZMLogTag ZM_UNUSED = @"CallKit";

NS_ASSUME_NONNULL_BEGIN

@implementation CXProvider (TypeConformance)
@end


@interface ZMCallKitDelegate ()

@property (nonatomic) id<CallKitProviderType> provider;
@property (nonatomic) id<CallKitCallController> callController;
@property (nonatomic) ZMOnDemandFlowManager *onDemandFlowManager;
@property (nonatomic, weak) ZMUserSession *userSession;
@property (nonatomic, weak) AVSMediaManager *mediaManager;
@property (nonatomic, nullable) ZMConversation *connectedCallConversation;
@property (nonatomic) id<NSObject> callStateObserverToken;
@property (nonatomic) id<NSObject> missedCallsObserverToken;
@property (nonatomic) id<NSObject> v2CallStateObserverToken;

@end


NS_ASSUME_NONNULL_END

@implementation ZMUser (Handle)

- (CXHandle *)callKitHandle
{
    if (0 != self.phoneNumber.length) {
        return [[CXHandle alloc] initWithType:CXHandleTypePhoneNumber value:self.phoneNumber];
    }
    else if (0 != self.emailAddress.length) {
        return [[CXHandle alloc] initWithType:CXHandleTypeEmailAddress value:self.emailAddress];
    }
    else if (nil != self.oneToOneConversation.remoteIdentifier) {
        return [[CXHandle alloc] initWithType:CXHandleTypeGeneric value:self.oneToOneConversation.remoteIdentifier.transportString];
    }
    else {
        RequireString(1, "Cannot create CXHandle: user has neither email nor phone number");
    }
    return nil;
}

@end

@implementation ZMConversation (Handle)

- (CXHandle *)callKitHandle
{
    switch (self.conversationType) {
        case ZMConversationTypeOneOnOne:
        case ZMConversationTypeConnection:
            return self.connectedUser.callKitHandle;
            break;
        case ZMConversationTypeGroup:
            return [[CXHandle alloc] initWithType:CXHandleTypeGeneric value:self.remoteIdentifier.transportString];
            break;
        default:
            RequireString(1, "Cannot create CXHandle: conversation type is invalid");
            return nil;
            break;
    }
    
    return nil;
}

- (NSString *)localizedCallerNameWithCallFromUser:(ZMUser *)user
{
    if (self.conversationType == ZMConversationTypeGroup) {
        return [ZMCallKitDelegateCallStartedInGroup localizedStringWithUser:user conversation:self count:0];
    } else {
        return self.connectedUser.displayName;
    }
}

+ (nullable instancetype)resolveConversationForPersons:(NSArray<INPerson *> *)persons
                                             inContext:(NSManagedObjectContext *)context
{
    if (1 != persons.count) {
        ZMLogError(@"CallKit: Cannot resolve call conversation for %lu participants", (unsigned long)persons.count);
        return nil;
    }
    
    INPerson *person = persons.firstObject;
    
    switch (person.personHandle.type) {
        case INPersonHandleTypeUnknown:
        {
            NSUUID *personHandle = [NSUUID uuidWithTransportString:person.personHandle.value];
            ZMConversation *result = [ZMConversation conversationWithRemoteID:personHandle
                                                               createIfNeeded:NO
                                                                    inContext:context];
            return result;
        }
            break;
        case INPersonHandleTypePhoneNumber:
        {
            ZMUser *user = [ZMUser userWithPhoneNumber:person.personHandle.value inContext:context];
            if (nil == user) {
                // Due to iOS bug the email caller is indicated as one with the INPersonHandleTypePhoneNumber in iOS 10.0.2
                user = [ZMUser userWithEmailAddress:person.personHandle.value inContext:context];
                
                if (nil == user) {
                    NSUUID *personHandle = [NSUUID uuidWithTransportString:person.personHandle.value];
                    ZMConversation *result = [ZMConversation conversationWithRemoteID:personHandle
                                                                       createIfNeeded:NO
                                                                            inContext:context];
                    return result;
                }
                else {
                    return user.oneToOneConversation;
                }
            }
            else {
                return user.oneToOneConversation;
            }
        }
            break;
        case INPersonHandleTypeEmailAddress:
        {
            ZMUser *user = [ZMUser userWithEmailAddress:person.personHandle.value inContext:context];
            if (nil == user) {
                return nil;
            }
            else {
                return user.oneToOneConversation;
            }
        }
            break;
    }
}

@end


@implementation CXCallAction (Conversation)

- (ZMConversation *)conversationInContext:(NSManagedObjectContext *)context
{
    ZMConversation *result = [ZMConversation conversationWithRemoteID:self.callUUID
                                                       createIfNeeded:NO
                                                            inContext:context];
    return result;
}

@end


@interface ZMCallKitDelegate (ProviderDelegate) <CXProviderDelegate>
@end


@implementation ZMCallKitDelegate

- (void)dealloc
{
    [WireCallCenterV3 removeObserverWithToken:self.callStateObserverToken];
    [WireCallCenterV3 removeObserverWithToken:self.missedCallsObserverToken];
    [WireCallCenterV2 removeObserverWithToken:self.v2CallStateObserverToken];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (instancetype)initWithCallKitProvider:(id<CallKitProviderType>)callKitProvider
                         callController:(id<CallKitCallController>)callController
                    onDemandFlowManager:(ZMOnDemandFlowManager *)onDemandFlowManager
                            userSession:(ZMUserSession *)userSession
                           mediaManager:(AVSMediaManager *)mediaManager

{
    self = [super init];
    if (nil != self) {
        Require(callKitProvider);
        Require(callController);
        Require(userSession);

        self.provider = callKitProvider;
        self.callController = callController;
        [self.provider setDelegate:self queue:nil];
        self.userSession = userSession;
        self.mediaManager = mediaManager;
        self.onDemandFlowManager = onDemandFlowManager;
                
        self.v2CallStateObserverToken = [WireCallCenterV2 addVoiceChannelStateObserverWithObserver:self context:userSession.managedObjectContext];
        self.callStateObserverToken = [self observeCallState];
        self.missedCallsObserverToken = [self observeMissedCalls];
        
        // If we see "ongoing" calls when app starts we need to end them. App cannot have calls when it is not running.
        [self endAllOngoingCallKitCallsExcept:nil];
    }
    return self;
}

+ (CXProviderConfiguration *)providerConfiguration
{
    NSString* localizedName = [NSBundle mainBundle].infoDictionary[@"CFBundleName"];
    if (localizedName == nil) {
        localizedName = @"Wire";
    }
    CXProviderConfiguration* providerConfiguration = [[CXProviderConfiguration alloc] initWithLocalizedName:localizedName];

    providerConfiguration.supportsVideo = YES;
    providerConfiguration.maximumCallGroups = 1;
    providerConfiguration.maximumCallsPerCallGroup = 1;
    providerConfiguration.supportedHandleTypes = [NSSet setWithObjects:
                                                  @(CXHandleTypeGeneric), nil];
    
    providerConfiguration.iconTemplateImageData = UIImagePNGRepresentation([UIImage imageNamed:@"logo"]);
    NSString *ringtoneSound = [ZMCustomSound notificationRingingSoundName];
    providerConfiguration.ringtoneSound = ringtoneSound;

    return providerConfiguration;
}

// MARK: - Logging

- (void)logErrorForConversation:(NSString *)conversationId line:(NSUInteger)line format:(NSString *)format, ...
{
    va_list args;
    va_start(args, format);
    NSString *logString = [[NSString alloc] initWithFormat:format arguments:args];
    [self logForConversation:conversationId level:ZMLogLevelError line:line message:logString];
    va_end(args);
}

- (void)logInfoForConversation:(NSString *)conversationId line:(NSUInteger)line format:(NSString *)format, ...
{
    va_list args;
    va_start(args, format);
    NSString *logString = [[NSString alloc] initWithFormat:format arguments:args];
    [self logForConversation:conversationId level:ZMLogLevelInfo line:line message:logString];
    va_end(args);
}

- (void)logForConversation:(NSString *)conversationId level:(ZMLogLevel_t)level line:(NSUInteger)line message:(NSString *)message
{
    NSString *messageWithLine = [NSString stringWithFormat:@"%s:%ld:%@ %@", __FILE__, (unsigned long)line, level == ZMLogLevelError ? @"ERROR: " : @"", message];
    [self.onDemandFlowManager.flowManager appendLogForConversation:conversationId message:messageWithLine];
}

- (void)endAllOngoingCallKitCallsExcept:(ZMConversation *)conversation
{
    for (CXCall *call in self.callController.callObserver.calls) {
        
        if (nil != conversation && [conversation.remoteIdentifier isEqual:call.UUID]) {
            continue;
        }
        
        CXEndCallAction *endCallAction = [[CXEndCallAction alloc] initWithCallUUID:call.UUID];
        
        CXTransaction *endCallTransaction = [[CXTransaction alloc] initWithActions:@[endCallAction]];
        
        [self.callController requestTransaction:endCallTransaction completion:^(NSError * _Nullable error) {
            if (nil != error) {
                [self logErrorForConversation:call.UUID.transportString line:__LINE__ format:@"Cannot end call: %@", error];
            }
        }];
        

    }
}

- (void)requestStartCallInConversation:(ZMConversation *)conversation videoCall:(BOOL)video
{
    if (conversation.voiceChannel.state == VoiceChannelV2StateIncomingCall) {
        CXAnswerCallAction *answerAction = [[CXAnswerCallAction alloc] initWithCallUUID:conversation.remoteIdentifier];
        CXTransaction *callAnswerTransaction = [[CXTransaction alloc] initWithAction:answerAction];
        [self.callController requestTransaction:callAnswerTransaction completion:^(NSError * _Nullable error) {
            if (nil != error) {
                [self logErrorForConversation:conversation.remoteIdentifier.transportString line:__LINE__ format:@"Cannot answer call: %@", error];
            }
        }];
    }
    else {
        [self endAllOngoingCallKitCallsExcept:conversation];
        
        CXStartCallAction *startCallAction = [[CXStartCallAction alloc] initWithCallUUID:conversation.remoteIdentifier
                                                                                  handle:conversation.callKitHandle];
        startCallAction.video = video;
        
        CXTransaction *startCallTransaction = [[CXTransaction alloc] initWithAction:startCallAction];
        
        [self.callController requestTransaction:startCallTransaction completion:^(NSError * _Nullable error) {
            if (nil != error) {
                [self logErrorForConversation:conversation.remoteIdentifier.transportString line:__LINE__ format:@"Cannot start call: %@", error];
            }
        }];
        
        CXCallUpdate *update = [[CXCallUpdate alloc] init];
        update.remoteHandle = conversation.callKitHandle;
        update.localizedCallerName = [conversation localizedCallerNameWithCallFromUser:[ZMUser selfUserInUserSession:self.userSession]];
        
        [self.provider reportCallWithUUID:conversation.remoteIdentifier updated:update];
    }
}

- (void)requestEndCallInConversation:(ZMConversation *)conversation
{
    CXEndCallAction *endCallAction = [[CXEndCallAction alloc] initWithCallUUID:conversation.remoteIdentifier];
    
    CXTransaction *endCallTransaction = [[CXTransaction alloc] initWithActions:@[endCallAction]];
    
    [self.callController requestTransaction:endCallTransaction completion:^(NSError * _Nullable error) {
        if (nil != error) {
            [self logErrorForConversation:conversation.remoteIdentifier.transportString line:__LINE__ format:@"Cannot end call: %@", error];
        }

        [conversation.voiceChannelRouter.currentVoiceChannel leave];
    }];
}

- (void)indicateIncomingCallFromUser:(ZMUser *)user inConversation:(ZMConversation *)conversation video:(BOOL)video
{
    // Construct a CXCallUpdate describing the incoming call, including the caller.
    CXCallUpdate* update = [[CXCallUpdate alloc] init];
    update.supportsHolding = NO;
    update.supportsDTMF = NO;
    update.supportsGrouping = NO;
    update.supportsUngrouping = NO;
    update.localizedCallerName = [conversation localizedCallerNameWithCallFromUser:user];
    update.remoteHandle = conversation.callKitHandle;
    update.hasVideo = video;
    
    [self logInfoForConversation:conversation.remoteIdentifier.transportString line:__LINE__ format:@"CallKit: reportNewIncomingCallWithUUID remoteHandle.type = %ld", (long)update.remoteHandle.type];
    
    [self.provider reportNewIncomingCallWithUUID:conversation.remoteIdentifier
                                          update:update
                                      completion:^(NSError * _Nullable error) {
                                          if (nil != error) {
                                              [conversation.voiceChannelRouter.currentVoiceChannel leave];
                                              [self logErrorForConversation:conversation.remoteIdentifier.transportString line:__LINE__ format:@"Cannot report incoming call: %@", error];
                                          } else {
                                              [self configureAudioSession];
                                          }
                                      }];
}

- (void)leaveAllActiveCalls
{
    ZMUserSession *userSession = self.userSession;
    NSArray<ZMConversation *> *nonIdleCallConversations = [WireCallCenter nonIdleCallConversationsInUserSession:userSession];
    
    [userSession enqueueChanges:^{
        for (ZMConversation *conversation in nonIdleCallConversations) {
            [conversation.voiceChannelRouter.currentVoiceChannel leave];
        }
    }];
}

- (void)configureAudioSession
{
	[self.mediaManager setupAudioDevice];
}

- (BOOL)continueUserActivity:(NSUserActivity *)userActivity
{
    ZMUserSession *userSession = self.userSession;
    INInteraction* interaction = userActivity.interaction;
    if (interaction == nil) {
        return NO;
    }
    INIntent *intent = interaction.intent;
    
    NSArray<INPerson *> *contacts = nil;
    BOOL isVideo = NO;
    
    if ([intent isKindOfClass:[INStartAudioCallIntent class]]) {
        INStartAudioCallIntent *startAudioCallIntent = (INStartAudioCallIntent *)intent;
        contacts = startAudioCallIntent.contacts;
        isVideo = NO;
    }
    else if ([intent isKindOfClass:[INStartVideoCallIntent class]]) {
        INStartVideoCallIntent *startVideoCallIntent = (INStartVideoCallIntent *)intent;
        contacts = startVideoCallIntent.contacts;
        isVideo = YES;
    }
    
    if (1 == contacts.count) {
        ZMConversation *callConversation = [ZMConversation resolveConversationForPersons:contacts
                                                                               inContext:userSession.managedObjectContext];
        if (nil != callConversation) {
            // Push channel must be open in order to process the call signaling
            if (!userSession.pushChannelIsOpen) {
                [userSession.transportSession restartPushChannel];
            }

            [self configureAudioSession];
            [self requestStartCallInConversation:callConversation videoCall:isVideo];
            return YES;
        }
        else {
            return NO;
        }
    }
    
    return YES;
}

@end


@implementation ZMCallKitDelegate (ProviderDelegate)

- (void)providerDidBegin:(CXProvider *)provider
{
    [self logInfoForConversation:nil line:__LINE__ format:@"CXProvider %@ didBegin", provider];
}

- (void)providerDidReset:(CXProvider *)provider
{
    [self logInfoForConversation:nil line:__LINE__ format:@"CXProvider %@ didReset", provider];
    [self.mediaManager resetAudioDevice];
    [self leaveAllActiveCalls];
}

- (void)provider:(CXProvider *)provider performStartCallAction:(CXStartCallAction *)action
{
    [self logInfoForConversation:nil line:__LINE__ format:@"CXProvider %@ performStartCallAction", provider];
    ZMUserSession *userSession = self.userSession;
    ZMConversation *callConversation = [action conversationInContext:userSession.managedObjectContext];
    [userSession performChanges:^{
        [self configureAudioSession];
        [callConversation.voiceChannelRouter.currentVoiceChannel joinWithVideo:action.video];
    }];
    
    [action fulfill];
}

- (void)provider:(CXProvider * __unused)provider performAnswerCallAction:(CXAnswerCallAction *)action
{
    [self.userSession performChanges:^{
        ZMConversation *callConversation = [action conversationInContext:self.userSession.managedObjectContext];
        [callConversation.voiceChannelRouter.currentVoiceChannel joinWithVideo:NO];
    }];
    [action fulfill];
}

- (void)provider:(CXProvider *)provider performEndCallAction:(nonnull CXEndCallAction *)action
{
    [self.mediaManager resetAudioDevice];
    
    ZMUserSession *userSession = self.userSession;

    ZMConversation *callConversation = [action conversationInContext:userSession.managedObjectContext];
    [self logInfoForConversation:callConversation.remoteIdentifier.transportString line:__LINE__ format:@"CXProvider %@ performEndCallAction on %@: current state %ld", provider, callConversation.displayName, (long)callConversation.voiceChannel.state];
    
    if (callConversation.voiceChannel.state != VoiceChannelV2StateNoActiveUsers &&
        callConversation.voiceChannel.state != VoiceChannelV2StateDeviceTransferReady &&
        callConversation.voiceChannel.state != VoiceChannelV2StateIncomingCallInactive &&
        callConversation.voiceChannel.state != VoiceChannelV2StateOutgoingCallInactive) {
        
        [userSession performChanges:^{
            if (callConversation.voiceChannel.selfUserConnectionState == VoiceChannelV2ConnectionStateNotConnected) {
                [self logInfoForConversation:callConversation.remoteIdentifier.transportString line:__LINE__ format:@"CXProvider performEndCallAction: ignore incoming call"];
                [callConversation.voiceChannelRouter.currentVoiceChannel ignore];
            }
            else {
                [self logInfoForConversation:callConversation.remoteIdentifier.transportString line:__LINE__ format:@"CXProvider performEndCallAction: leave"];
                [callConversation.voiceChannelRouter.currentVoiceChannel leave];
            }
        }];
    }
    [action fulfill];
}

- (void)provider:(CXProvider *)provider performSetHeldCallAction:(nonnull CXSetHeldCallAction *)action
{
    [self logInfoForConversation:nil line:__LINE__ format:@"CXProvider %@ performSetHeldCallAction", provider];
    [self.userSession performChanges:^{
        self.mediaManager.microphoneMuted = action.onHold;
    }];
    [action fulfill];
}

- (void)provider:(CXProvider *)provider performSetMutedCallAction:(CXSetMutedCallAction *)action
{
    [self logInfoForConversation:nil line:__LINE__ format:@"CXProvider %@ performSetMutedCallAction", provider];
    [self.userSession performChanges:^{
        self.mediaManager.microphoneMuted = action.muted;
    }];
    [action fulfill];
}

- (void)provider:(CXProvider *)provider timedOutPerformingAction:(CXAction *)action
{
    [self logInfoForConversation:nil line:__LINE__ format:@"CXProvider %@ timedOutPerformingAction %@", provider, action];
}

- (void)provider:(CXProvider __unused *)provider didActivateAudioSession:(AVAudioSession __unused *)audioSession
{
    [self logInfoForConversation:nil line:__LINE__ format:@"CXProvider %@ didActivateAudioSession", provider];
}

- (void)provider:(CXProvider *)provider didDeactivateAudioSession:(AVAudioSession __unused *)audioSession
{
    [self logInfoForConversation:nil line:__LINE__ format:@"CXProvider %@ didDeactivateAudioSession", provider];
}

@end
