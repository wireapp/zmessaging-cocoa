/*
* Wire
* Copyright (C) 2016 Wire Swiss GmbH
*
* This program is free software: you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation, either version 3 of the License, or
* (at your option) any later version.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
* GNU General Public License for more details.
*
* You should have received a copy of the GNU General Public License
* along with this program. If not, see <http://www.gnu.org/licenses/>.
*/

#ifndef AVS_CAPTURER_H_
#define AVS_CAPTURER_H_

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "AVSFlowManager.h"

typedef enum {
	AVS_CAPTURER_STATE_STOPPED = 0,
	AVS_CAPTURER_STATE_STARTING,
	AVS_CAPTURER_STATE_RUNNING,
	AVS_CAPTURER_STATE_STOPPING,
	AVS_CAPTURER_STATE_ERROR
}AVSCapturerState;


@interface AVSCapturer : NSObject<AVCaptureVideoDataOutputSampleBufferDelegate>

- (id)init;
- (int)startWithWidth:(uint32_t)width Height:(uint32_t)height MaxFps:(uint32_t)max_fps;
- (int)stop;
- (AVSCapturerState)getState;
- (int)setCaptureDevice:(NSString*)devId;
- (void)attachPreview:(UIView*)preview;
- (void)detachPreview:(UIView*)preview;

@end

#endif  // AVS_CAPTURER_H_
