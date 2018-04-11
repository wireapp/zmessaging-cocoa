//
// Wire
// Copyright (C) 2018 Wire Swiss GmbH
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

import WireDataModel
@testable import WireSyncEngine

class AssetDeletionStatusTests: MessagingTest {
    
    private var sut: AssetDeletionStatus!
    fileprivate var identifierProvider: DeletableAssetIdentifierProvider!
    
    override func setUp() {
        super.setUp()
        identifierProvider = IdentifierProvider()
        sut = AssetDeletionStatus(provider: identifierProvider, queue: FakeGroupQueue())
    }
    
    override func tearDown() {
        identifierProvider = nil
        sut = nil
        super.tearDown()
    }
    
    func testThatItDoesNotReturnAnyIdentifiersInitially() {
        // When
        let identifier = sut.nextIdentifierToDelete()
        
        // Then
        XCTAssertNil(identifier)
    }
    
    func testThatItAddsAnIdentifierToTheList() {
        // Given
        let expected = UUID.create().transportString()
        
        // When
        NotificationCenter.default.post(name: .deleteAssetNotification, object: expected)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // Then
        XCTAssertEqual(identifierProvider.assetIdentifiersToBeDeleted, [expected])
    }
    
    func testThatItReturnsAnIdentifierWhenThereIsOne() {
        // Given
        let expected = UUID.create().transportString()
        identifierProvider.assetIdentifiersToBeDeleted = [expected]
        
        // When
        let identifier = sut.nextIdentifierToDelete()
        
        // Then
        XCTAssertEqual(identifier, expected)
        XCTAssertNil(sut.nextIdentifierToDelete())
    }
    
    func testThatItReturnsAnIdentifierOnlyOnce() {
        // Given
        let firstExpected = UUID.create().transportString()
        let secondExpected = UUID.create().transportString()
        identifierProvider.assetIdentifiersToBeDeleted = [firstExpected, secondExpected]
        
        // When
        guard let first = sut.nextIdentifierToDelete() else { return XCTFail("no first identifier") }
        guard let second = sut.nextIdentifierToDelete() else { return XCTFail("no second identifier") }
        
        // Then
        let expected = Set([firstExpected, secondExpected])
        let actual = Set([first, second])
        XCTAssertEqual(actual, expected)
        XCTAssertNil(sut.nextIdentifierToDelete())
    }
    
    func testThatItFiresANextRequestNotificationIfAnIdentifierIsAdded() {
        // Given
        let expected = UUID.create().transportString()
        
        // Expect
        let requestExpectation = expectation(description: "notification should be posted")
        let observer = MockRequestAvailableObserver(requestAvailable: requestExpectation.fulfill)
        
        // When
        NotificationCenter.default.post(name: .deleteAssetNotification, object: expected)
        
        // Then
        XCTAssert(waitForCustomExpectations(withTimeout: 0.1))
        _ = observer
    }
    
    func testThatItDoesNotReturnAnIdentifierAgainAfterItSucceeded() {
        // Given
        let firstExpected = UUID.create().transportString()
        let secondExpected = UUID.create().transportString()
        let expected = Set([firstExpected, secondExpected])
        identifierProvider.assetIdentifiersToBeDeleted = expected
        guard let first = sut.nextIdentifierToDelete() else { return XCTFail("no first identifier") }
        
        // When
        sut.didDelete(identifier: first)
        
        // Then
        guard let second = sut.nextIdentifierToDelete() else { return XCTFail("no second identifier") }
        XCTAssertNotEqual(first, second)
        XCTAssertNil(sut.nextIdentifierToDelete())
    }
    
    func testThatItDoesNotReturnAnIdentifierAgainAfterItFailed() {
        // Given
        let firstExpected = UUID.create().transportString()
        let secondExpected = UUID.create().transportString()
        let expected = Set([firstExpected, secondExpected])
        identifierProvider.assetIdentifiersToBeDeleted = expected
        guard let first = sut.nextIdentifierToDelete() else { return XCTFail("no first identifier") }
        
        // When
        sut.didFailToDelete(identifier: firstExpected)
        
        // Then
        guard let second = sut.nextIdentifierToDelete() else { return XCTFail("no second identifier") }
        XCTAssertNotEqual(first, second)
        XCTAssertNil(sut.nextIdentifierToDelete())
    }
    
}

// MARK: - Helper

fileprivate class IdentifierProvider: NSObject, DeletableAssetIdentifierProvider {
    var assetIdentifiersToBeDeleted = Set<String>()
}

fileprivate class MockRequestAvailableObserver: NSObject, RequestAvailableObserver {
    
    private let requestAvailable: () -> Void
    
    init(requestAvailable: @escaping () -> Void) {
        self.requestAvailable = requestAvailable
        super.init()
        RequestAvailableNotification.addObserver(self)
    }
    
    deinit {
        RequestAvailableNotification.removeObserver(self)
    }
    
    func newRequestsAvailable() {
        requestAvailable()
    }
}
