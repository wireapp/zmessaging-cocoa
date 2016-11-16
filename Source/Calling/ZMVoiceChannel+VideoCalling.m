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

#import "ZMVoiceChannel+VideoCalling.h"
#import "ZMVoiceChannel+CallFlowPrivate.h"
#import "AVSFlowManager.h"
#import "ZMUserSession.h"
#import "ZMUserSession+Internal.h"
#import "ZMCallKitDelegate.h"
#import "ZMAVSBridge.h"
#import <zmessaging/zmessaging-Swift.h>

@import ZMTransport;


NSString * ZMVoiceChannelVideoCallErrorDomain = @"ZMVoiceChannelVideoCallErrorDomain";
NSString * const ZMFrontCameraDeviceID = @"com.apple.avfoundation.avcapturedevice.built-in_video:1";
NSString * const ZMBackCameraDeviceID = @"com.apple.avfoundation.avcapturedevice.built-in_video:0";

@implementation ZMVoiceChannel (VideoCalling)

/// Establishing a video call or join a video call and send video straight away
- (BOOL)joinVideoCall:(NSError **)error inUserSession:(ZMUserSession *)userSession
{
    if ([ZMUserSession useCallKit]) {
        // Push channel must be open in order to process the call signalling
        if (!userSession.pushChannelIsOpen) {
            [userSession.transportSession restartPushChannel];
        }
        [userSession.callKitDelegate requestStartCallInConversation:self.conversation videoCall:YES];
        return YES;
    }
    else {
        return [self joinVideoCall:error];
    }
}

- (BOOL)isSendingVideoForParticipant:(ZMUser *)participant error:(NSError **)error
{
    ZMConversation *conversation = self.conversation;
    if (self.flowManager == nil || !self.flowManager.isReady) {
        if (error != nil) {
            *error = [ZMVoiceChannelError noFlowManagerError];
        }
        return NO;
    }
    
    if(!conversation.isVideoCall) {
        if (error != nil) {
            *error = [ZMVoiceChannelError videoNotActiveError];
        }
        return NO;
    }
    
    return [self.flowManager isSendingVideoInConversation:conversation.remoteIdentifier.transportString forParticipant:participant.remoteIdentifier.transportString];
}


- (BOOL)isVideoCallingPossibleInConversation:(ZMConversation *)conversation error:(NSError **)error
{
    if (self.flowManager == nil || !self.flowManager.isReady) {
        if (error != nil) {
            *error = [ZMVoiceChannelError noFlowManagerError];
        }
        return NO;
    }
    
    if (! [self.flowManager isMediaEstablishedInConversation:conversation.remoteIdentifier.transportString]) {
        if (error != nil) {
            *error = [ZMVoiceChannelError noMediaError];
        }
        return NO;
    }
    
    if (! [self.flowManager canSendVideoForConversation:conversation.remoteIdentifier.transportString]) {
        if (error != nil) {
            *error = [ZMVoiceChannelError videoCallNotSupportedError];
        }
        return NO;
    }
    
    return YES;
}

- (BOOL)setVideoSendActive:(BOOL)active error:(NSError **)error;
{
    AVSFlowManagerVideoSendState sendState = active ? FLOWMANAGER_VIDEO_SEND : FLOWMANAGER_VIDEO_SEND_NONE;

    return [self setVideoSendState:sendState error:error];
}

- (BOOL)setVideoSendState:(int)state error:(NSError **)error;
{
    ZMConversation *conversation = self.conversation;
    if (state == FLOWMANAGER_VIDEO_SEND && ![self isVideoCallingPossibleInConversation:conversation error:error]) {
        return NO;
    }
    if (error != nil) {
        *error = nil;
    }
    self.currentVideoDeviceID = state == FLOWMANAGER_VIDEO_SEND_NONE ? nil : ZMFrontCameraDeviceID;
    conversation.isSendingVideo = state == FLOWMANAGER_VIDEO_SEND;
    
    [self.flowManager setVideoSendState:state
                                forConversation:conversation.remoteIdentifier.transportString];
    return YES;
}

- (BOOL)setVideoCaptureDevice:(NSString *)deviceId error:(NSError **)error
{
    ZMConversation *conversation = self.conversation;
    if (self.flowManager == nil || !self.flowManager.isReady) {
        if (error != nil) {
            *error = [ZMVoiceChannelError noFlowManagerError];
        }
        return NO;
    }

    if(!conversation.isVideoCall) {
        if (error != nil) {
            *error = [ZMVoiceChannelError videoNotActiveError];
        }
        return NO;
    }
    
    self.currentVideoDeviceID = deviceId;
    [self.flowManager setVideoCaptureDevice:deviceId
                                   forConversation:conversation.remoteIdentifier.transportString];
    return YES;
}

@end
