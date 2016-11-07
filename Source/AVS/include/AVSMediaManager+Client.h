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
//  AVSMediaManager+UI.h
//  zmm
//

#import <Foundation/Foundation.h>

#import "AVSMediaManager.h"


@class AVSMediaManagerClientChangeNotification;


@protocol AVSMediaManagerClientObserver <NSObject>

- (void)mediaManagerDidChange:(AVSMediaManagerClientChangeNotification *)notification;

@end


@interface AVSMediaManagerClientChangeNotification : NSNotification

@property (nonatomic, readonly) AVSMediaManager *manager;
@property (nonatomic, readonly) BOOL intensityLevelChanged;
@property (nonatomic, readonly) BOOL speakerEnableChanged;
@property (nonatomic, readonly) BOOL speakerMuteChanged;
@property (nonatomic, readonly) BOOL microphoneMuteChanged;
@property (nonatomic, readonly) BOOL audioControlChanged;

+ (void)addObserver:(id <AVSMediaManagerClientObserver>)observer;
+ (void)removeObserver:(id <AVSMediaManagerClientObserver>)observer;

@end


/// Media manager category designed specifically for the client usage
@interface AVSMediaManager (Client)

+ (instancetype)sharedInstance;

- (void)playSound:(NSString *)name;
- (void)stopSound:(NSString *)name;

- (void)registerMediaFromConfiguration:(NSDictionary *)configuration inDirectory:(NSString *)directory;

/// Check if application is in control of the audio session or it has been highjacked by another application
//@property (nonatomic, readonly) BOOL isInControlOfAudio;

/// Controls notification intensity level
@property (nonatomic, assign) AVSIntensityLevel intensityLevel;

/// Sound can be forced to come out of the speaker rather than earpiece or headphones using
@property (nonatomic, assign, getter=isSpeakerEnabled) BOOL speakerEnabled;

/// Controls speaker sound
//@property (nonatomic, assign, getter=isSpeakerMuted) BOOL speakerMuted;

/// Controls microphone muting
@property (nonatomic, assign, getter=isMicrophoneMuted) BOOL microphoneMuted;

- (void)routeChanged:(AVSPlaybackRoute)route;

@end

