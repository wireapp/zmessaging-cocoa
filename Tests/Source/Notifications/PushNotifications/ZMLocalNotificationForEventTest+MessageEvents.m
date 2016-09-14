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


@import ZMTesting;
@import ZMUtilities;
#import <zmessaging/zmessaging-Swift.h>
#import "MessagingTest.h"
#import "ZMLocalNotificationForEventTest.h"
#import "zmessaging_iOS_Tests-Swift.h"


@implementation ZMLocalNotificationForEventTest (MessageEvents)

- (void)testThatItHandlesExceptions
{
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // given
        
        NSUUID *conversationID = [NSUUID createUUID];
        
        //create encrypted message
        NSString *encryptedData = @"70XpQ4qri2D4YCU7lvSjaqk+SgN/s4dDv/J8uMUel0xY8quNetPF8cMXskAZwBI9EArjMY/NupWo8Bar14GHi9ISzlOswDsoQ6BQiFsEdnv4shT+ZpJ+wghmPF+sxWhys9048ny6WiSqywUNzsUPjDrudAAiG4bPjS2FjMou2/o7FpCg7+6p8fcSYCcvQllv6P8oidVbMlpnT1Bs7fK6fz9ceq6H3L+BKZai82H7gc6nxSS5Gjf56qvDqdc3J9jTowpdjyqHGO26YahMQtDf4tn6KuTSp4OG1qLPk6jFf4xO2q/WrxV2dnoXGXWbIZ4cnohkeA85QxMhpM9pIGAbZ58fRUt9fPXm6PmX3rqQY7MSv4TV1fLyb5Zqo/yqQbcE2qS/dJKRrzwW5MWlKVWfacuNRZnansMMGUYyt7iRpD/E8PdtSfW7QO/02Evureor7MqQ8AYf6Ivt3Ksf1wplXne0zl8CT5GMeExB7DLfyr8T1xK6H+u3y29FmI9/T01la5cbIq/E83Yh2LTNo3X4eOfZ6mhC0EIC8YEyo/0x2IHsLyCAjzvIFfTSD8tOpa1yQTBSQ3mGGDWiPJ3f6OypQFj+vY13Bq9WZoL9Q+UbYbxdzkaYILaX2UakZ5OafQ7nH0WslvfzjRsdYoruTGDV+E8mXB2JOZh9ij2PT8fWsyJJ9DqKg5Iw2EPfUlXBv3pXIpZuL6+g8c2von092bV2pHTWkPE4A2yvw3LTzI8e9puOr5K87JUQHdR7mfXYifErW+9TRrmBibF5wKZtVl97UOFOps4/ZXU9i6Lr0qKKMdX3iruo7o3fYcbJTajb+sZLttDPsKnJHnnMxJUB3D+I1UuA35hL6Fy2wLj2mRNAzWuitNj9MSDUhDHU42+bZnap";
        
        ZMUpdateEvent *updateEvent = [ZMUpdateEvent eventFromEventStreamPayload:
                                      @{
                                        @"type":@"conversation.otr-message-add",
                                        @"data": encryptedData,
                                        @"conversation":conversationID.transportString,
                                        @"time":[NSDate dateWithTimeIntervalSince1970:555555].transportString
                                        } uuid:nil];
        
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.remoteIdentifier = conversationID;
        [self.syncMOC saveOrRollback];
        
        // when
        __block ZMLocalNotificationForEvent * note;
        [self performIgnoringZMLogError:^{
            note = [ZMLocalNotificationForEvent notificationForEvent:updateEvent managedObjectContext:self.syncMOC application:self.application];
        }];
        
        // then
        XCTAssertNil(note);
    }];
}


@end
