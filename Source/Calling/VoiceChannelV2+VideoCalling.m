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

@import WireDataModel;
@import WireTransport;
@import avs;

#import "VoiceChannelV2+VideoCalling.h"
#import "ZMUserSession.h"
#import "ZMUserSession+Internal.h"
#import "ZMCallKitDelegate.h"
#import "ZMAVSBridge.h"
#import <WireSyncEngine/WireSyncEngine-Swift.h>


NSString * VoiceChannelV2VideoCallErrorDomain = @"VoiceChannelV2VideoCallErrorDomain";

@implementation VoiceChannelV2 (VideoCalling)

- (BOOL)isSendingVideoForParticipant:(ZMUser *)participant error:(NSError **)error
{
    ZMConversation *conversation = self.conversation;
    if (self.flowManager == nil || !self.flowManager.isReady) {
        if (error != nil) {
            *error = [VoiceChannelV2Error noFlowManagerError];
        }
        return NO;
    }
    
    if(!conversation.isVideoCall) {
        if (error != nil) {
            *error = [VoiceChannelV2Error videoNotActiveError];
        }
        return NO;
    }
    
    return [self.flowManager isSendingVideoInConversation:conversation.remoteIdentifier.transportString forParticipant:participant.remoteIdentifier.transportString];
}


- (BOOL)isVideoCallingPossibleInConversation:(ZMConversation *)conversation error:(NSError **)error
{
    if (self.flowManager == nil || !self.flowManager.isReady) {
        if (error != nil) {
            *error = [VoiceChannelV2Error noFlowManagerError];
        }
        return NO;
    }
    
    if (! [self.flowManager isMediaEstablishedInConversation:conversation.remoteIdentifier.transportString]) {
        if (error != nil) {
            *error = [VoiceChannelV2Error noMediaError];
        }
        return NO;
    }
    
    if (! [self.flowManager canSendVideoForConversation:conversation.remoteIdentifier.transportString]) {
        if (error != nil) {
            *error = [VoiceChannelV2Error videoCallNotSupportedError];
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
    
    conversation.isSendingVideo = state == FLOWMANAGER_VIDEO_SEND;
    
    [self.flowManager setVideoSendState:state
                                forConversation:conversation.remoteIdentifier.transportString];
    return YES;
}

@end
