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


import Foundation
import XCTest
import WireTesting
@testable import WireSyncEngine



class AnalyticsTests: ZMTBaseTest {
    
    var analytics: MockAnalytics!
    var directory: ManagedObjectContextDirectory!
    var sharedContainerURL : URL!
    var accountID : UUID!

    func createSyncContext() -> NSManagedObjectContext {
        let expectation = self.expectation(description: "create directory")
        StorageStack.shared.createManagedObjectContextDirectory(accountIdentifier: accountID, applicationContainer: sharedContainerURL) {
            self.directory = $0
            expectation.fulfill()
        }
        XCTAssert(self.waitForCustomExpectations(withTimeout: 0.5))
        return self.directory.syncContext
    }

    override func setUp() {
        super.setUp()
        analytics = MockAnalytics()
        accountID = UUID()
        sharedContainerURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
    
    override func tearDown() {
        sharedContainerURL = nil
        directory = nil
        accountID = nil
        analytics = nil
        StorageStack.reset()
        super.tearDown()
    }
    
    func testThatItSetsAnalyticsOnManagedObjectContext() {
        // given
        let context = createSyncContext()
        
        // when
        context.analytics = analytics
        
        // then
        XCTAssertNotNil(context.analytics)
        XCTAssertEqual(context.analytics as? MockAnalytics, analytics)
        context.analytics = nil
        XCTAssertNil(context.analytics)
    }
}
