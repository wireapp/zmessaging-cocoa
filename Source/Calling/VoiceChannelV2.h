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


@import ZMCSystem;
@import ZMCDataModel;

NS_ASSUME_NONNULL_BEGIN

@class ZMUserSession;
@class ZMUser;
@class VoiceChannelV2ParticipantState;
@protocol CallingInitialisationObserverToken
@end
@protocol CallingInitialisationObserver <NSObject>
- (void)couldNotInitialiseCallWithError:(NSError *)error;
@end


typedef NS_ENUM(uint8_t, VoiceChannelV2ConnectionState) {
    VoiceChannelV2ConnectionStateInvalid,
    VoiceChannelV2ConnectionStateNotConnected,
    VoiceChannelV2ConnectionStateConnecting,    ///<  The user is in the process of joining the media flow channel
    VoiceChannelV2ConnectionStateConnected      ///<  The media flow channel is established.  The user is fully connected and can participate in the voice channel
};

typedef NS_ENUM(uint8_t, VoiceChannelV2State) {
    VoiceChannelV2StateInvalid = 0,
    VoiceChannelV2StateNoActiveUsers, ///< Nobody is active on the voice channel
    VoiceChannelV2StateOutgoingCall, ///< We are connecting and nobody is in a connected state on the voice channel yet (ie: we are calling)
    VoiceChannelV2StateOutgoingCallDegraded, ///< We are doing an outgoing call but we can't proceed since the conversation security is degraded
    VoiceChannelV2StateOutgoingCallInactive, ///< We are connecting and nobody is in a connected state on the voice channel yet (ie: we are calling) but not ringing anymore.
    VoiceChannelV2StateIncomingCall, ///< Someone else is calling (ringing) you on the voice channel.
    VoiceChannelV2StateIncomingCallDegraded, ///< Someone else is calling but we can't proceed since the conversation security is degraded
    VoiceChannelV2StateIncomingCallInactive, ///< Group call is in progress but it's not ringing for us.
    VoiceChannelV2StateSelfIsJoiningActiveChannel, ///< Somebody else is in a connected state on the voice channel and we are connecting (ie: we are joining)
    VoiceChannelV2StateSelfConnectedToActiveChannel, ///< Self connects to voice channel AND there is someone already connected on the channel
    VoiceChannelV2StateDeviceTransferReady, ///< This device is ready to have the call transfered to it
};


typedef NS_ENUM(uint8_t, VoiceChannelV2CallEndReason) {
    VoiceChannelV2CallEndReasonRequested, ///< Default when other user ends the call
    VoiceChannelV2CallEndReasonRequestedSelf, ///< when self user ends the call
    VoiceChannelV2CallEndReasonRequestedAVS, ///< AVS requested to end call. (media wasn't flowing etc.)
    VoiceChannelV2CallEndReasonOtherLostMedia, ///< Other participant lost media flow
    VoiceChannelV2CallEndReasonInterrupted, ///< When GSM call interrupts call
    VoiceChannelV2CallEndReasonDisconnected, ///< When the client disconnects from the service due to other technical reasons
    VoiceChannelV2CallEndReasonInputOutputError ///< When the client disconnects from the service due to input output error (microphone not working)
};

// The voice channel of a conversation.
//
// N.B.: The conversation owns the voice channel, but the voice channel only has a weak reference back to the conversations. Users of the voice channel @b must hold onto a strong reference to the owning conversations. Failure to do so can lead to undefined behaviour.
// !!!: tl;dr Don't hold on to any @c VoiceChannelV2 references. Store the @c ZMConversation reference instead and ask it for the voice channel
//
@interface VoiceChannelV2 : NSObject

- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, readonly) VoiceChannelV2State state;
@property (nonatomic, readonly, weak, nullable) ZMConversation *conversation; ///< The owning conversation

/// The date and time of current call start
@property (nonatomic, copy, readonly, nullable) NSDate *callStartDate;

/// Voice channel participants. May be a subset of conversation participants.
@property (nonatomic, readonly) NSOrderedSet *participants;

/// Returns @c nil if there's no active voice channel
//+ (instancetype)activeVoiceChannelInSession:(id<ZMManagedObjectContextProvider>)session;


/// For each participant call the block with that user and the user's connection state and muted state.
- (void)enumerateParticipantStatesWithBlock:(void(^)(ZMUser *user, VoiceChannelV2ConnectionState connectionState, BOOL muted))block ZM_NON_NULL(1);

- (VoiceChannelV2ParticipantState *)stateForParticipant:(ZMUser *)participant;

@property (nonatomic, readonly) VoiceChannelV2ConnectionState selfUserConnectionState;



/// Adds an observer that notifies if there are errors establishing a video or audio call
/// The returned token needs to be retained and used to remove the observer in removeCallingInitialisationObserver:
- (id<CallingInitialisationObserverToken>)addCallingInitializationObserver:(id<CallingInitialisationObserver>)observer;

/// Unregister from notifications about call establishment
- (void)removeCallingInitialisationObserver:(id<CallingInitialisationObserverToken>)token;

@end

@interface VoiceChannelV2ParticipantState : NSObject

@property (nonatomic, readonly) VoiceChannelV2ConnectionState connectionState;
@property (nonatomic, readonly) BOOL muted;
@property (nonatomic, readonly) BOOL isSendingVideo;

@end


@interface VoiceChannelV2 (ZMDebug)

/// Attributed string to be displayed to the user to help tracking down calling related bugs.
+ (NSAttributedString *)voiceChannelDebugInformation;

@end

NS_ASSUME_NONNULL_END
