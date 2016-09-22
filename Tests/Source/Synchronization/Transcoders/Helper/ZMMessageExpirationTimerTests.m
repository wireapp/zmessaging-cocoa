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

#import "MessagingTest.h"
#import "ZMMessageExpirationTimer.h"

#if TARGET_OS_IPHONE
#import "ZMLocalNotificationDispatcher.h"
#else
@interface ZMLocalNotificationDispatcher :NSObject
- (void) didFailToSentMessage:(id)obj;
@end
@implementation ZMLocalNotificationDispatcher: NSObject
- (void) didFailToSentMessage:(id)obj { (void) obj; }
@end
#endif

@interface ZMMessageExpirationTimerTests : MessagingTest

@property (nonatomic) ZMMessageExpirationTimer *sut;
@property (nonatomic) id mockLocalNotificationDispatcher;
@end



@implementation ZMMessageExpirationTimerTests

- (void)setUp
{
    [super setUp];
    self.mockLocalNotificationDispatcher = [OCMockObject mockForClass:ZMLocalNotificationDispatcher.class];
    [self verifyMockLater:self.mockLocalNotificationDispatcher];
    
    self.sut = [[ZMMessageExpirationTimer alloc] initWithManagedObjectContext:self.uiMOC entityName:[ZMTextMessage entityName] localNotificationDispatcher:self.mockLocalNotificationDispatcher];
}

- (void)tearDown
{
    [self.sut tearDown];
    self.mockLocalNotificationDispatcher = nil;
    self.sut = nil;
    [super tearDown];
}

- (ZMTextMessage *)setupTextMessageWithExpirationTime:(NSTimeInterval)expirationTime
{
    ZMTextMessage *textMessage = [ZMTextMessage insertNewObjectInManagedObjectContext:self.uiMOC];
    [ZMMessage setDefaultExpirationTime:expirationTime];
    [textMessage setExpirationDate];
    XCTAssertFalse(textMessage.isExpired);
    XCTAssert([self.uiMOC saveOrRollback]);
    [ZMMessage resetDefaultExpirationTime];
    return textMessage;
}


- (void)checkThatMessage:(ZMMessage *)message isExpiredWithFailureRecorder:(ZMTFailureRecorder *)failureRecorder
{
    WaitForAllGroupsToBeEmpty(0.5);
    FHAssertFalse(failureRecorder, message.hasChanges);
    FHAssertEqualObjects(failureRecorder, message.expirationDate, nil);
    FHAssertEqual(failureRecorder, message.isExpired, YES);
}

- (void)waitForMessage:(ZMMessage *)message toExpireWithFailureRecorder:(ZMTFailureRecorder *)failureRecorder
{
    FHAssertTrue(failureRecorder, [self waitOnMainLoopUntilBlock:^BOOL{
        return message.isExpired == YES;
    } timeout:2.2]);
}




- (void)testThatItExpiresAMessageImmediately
{
    // given
    ZMTextMessage *textMessage = [self setupTextMessageWithExpirationTime:-2];
    [[self.mockLocalNotificationDispatcher stub] didFailToSentMessage:textMessage];
    
    // when
    [self.sut objectsDidChange:[NSSet setWithObject:textMessage]];
    
    // then
    [self checkThatMessage:textMessage isExpiredWithFailureRecorder:NewFailureRecorder()];
}

- (void)testThatItExpiresAMessageWhenItsTimeRunsOut
{
    // given
    ZMTextMessage *textMessage = [self setupTextMessageWithExpirationTime:0.1];
    [[self.mockLocalNotificationDispatcher stub] didFailToSentMessage:textMessage];

    // when
    [self.sut objectsDidChange:[NSSet setWithObject:textMessage]];
    [self waitForMessage:textMessage toExpireWithFailureRecorder:NewFailureRecorder()];
    
    // then
    [self checkThatMessage:textMessage isExpiredWithFailureRecorder:NewFailureRecorder()];
}

#if TARGET_OS_IPHONE
- (void)testThatItNotifiesTheLocalNotificaitonDispatcherWhenItsTimeRunsOut
{
    // given
    ZMTextMessage *textMessage = [self setupTextMessageWithExpirationTime:0.2];
    
    // expect
    [[self.mockLocalNotificationDispatcher expect] didFailToSentMessage:textMessage];
    
    // when
    [self.sut objectsDidChange:[NSSet setWithObject:textMessage]];
    [self waitForMessage:textMessage toExpireWithFailureRecorder:NewFailureRecorder()];
    
    // then
    [self checkThatMessage:textMessage isExpiredWithFailureRecorder:NewFailureRecorder()];
    [self.mockLocalNotificationDispatcher verify];
}
#endif

- (void)testThatItDoesNotExpireAMessageWhenTheEventIDIsSet
{
    // given
    ZMTextMessage *textMessage = [self setupTextMessageWithExpirationTime:0.2];
    textMessage.eventID = [self createEventID];
     
    // when
    [self.sut objectsDidChange:[NSSet setWithObject:textMessage]];
    
    [self spinMainQueueWithTimeout:0.2];
    
    // then
    XCTAssertFalse(textMessage.isExpired);
}

