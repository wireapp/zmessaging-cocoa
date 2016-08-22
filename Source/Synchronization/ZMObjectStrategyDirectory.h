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


#import <Foundation/Foundation.h>
#import "ZMUpdateEventsBuffer.h"

@class ZMConnectionTranscoder;
@class ZMUserTranscoder;
@class ZMSelfTranscoder;
@class ZMMessageTranscoder;
@class ZMConversationTranscoder;
@class ZMAssetTranscoder;
@class ZMUserImageTranscoder;
@class ZMMissingUpdateEventsTranscoder;
@class ZMRegistrationTranscoder;
@class ZMFlowSync;
@class ZMPushTokenTranscoder;
@class ZMCallStateTranscoder;
@class ZMLastUpdateEventIDTranscoder;
@class ZMLoginTranscoder;
@class ZMKnockTranscoder;
@class ZMSearchUserImageTranscoder;
@class ZMTypingTranscoder;
@class ZMRemovedSuggestedPeopleTranscoder;
@class ZMPhoneNumberVerificationTranscoder;
@class ZMLoginCodeRequestTranscoder;
@class ZMUserProfileUpdateTranscoder;

@protocol ZMUpdateEventsFlushableCollection;



@protocol ZMObjectStrategyDirectory <NSObject, ZMUpdateEventsFlushableCollection>

@property (nonatomic, readonly) ZMConnectionTranscoder *connectionTranscoder;
@property (nonatomic, readonly) ZMUserTranscoder *userTranscoder;
@property (nonatomic, readonly) ZMSelfTranscoder *selfTranscoder;
@property (nonatomic, readonly) ZMConversationTranscoder *conversationTranscoder;
@property (nonatomic, readonly) ZMMessageTranscoder *systemMessageTranscoder;
@property (nonatomic, readonly) ZMMessageTranscoder *clientMessageTranscoder;
@property (nonatomic, readonly) ZMKnockTranscoder *knockTranscoder;
@property (nonatomic, readonly) ZMAssetTranscoder *assetTranscoder;
@property (nonatomic, readonly) ZMUserImageTranscoder *userImageTranscoder;
@property (nonatomic, readonly) ZMMissingUpdateEventsTranscoder *missingUpdateEventsTranscoder;
@property (nonatomic, readonly) ZMLastUpdateEventIDTranscoder *lastUpdateEventIDTranscoder;
@property (nonatomic, readonly) ZMRegistrationTranscoder *registrationTranscoder;
@property (nonatomic, readonly) ZMPhoneNumberVerificationTranscoder *phoneNumberVerificationTranscoder;
@property (nonatomic, readonly) ZMLoginTranscoder *loginTranscoder;
@property (nonatomic, readonly) ZMLoginCodeRequestTranscoder *loginCodeRequestTranscoder;
@property (nonatomic, readonly) ZMFlowSync *flowTranscoder;
@property (nonatomic, readonly) ZMCallStateTranscoder *callStateTranscoder;
@property (nonatomic, readonly) ZMPushTokenTranscoder *pushTokenTranscoder;
@property (nonatomic, readonly) ZMSearchUserImageTranscoder *searchUserImageTranscoder;
@property (nonatomic, readonly) ZMTypingTranscoder *typingTranscoder;
@property (nonatomic, readonly) ZMRemovedSuggestedPeopleTranscoder *removedSuggestedPeopleTranscoder;
@property (nonatomic, readonly) ZMUserProfileUpdateTranscoder *userProfileUpdateTranscoder;

@property (nonatomic, readonly) NSManagedObjectContext *moc;

- (NSArray *)allTranscoders;

- (NSArray *)conversationIdsThatHaveBufferedUpdatesForCallState;

@end
