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


#if TARGET_OS_IPHONE

@import UIKit;

@class ZMUpstreamModifiedObjectSync;
@class ZMConversation;
@class CTCall;
@class ZMCallStateLogger;
@class ZMSyncStatus;

extern NSString *const ZMInterruptedCallConversationObjectIDKey;

/*!
    @brief The GSMCallHandler is handling incoming GSM calls while there is on ongoing wire call.
    
    @discussion
    If the user initiates or joins a call, you need to call <b>setActiveCallSyncConversation</b> with the conversation that has the incoming call
 
    When the user leaves the call, you need to call <b>setActiveCallSyncConversation</b> again and set nil as parameter
 
    Internally the GSMCallHandler sets up a CTCallCenter with a callEventHandler that makes sure we send a request to the BE about an incoming call and rejoin or end the call when the interruption ends.
*/
@interface ZMGSMCallHandler : NSObject

- (instancetype)initWithUIManagedObjectContext:(NSManagedObjectContext *)uiMOC
                      syncManagedObjectContext:(NSManagedObjectContext *)syncMOC
                               callStateLogger:(ZMCallStateLogger*)logger;

/*!
    Call this method to set or reset the active call conversation (when the user joins or leaves a voiceChannel)
    @param conversation can be set to nil to reset the callConversation
*/
- (void)setActiveCallSyncConversation:(ZMConversation *)conversation;

/*!
    Call this method to check if the passed in conversation is a call conversation
 */
- (BOOL)isInterruptedCallConversation:(ZMConversation *)conversation;

@end



@interface ZMGSMCallHandler (Testing)

- (instancetype)initWithUIManagedObjectContext:(NSManagedObjectContext *)uiMOC
                      syncManagedObjectContext:(NSManagedObjectContext *)syncMOC
                               callStateLogger:(ZMCallStateLogger*)logger
                                    callCenter:(CTCallCenter *)callCenter;

@property (nonatomic, readonly) BOOL hasStoredInterruptedCallConversation;
@property (nonatomic, readonly) ZMConversation *activeCallUIConversation;
@property (nonatomic, readonly, copy) void (^callEventHandler)(CTCall *);

- (void)tearDown;

@end

#endif

