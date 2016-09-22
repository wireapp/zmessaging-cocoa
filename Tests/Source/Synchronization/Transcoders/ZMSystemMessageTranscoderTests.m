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

#import "ZMMessageTranscoderTests.h"
#import "ZMMessageTranscoder+Internal.h"



@interface ZMSystemMessageTranscoderTests : ZMMessageTranscoderTests

@end

@implementation ZMSystemMessageTranscoderTests

- (ZMMessageTranscoder *)sut
{
    if (!_sut) {
        _sut = [ZMMessageTranscoder systemMessageTranscoderWithManagedObjectContext:self.syncMOC
                                                        localNotificationDispatcher:self.notificationDispatcher];
    }
    return _sut;
}

- (void)testThatItCreatesSystemMessagesFromAPushEvent
{
    ZMUpdateEventType types[] = {
        
        // ZMUpdateEventConversationMessageAdd,
        //        ZMUpdateEventConversationKnock,
        //        ZMUpdateEventConversationAssetAdd,
        ZMUpdateEventConversationMemberJoin,
        ZMUpdateEventConversationMemberLeave,
        ZMUpdateEventConversationRename,
        //        ZMUpdateEventConversationMemberUpdate,
        //        ZMUpdateEventConversationVoiceChannelActivate,
        //        ZMUpdateEventConversationVoiceChannel,
        ZMUpdateEventConversationCreate,
        //        ZMUpdateEventConversationConnectRequest,
        //        ZMUpdateEventUserUpdate,
        //        ZMUpdateEventUserNew,
        //        ZMUpdateEventUserConnection
    };
    
    // given
    ZMSystemMessage *mockSystemMessage = [OCMockObject mockForClass:ZMSystemMessage.class];
    ZMUpdateEvent *event = [OCMockObject mockForClass:ZMUpdateEvent.class];
    
    const size_t len = sizeof(types)/sizeof(types[0]);
    
    for(size_t i = 0; i < len; ++i) {
        ZMUpdateEventType currentType = types[i];
        [self.syncMOC performGroupedBlockAndWait:^{
            
            // given
            (void)[(ZMUpdateEvent *)[[(id)event stub] andReturnValue:OCMOCK_VALUE(currentType)] type];
            
            // expect
            [[(id)mockSystemMessage expect] createOrUpdateMessageFromUpdateEvent:event inManagedObjectContext:self.syncMOC prefetchResult:nil];
            
            // when
            [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
            
        }];
    }
    
    // then
    [(id)mockSystemMessage stopMocking];
    [(id)mockSystemMessage verify];
    [(id)event stopMocking];
}

- (void)testThatItSetsHasUnreadMissedCallWhenReceivingAMissedCallEvent
{
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // given
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.lastReadServerTimeStamp = [NSDate date];
        conversation.remoteIdentifier = [NSUUID createUUID];
        
        [self.syncMOC saveOrRollback];
        
        NSDate *newDate = [NSDate date];
        
        NSDictionary *payload = @{
                                  @"conversation" : conversation.remoteIdentifier.transportString,
                                  @"data" : @{@"reason": @"missed"},
                                  @"from" : @"08316f5e-3c0a-4847-a235-2b4d93f291a4",
                                  @"time" : newDate.transportString,
                                  @"type" : @"conversation.voice-channel-deactivate",
                                  @"id"   : self.createEventID.transportString
                                  };
        
        ZMUpdateEvent *updateEvent = [ZMUpdateEvent eventFromEventStreamPayload:payload uuid:nil];
        XCTAssertNotNil(updateEvent);
        
        // expect
        [[self.notificationDispatcher expect] processMessage: OCMOCK_ANY];
        
        // when
        [self.sut processEvents:@[updateEvent] liveEvents:NO prefetchResult:nil];
        
        // then
        XCTAssertEqual(conversation.conversationListIndicator, ZMConversationListIndicatorMissedCall);
        XCTAssertFalse([conversation.keysThatHaveLocalModifications containsObject:ZMConversationHasUnreadMissedCallKey]);
    }];
}


@end
