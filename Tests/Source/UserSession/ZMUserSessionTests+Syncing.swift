////
// Wire
// Copyright (C) 2019 Wire Swiss GmbH
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

import XCTest

class ZMUserSessionTests_Syncing: ZMUserSessionTestsBase {
    
    // MARK: Helpers
    
    class InitialSyncObserver : NSObject, ZMInitialSyncCompletionObserver {
        
        var didNotify : Bool = false
        var initialSyncToken : Any?
        
        init(context: NSManagedObjectContext) {
            super.init()
            initialSyncToken = ZMUserSession.addInitialSyncCompletionObserver(self, context: context)
        }
        
        func initialSyncCompleted() {
            didNotify = true
        }
    }
    
    
    // MARK: Slow Sync
    
    func testThatObserverSystemIsDisabledDuringSlowSync() {
        
        // given
        sut.didFinishSlowSync()
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        XCTAssertFalse(sut.notificationDispatcher.isDisabled)
        
        // when
        sut.didStartSlowSync()
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertTrue(sut.notificationDispatcher.isDisabled)
    }
    
    func testThatObserverSystemIsEnabledAfterSlowSync() {
        
        // given
        sut.didStartSlowSync()
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        XCTAssertTrue(sut.notificationDispatcher.isDisabled)
        
        // when
        sut.didFinishSlowSync()
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertFalse(sut.notificationDispatcher.isDisabled)
    }
    
    func testThatInitialSyncIsCompletedAfterSlowSync() {
        
        // given
        sut.didStartSlowSync()
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        XCTAssertFalse(sut.hasCompletedInitialSync)
        
        // when
        sut.didFinishSlowSync()
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertTrue(sut.hasCompletedInitialSync)
    }
    
    func testThatItNotifiesObserverWhenInitialIsSyncCompleted(){
        // given
        let observer = InitialSyncObserver(context: uiMOC)
        sut.didStartSlowSync()
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        XCTAssertFalse(observer.didNotify)
        
        // when
        sut.didFinishSlowSync()
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertTrue(observer.didNotify)
    }
    
    func testThatPerformingSyncIsStillOngoingAfterSlowSync() {
        
        // given
        sut.didStartSlowSync()
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        XCTAssertTrue(sut.isPerformingSync)
        
        // when
        sut.didFinishSlowSync()
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertTrue(sut.isPerformingSync)
    }
    
    // MARK: Quick Sync

    func testThatPerformingSyncIsFinishedAfterQuickSync() {
        
        // given
        sut.didStartQuickSync()
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        XCTAssertTrue(sut.isPerformingSync)
        
        // when
        sut.didFinishQuickSync()
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertFalse(sut.isPerformingSync)
    }
    
}
