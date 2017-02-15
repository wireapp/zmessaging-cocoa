//
// Wire
// Copyright (C) 2017 Wire Swiss GmbH
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
import WireMessageStrategy

class CallingRequestStrategyTests : MessagingTest {

    var sut: CallingRequestStrategy!
    var mockRegistrationDelegate : ClientRegistrationDelegate!
    
    override func setUp() {
        super.setUp()
        mockRegistrationDelegate = MockClientRegistrationDelegate()
        sut = CallingRequestStrategy(managedObjectContext: uiMOC, clientRegistrationDelegate: mockRegistrationDelegate)
    }
    
    override func tearDown() {
        sut = nil
        mockRegistrationDelegate = nil
        super.tearDown()
    }
    
    func testThatItReturnsItselfAndTheGenericMessageStrategyAsContextChangeTracker(){
        // when
        let trackers = sut.contextChangeTrackers
        
        // then
        XCTAssertTrue(trackers.first is CallingRequestStrategy)
        XCTAssertTrue(trackers.last is GenericMessageRequestStrategy)
    }
}