- (void)testThatItExpiresAMessageWhenTheEventIDIsNotSet
{
    // given
    ZMTextMessage *textMessage = [self setupTextMessageWithExpirationTime:0.1];
    [[self.mockLocalNotificationDispatcher stub] didFailToSentMessage:textMessage];

    // when
    [self.sut objectsDidChange:[NSSet setWithObject:textMessage]];
    
    XCTAssertTrue([self waitOnMainLoopUntilBlock:^BOOL{
        return textMessage.isExpired == YES;
    } timeout:0.5]);
    
    // then
    XCTAssertTrue(textMessage.isExpired);
}

- (void)testThatItDoesNotExpireAMessageForWhichTheTimerWasStopped
{
    // given
    ZMTextMessage *textMessage = [self setupTextMessageWithExpirationTime:0.2];
    [self.sut objectsDidChange:[NSSet setWithObject:textMessage]];
    
    // when
    [self.sut stopTimerForMessage:textMessage];
    
    [self spinMainQueueWithTimeout:0.4];
    
    // then
    XCTAssertNotNil(textMessage.expirationDate);
    XCTAssertFalse(textMessage.isExpired);

}


- (void)testThatItDoesNotExpireAMessageThatHasNoExpirationDate
{
    // given
    ZMTextMessage *textMessage = [self setupTextMessageWithExpirationTime:0];
    [textMessage removeExpirationDate];
    
    // when
    [self.sut objectsDidChange:[NSSet setWithObject:textMessage]];
    
    [self spinMainQueueWithTimeout:0.2];
    
    // then
    XCTAssertNil(textMessage.expirationDate);
    XCTAssertFalse(textMessage.isExpired);
}



- (void)testThatItStartsTimerForStoredMessagesOnFirstRequest
{
    // given
    ZMTextMessage *textMessage = [self setupTextMessageWithExpirationTime:0.2];
    [[self.mockLocalNotificationDispatcher stub] didFailToSentMessage:textMessage];

    // when
    [ZMChangeTrackerBootstrap bootStrapChangeTrackers:@[self.sut] onContext:self.uiMOC];
    [self waitForMessage:textMessage toExpireWithFailureRecorder:NewFailureRecorder()];
    
    // then
    XCTAssertNil(textMessage.expirationDate);
    XCTAssertTrue(textMessage.isExpired);
}

- (void)testThatItDoesNotHaveMessageTimersRunningWhenThereIsNoMessage
{
    XCTAssertFalse(self.sut.hasMessageTimersRunning);
}

- (void)testThatItDoesNotHaveMessageTimersRunningWhenThereIsNoMessageBecauseTheyAreExpired
{
    // given
    ZMTextMessage *textMessage = [self setupTextMessageWithExpirationTime:-2];
    
    // when
    [self.sut objectsDidChange:[NSSet setWithObject:textMessage]];
    WaitForAllGroupsToBeEmpty(0.5);

    //then
    XCTAssertFalse(self.sut.hasMessageTimersRunning);
}


- (void)testThatItDoesNotHaveMessageTimersRunningAfterAMessageExpires
{
    // given
    ZMTextMessage *textMessage = [self setupTextMessageWithExpirationTime:0.01];
    [[self.mockLocalNotificationDispatcher stub] didFailToSentMessage:textMessage];
    
    // when
    [self.sut objectsDidChange:[NSSet setWithObject:textMessage]];
    XCTAssertTrue([self waitOnMainLoopUntilBlock:^BOOL{
        return ! self.sut.hasMessageTimersRunning;
    } timeout:0.5]);
    
    
    //then
    XCTAssertFalse(self.sut.hasMessageTimersRunning);
}


- (void)testThatItHasMessageTimersRunningWhenThereIsAMessage
{
    // given
    ZMTextMessage *textMessage = [self setupTextMessageWithExpirationTime:0.7];
    
    // when
    [self.sut objectsDidChange:[NSSet setWithObject:textMessage]];
    WaitForAllGroupsToBeEmpty(0.5);

    //then
    XCTAssertTrue(self.sut.hasMessageTimersRunning);
}

@end



@implementation ZMMessageExpirationTimerTests (SlowSync)

- (void)testThatItReturnsCorrectFetchRequest
{
    // when
    NSFetchRequest *request = [self.sut fetchRequestForTrackedObjects];
    
    // then
    NSFetchRequest *expected = [ZMMessage sortedFetchRequestWithPredicate:[ZMMessage predicateForMessagesThatWillExpire]];
    XCTAssertEqualObjects(request, expected);
}

- (void)testThatItAddsObjectsThatNeedProcessing
{
    // given
    ZMTextMessage *textMessage = [self setupTextMessageWithExpirationTime:0.4];
    ZMTextMessage *anotherTextMessage = [self setupTextMessageWithExpirationTime:0.4];
    
    // this message should be ignored
    ZMKnockMessage *knockMessage = [ZMKnockMessage insertNewObjectInManagedObjectContext:self.uiMOC];
    [ZMMessage setDefaultExpirationTime:0.4];
    [knockMessage setExpirationDate];
    XCTAssert([self.uiMOC saveOrRollback]);
    [ZMMessage resetDefaultExpirationTime];

    XCTAssertFalse(self.sut.hasMessageTimersRunning);

    // when
    [self.sut addTrackedObjects:[NSSet setWithObjects:textMessage, anotherTextMessage, knockMessage, nil]];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertTrue(self.sut.hasMessageTimersRunning);
    XCTAssertEqual(self.sut.runningTimersCount, 2u);
}

@end
