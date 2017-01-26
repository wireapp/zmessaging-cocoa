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
    
    func createSyncMOC() -> NSManagedObjectContext {
        let storeURL = PersistentStoreRelocator.storeURL(in: .documentDirectory)
        let keyStoreURL = storeURL?.deletingLastPathComponent()
        
        return NSManagedObjectContext.createSyncContextWithStore(at: storeURL, keyStore: keyStoreURL)
    }
    
    override func setUp() {
        super.setUp()
        analytics = MockAnalytics()
    }
    
    func testThatItSetsAnalyticsOnManagedObjectContext() {
        // given
        let context = createSyncMOC()
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
        let notificationID = UUID.create()
        let serverTime = Date(timeIntervalSince1970: 1234567890)
        let currentTime = serverTime.addingTimeInterval(4.5) // Simulate VoIP arriving in OperationLoop after 4.5 sec
        let referenceDate = currentTime.addingTimeInterval(0.25) // Simulate VoIP arriving in PingBackStatus after 250 ms

        // when
        let tracker = APNSPerformanceTracker()

        let operationLoopState = NotificationFunnelState.operationLoop(serverTimestamp: serverTime, notificationsEnabled: true, background: true, currentDate: currentTime)
        tracker.trackNotification(notificationID, state: operationLoopState, analytics: analytics, currentDate: currentTime)
        tracker.trackNotification(notificationID, state: .pingBackStatus, analytics: analytics, currentDate: referenceDate)

        // then
        XCTAssertTrue(analytics.taggedEvents.isEmpty)
        XCTAssertEqual(analytics.taggedEventsWithAttributes.count, 2) // UserSession & OperationLoop
        let firstEventWithAttribute = analytics.taggedEventsWithAttributes.first
        let secondEventWithAttribute = analytics.taggedEventsWithAttributes.last

        let firstExpected = EventWithAttributes(event: "apns_performance", attributes: [
            "server_timestamp_difference": "4000-5000" as NSObject,
            "notification_identifier": notificationID.transportString() as NSObject,
            "state_description": "OperationLoop" as NSObject,
            "state_index": 0 as NSObject,
            "allowed_notifications": NSNumber(value:true),
            "background": NSNumber(value:true)
        ])

        XCTAssertEqual(firstEventWithAttribute, firstExpected)

        let secondExpected = EventWithAttributes(event: "apns_performance", attributes: [
            "notification_identifier": notificationID.transportString() as NSObject,
            "state_description": "PingBackStatus" as NSObject,
            "state_index": 1 as NSObject,
            "time_since_last": "200-500" as NSObject
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
    
    func testThatItDoesTrackTheIntervalBetweenTwoUploads() {
        // given
        let tracker = zmessaging.AddressBookAnalytics(analytics: analytics, managedObjectContext: createSyncMOC())
        
        
        // when
        tracker.tagAddressBookUploadSuccess()
        tracker.tagAddressBookUploadSuccess()
        
        // then
        XCTAssertTrue(analytics.taggedEvents.isEmpty)
        XCTAssertEqual(analytics.taggedEventsWithAttributes.count, 2)
        let eventWithAtributes = analytics.taggedEventsWithAttributes.last!
        XCTAssertEqual(eventWithAtributes.event, "connect.completed_addressbook_search")
        XCTAssertEqual((eventWithAtributes.attributes["interval"] as? NSNumber)?.intValue, 0)
    }
    
    func testThatItTracksAddresBookUploadStarted() {
        // given
        let size : UInt = 345
        let tracker = zmessaging.AddressBookAnalytics(analytics: analytics, managedObjectContext: createSyncMOC())
        
        // when
        tracker.tagAddressBookUploadStarted(size)
        
        // then
        XCTAssertTrue(analytics.taggedEvents.isEmpty)
        XCTAssertEqual(analytics.taggedEventsWithAttributes.count, 1)
        let eventWithAtributes = analytics.taggedEventsWithAttributes.first!
        XCTAssertEqual(eventWithAtributes.event, "connect.started_addressbook_search")
        XCTAssertEqual(eventWithAtributes.attributes, ["size": NSNumber(value: size)])
    }
}

extension AnalyticsTests {
    
    func assertThatItTracksAddresBookUploadEnded(_ hoursSinceLastUpload: Int? = nil, shouldTrackInterval: Bool = true, line: UInt = #line) {
        // given
        let tracker = zmessaging.AddressBookAnalytics(analytics: analytics, managedObjectContext: createSyncMOC())
        if let hours = hoursSinceLastUpload.map(TimeInterval.init) {
            let lastDate = Date(timeIntervalSinceNow: -hours * 3600)
            tracker.managedObjectContext.lastAddressBookUploadDate = lastDate
        }

        // when
        tracker.tagAddressBookUploadSuccess()
        
        // then
        XCTAssertTrue(analytics.taggedEvents.isEmpty)
        XCTAssertEqual(analytics.taggedEventsWithAttributes.count, 1, line: line)
        let eventWithAtributes = analytics.taggedEventsWithAttributes.first!
        XCTAssertEqual(eventWithAtributes.event, "connect.completed_addressbook_search", line: line)
        
        var attributes: [String: NSObject] = [:]
        
        if let hours = hoursSinceLastUpload, shouldTrackInterval {
            attributes["interval"] = NSNumber(value: hours)
        }
        XCTAssertEqual(eventWithAtributes.attributes, attributes, line: line)
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
    
    @objc func tagEvent(_ event: String) {
        taggedEvents.append(event)
    }
    
    @objc func tagEvent(_ event: String, attributes: [String : NSObject]) {
        taggedEventsWithAttributes.append(EventWithAttributes(event: event, attributes: attributes))
    }
    
    @objc func upload() {
        uploadCallCount += 1
    }
    
    var taggedEvents = [String]()
    var taggedEventsWithAttributes = [EventWithAttributes]()
    var uploadCallCount = 0
}
