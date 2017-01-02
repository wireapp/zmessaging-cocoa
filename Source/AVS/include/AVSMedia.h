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
//
//  AVSMedia.h
//  zmm
//

@protocol AVSMedia;

@protocol AVSMediaDelegate <NSObject>

- (void)didStartPlayingMedia:(id<AVSMedia>)media;
- (void)didPausePlayingMedia:(id<AVSMedia>)media;
- (void)didResumePlayingMedia:(id<AVSMedia>)media;
- (void)didFinishPlayingMedia:(id<AVSMedia>)media;

@end

@protocol AVSMedia <NSObject>

- (void)play;
- (void)stop;

- (void)pause;
- (void)resume;

@property (nonatomic, copy) NSString *name;

@property (nonatomic, weak) id<AVSMediaDelegate> delegate;

@property (nonatomic, assign) float volume;
@property (nonatomic, assign) BOOL looping;

@property (nonatomic, assign) BOOL playbackMuted;
@property (nonatomic, assign) BOOL recordingMuted;

@optional
@property (nonatomic, assign) void* sound;

@end
