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

@import WireMessageStrategy;
#import <Foundation/Foundation.h>
#import "ZMUpdateEventsBuffer.h"

@class ZMConnectionTranscoder;
@class ZMUserTranscoder;
@class ZMSelfTranscoder;
@class ZMConversationTranscoder;
@class ZMMissingUpdateEventsTranscoder;
@class ZMRegistrationTranscoder;
@class ZMFlowSync;
@class ZMCallStateTranscoder;
@class ZMLastUpdateEventIDTranscoder;
@class ZMLoginTranscoder;
@class ZMPhoneNumberVerificationTranscoder;
@class ZMLoginCodeRequestTranscoder;

@protocol ZMUpdateEventsFlushableCollection;



@protocol ZMObjectStrategyDirectory <NSObject, ZMUpdateEventsFlushableCollection>

@property (nonatomic, readonly) ZMConnectionTranscoder *connectionTranscoder;
@property (nonatomic, readonly) ZMUserTranscoder *userTranscoder;
@property (nonatomic, readonly) ZMSelfTranscoder *selfTranscoder;
@property (nonatomic, readonly) ZMConversationTranscoder *conversationTranscoder;
@property (nonatomic, readonly) SystemMessageEventsConsumer *systemMessageEventConsumer;
@property (nonatomic, readonly) ClientMessageTranscoder *clientMessageTranscoder;
@property (nonatomic, readonly) ZMMissingUpdateEventsTranscoder *missingUpdateEventsTranscoder;
@property (nonatomic, readonly) ZMLastUpdateEventIDTranscoder *lastUpdateEventIDTranscoder;
@property (nonatomic, readonly) ZMRegistrationTranscoder *registrationTranscoder;
@property (nonatomic, readonly) ZMPhoneNumberVerificationTranscoder *phoneNumberVerificationTranscoder;
@property (nonatomic, readonly) ZMLoginTranscoder *loginTranscoder;
@property (nonatomic, readonly) ZMLoginCodeRequestTranscoder *loginCodeRequestTranscoder;
@property (nonatomic, readonly) ZMFlowSync *flowTranscoder;
@property (nonatomic, readonly) ZMCallStateTranscoder *callStateTranscoder;


@property (nonatomic, readonly) NSManagedObjectContext *moc;

- (NSArray *)allTranscoders;

- (NSArray *)conversationIdsThatHaveBufferedUpdatesForCallState;

@end
