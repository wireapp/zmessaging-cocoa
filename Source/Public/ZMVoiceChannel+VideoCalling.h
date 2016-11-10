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


@import Foundation;
@import ZMCDataModel;
#import <ZMCDataModel/ZMVoiceChannel.h>

@class ZMUser;
@class UIView;

extern NSString * const ZMFrontCameraDeviceID;
extern NSString * const ZMBackCameraDeviceID;

FOUNDATION_EXPORT NSString * ZMVoiceChannelVideoCallErrorDomain;

@interface ZMVoiceChannel (VideoCalling)

/// Establishing a video call or join a video call and send video straight away
/// Returns an error if a video call can not be initialized
- (BOOL)joinVideoCall:(NSError **)error inUserSession:(ZMUserSession *)userSession;

// Checks if sending of the video is possible for the participant
- (BOOL)isSendingVideoForParticipant:(ZMUser *)participant error:(NSError **)error;

// Set video sending active/inactive
- (BOOL)setVideoSendActive:(BOOL)active error:(NSError **)error;

// Selects camera
- (BOOL)setVideoCaptureDevice:(NSString *)deviceId error:(NSError **)error;


#pragma mark - Private
- (BOOL)setVideoSendState:(int)state error:(NSError **)error;

@end
