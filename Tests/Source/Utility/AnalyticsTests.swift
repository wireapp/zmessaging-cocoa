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
import ZMTesting
@testable import zmessaging



class AnalyticsTests: XCTestCase {
    
    var analytics: MockAnalytics!
    
    override func setUp() {
        super.setUp()
        analytics = MockAnalytics()
    }
    
    func testThatItSetsAnalyticsOnManagedObjectContext() {
        // given
        let context = NSManagedObjectContext.createSyncContext()
        context.markAsSyncContext()
        
        // when
        context.analytics = analytics
        
        // then
        XCTAssertNotNil(context.analytics)
        XCTAssertEqual(context.analytics as? MockAnalytics, analytics)
        context.analytics = nil
        XCTAssertNil(context.analytics)
    }
}

// MARK: - Calling
extension AnalyticsTests {
    
    func testVOIPTimeDifferenceTracking() {
        // given
        let notificationID = NSUUID.createUUID()
        let serverTime = NSDate(timeIntervalSince1970: 1234567890)
        let currentTime = serverTime.dateByAddingTimeInterval(4.5) // Simulate VoIP arriving in OperationLoop after 4.5 sec
        let referenceDate = currentTime.dateByAddingTimeInterval(0.25) // Simulate VoIP arriving in PingBackStatus after 250 ms

        // when
        let tracker = APNSPerformanceTracker()

        let operationLoopState = NotificationFunnelState.OperationLoop(serverTimestamp: serverTime, notificationsEnabled: true, background: true, currentDate: currentTime)
        tracker.trackNotification(notificationID, state: operationLoopState, analytics: analytics, currentDate: currentTime)
        tracker.trackNotification(notificationID, state: .PingBackStatus, analytics: analytics, currentDate: referenceDate)

        // then
        XCTAssertTrue(analytics.taggedEvents.isEmpty)
        XCTAssertEqual(analytics.taggedEventsWithAttributes.count, 2) // UserSession & OperationLoop
        let firstEventWithAttribute = analytics.taggedEventsWithAttributes.first
        let secondEventWithAttribute = analytics.taggedEventsWithAttributes.last

        let firstExpected = EventWithAttributes(event: "apns_performance", attributes: [
            "server_timestamp_difference": "4000-5000",
            "notification_identifier": notificationID.transportString(),
            "state_description": "OperationLoop",
            "state_index": 0,
            "allowed_notifications": true,
            "background": true
        ])

        XCTAssertEqual(firstEventWithAttribute, firstExpected)

        let secondExpected = EventWithAttributes(event: "apns_performance", attributes: [
            "notification_identifier": notificationID.transportString(),
            "state_description": "PingBackStatus",
            "state_index": 1,
            "time_since_last": "200-500"
        ])
        
        XCTAssertEqual(secondEventWithAttribute, secondExpected)
    }
    
}

// MARK: - Address book tag
extension AnalyticsTests {
    
    func testThatItTracksTheAddresBookSizeWhenThereIsNoLastUploadDate() {
        assertThatItTracksAddresBookUploadEnded(0)
    }

    
    func testThatItTracksTheAddresBookSizeWhenThereIsALastUploadDate() {
        assertThatItTracksAddresBookUploadEnded(12)
    }

    
    func testThatItDoesNotTrackTheIntervalSinceLastAddresBookUploadIfTheLastDateIsInTheFuture() {
        assertThatItTracksAddresBookUploadEnded(-42, shouldTrackInterval: false)
    }
    
    func testThatItTracksAddresBookUploadStarted() {
        // given
        let size : UInt = 345
        let tracker = zmessaging.AddressBookAnalytics(analytics: analytics)
        
        // when
        tracker.tagAddressBookUploadStarted(size)
        
        // then
        XCTAssertTrue(analytics.taggedEvents.isEmpty)
        XCTAssertEqual(analytics.taggedEventsWithAttributes.count, 1)
        let eventWithAtributes = analytics.taggedEventsWithAttributes.first!
        XCTAssertEqual(eventWithAtributes.event, "connect.started_addressbook_search")
        XCTAssertEqual(eventWithAtributes.attributes, ["size": size])
    }
}

extension AnalyticsTests {
    
    func assertThatItTracksAddresBookUploadEnded(hoursSinceLastUpload: Int? = nil, shouldTrackInterval: Bool = true, line: UInt = #line) {
        // given
        let tracker = zmessaging.AddressBookAnalytics(analytics: analytics)
        if let hours = hoursSinceLastUpload.map(NSTimeInterval.init) {
            let lastDate = NSDate(timeIntervalSinceNow: -hours * 3600)
            NSUserDefaults.standardUserDefaults().setObject(lastDate, forKey: "lastAddressBookUploadDate")
        }

        // when
        tracker.tagAddressBookUploadSuccess()
        
        // then
        XCTAssertTrue(analytics.taggedEvents.isEmpty)
        XCTAssertEqual(analytics.taggedEventsWithAttributes.count, 1, line: line)
        let eventWithAtributes = analytics.taggedEventsWithAttributes.first!
        XCTAssertEqual(eventWithAtributes.event, "connect.completed_addressbook_search", line: line)
        
        var attributes: [String: NSObject] = [:]
        
        if let hours = hoursSinceLastUpload where shouldTrackInterval { attributes["interval"] = hours }
        XCTAssertEqual(eventWithAtributes.attributes, attributes, line: line)
        
        NSUserDefaults.standardUserDefaults().setObject(nil, forKey: "lastAddressBookUploadDate")
    }
}

// MARK: - Helpers
struct EventWithAttributes: Equatable {
    let event: String
    let attributes: [String: NSObject]
}

func ==(lhs: EventWithAttributes, rhs: EventWithAttributes) -> Bool {
    return lhs.event == rhs.event && lhs.attributes == rhs.attributes
}

final class MockAnalytics: NSObject, AnalyticsType {
    
    @objc func tagEvent(event: String) {
        taggedEvents.append(event)
    }
    
    @objc func tagEvent(event: String, attributes: [String : NSObject]) {
        taggedEventsWithAttributes.append(EventWithAttributes(event: event, attributes: attributes))
    }
    
    @objc func upload() {
        uploadCallCount += 1
    }
    
    var taggedEvents = [String]()
    var taggedEventsWithAttributes = [EventWithAttributes]()
    var uploadCallCount = 0
}
