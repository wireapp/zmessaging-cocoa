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


@testable import WireSyncEngine
import WireTesting
import WireMockTransport

// MARK: - Mocks


@objc class MockAuthenticationProvider: NSObject, AuthenticationStatusProvider {
    var mockIsAuthenticated: Bool = true
    
    var isAuthenticated: Bool {
        return mockIsAuthenticated
    }
}

@objc class FakeGroupQueue : NSObject, ZMSGroupQueue {
    
    var dispatchGroup : ZMSDispatchGroup! {
        return nil
    }
    
    func performGroupedBlock(_ block : @escaping () -> Void) {
        block()
    }
    
}

// MARK: - Tests

class PushNotificationStatusTests: ZMTBaseTest {
    
    var sut: PushNotificationStatus!
    
    
    override func setUp() {
        super.setUp()
        
        sut = PushNotificationStatus()
    }
    
    override func tearDown() {
        sut = nil
        
        super.tearDown()
    }
    
    func testThatStatusIsInProgressWhenAddingEventIdToFetch() {
        // given
        let eventId = UUID.create()
        
        
        // when
        sut.fetch(eventId: eventId) { (_) in }
        
        // then
        XCTAssertEqual(sut.status, .inProgress)
    }
    
    func testThatStatusIsInProgressWhenNotAllEventsIdsHaveBeenFetched() {
        // given
        let eventId1 = UUID.create()
        let eventId2 = UUID.create()
        
        sut.fetch(eventId: eventId1) { (_) in }
        sut.fetch(eventId: eventId2) { (_) in }
        
        // when
        sut.didFetch(eventIds: [eventId1], finished: true)
        
        // then
        XCTAssertEqual(sut.status, .inProgress)
    }
    
    func testThatStatusIsDoneAfterEventIdIsFetched() {
        // given
        let eventId = UUID.create()
        sut.fetch(eventId: eventId) { (_) in }
        
        // when
        sut.didFetch(eventIds: [eventId], finished: true)
        
        // then
        XCTAssertEqual(sut.status, .done)
    }
    
    func testThatStatusIsDoneAfterEventIdIsFetchedEvenIfMoreEventsWillBeFetched() {
        // given
        let eventId = UUID.create()
        sut.fetch(eventId: eventId) { (_) in }
        
        // when
        sut.didFetch(eventIds: [eventId], finished: false)
        
        // then
        XCTAssertEqual(sut.status, .done)
    }
    
    func testThatStatusIsDoneIfEventsCantBeFetched() {
        // given
        let eventId = UUID.create()
        sut.fetch(eventId: eventId) { (_) in }
        
        // when
        sut.didFailToFetchEvents()
        
        // then
        XCTAssertEqual(sut.status, .done)
    }
    
    func testThatCompletionHandlerIsCalledAfterAllEventsHasBeenFetched() {
        // given
        let eventId = UUID.create()
        sut.fetch(eventId: eventId) { (result) in
            _ = self.expectation(description: "completion handler was called")
        }
        
        // when
        sut.didFetch(eventIds: [eventId], finished: true)
        
        // then
        XCTAssertEqual(sut.status, .done)
        XCTAssertTrue(waitForCustomExpectations(withTimeout: 0.5))
    }
    
}

