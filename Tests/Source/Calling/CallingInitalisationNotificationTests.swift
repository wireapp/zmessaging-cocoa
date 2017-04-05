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


import WireTesting

@testable import WireSyncEngine

class CallingInitialisationNotificationTests : MessagingTest {
    
    func testThatItSendTheCorrectNotification() {
        
        func checkThatItNotifiyWithErrorType(_ errorCode: VoiceChannelV2ErrorCode) -> Bool {
            var isCorrectErrorType = false
            // given
            NotificationCenter.default.addObserver(forName: Notification.Name(rawValue: CallingInitialisationNotification.Name), object: nil, queue: nil) {
                // then
                guard let callingNotification = $0.object as? CallingInitialisationNotification else {
                    XCTFail()
                    return
                }
                if (callingNotification.errorCode == errorCode) {
                    isCorrectErrorType = true
                }
            }
            // when
            CallingInitialisationNotification.notifyCallingFailedWithErrorCode(errorCode)
            
            // then
            return isCorrectErrorType
        }
        
        //when
        XCTAssertTrue(checkThatItNotifiyWithErrorType(.ongoingGSMCall))
        
        //when
        XCTAssertTrue(checkThatItNotifiyWithErrorType(.switchToAudioNotAllowed))
        
        //when
        XCTAssertTrue(checkThatItNotifiyWithErrorType(.switchToVideoNotAllowed))
        
        //when
        XCTAssertTrue(checkThatItNotifiyWithErrorType(.videoCallingNotSupported))
    }
}
