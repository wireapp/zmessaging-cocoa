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

import XCTest
@testable import WireSyncEngine

typealias FileManagerProtocol = WireSyncEngine.FileManagerProtocol

class MockFileManager: FileManagerProtocol {
    var containerURL: URL?
    var calledGroupIdentifier: String?
    func containerURL(forSecurityApplicationGroupIdentifier groupIdentifier: String) -> URL? {
        calledGroupIdentifier = groupIdentifier
        return containerURL
    }

    var urlsForDirectory = [URL]()
    var calledDomainMask: FileManager.SearchPathDomainMask?
    var calledDirectory: FileManager.SearchPathDirectory?
    func urls(for directory: FileManager.SearchPathDirectory, in domainMask: FileManager.SearchPathDomainMask) -> [URL] {
        calledDirectory = directory
        calledDomainMask = domainMask
        return urlsForDirectory
    }
}

class LocalStoreProviderTests: ZMTBaseTest {
    
    var sut: LocalStoreProvider!
    var fileManager: MockFileManager!
    var appGroupIdentifier: String!
    var bundleIdentifier: String!
    
    override func setUp() {
        super.setUp()
        fileManager = MockFileManager()
        bundleIdentifier = "com.some.app"
        appGroupIdentifier = "group." + bundleIdentifier
        sut = LocalStoreProvider(bundleIdentifier: bundleIdentifier, appGroupIdentifier: appGroupIdentifier, fileManager: fileManager)
    }
    
    override func tearDown() {
        sut = nil
        fileManager = nil
        appGroupIdentifier = nil
        super.tearDown()
    }
}

// MARK: - Initialization
extension LocalStoreProviderTests {
    
    func testThatItHasGroupIdentifierFromMainBundle() {
        // given
        let groupIdentifier = "group.\(Bundle.main.bundleIdentifier!)"
        
        // when
        let sut = LocalStoreProvider()
        
        // then
        XCTAssertEqual(sut.appGroupIdentifier, groupIdentifier)
    }
    
    func testThatItIsInitializedWithDefaultFileManager() {
        // given
        let defaultFileManager: FileManagerProtocol = FileManager.default
        
        // when
        let sut = LocalStoreProvider()

        // then
        XCTAssert(sut.fileManager === defaultFileManager)
    }
}

// MARK: - Properties
extension LocalStoreProviderTests {

    func testThatSharedContainerDirectoryIsProvidedFromFileManager() {
        // given
        fileManager.containerURL = URL(fileURLWithPath: "some/file/path")
        XCTAssertNotNil(fileManager.containerURL)
        
        // when
        let containerURL = sut.sharedContainerDirectory
        
        // then
        XCTAssertEqual(containerURL, fileManager.containerURL)
        XCTAssertEqual(fileManager.calledGroupIdentifier, appGroupIdentifier)
    }
    
    func testItFallsBackToUserDocumentsDirectoryIfSharedContainerIsNotAvailable() {
        // given
        fileManager.containerURL = nil
        let documentsDirectory = URL(fileURLWithPath: "path/to/documents")
        fileManager.urlsForDirectory = [documentsDirectory]
        
        // when
        var containerURL: URL?
        performIgnoringZMLogError {
            containerURL = self.sut.sharedContainerDirectory
        }
        
        // then
        XCTAssertEqual(containerURL, documentsDirectory)
        XCTAssertEqual(fileManager.calledDomainMask, .userDomainMask)
        XCTAssertEqual(fileManager.calledDirectory, .documentDirectory)
    }
    
    func testThatCachesAreNilWhenContainerIsNil() {
        // given
        fileManager.containerURL = nil
        
        // then
        XCTAssertNil(sut.cachesURL)
    }
    
    func testThatCachesIsInSharedContainer_Library_Caches() {
        // given
        let containerURL = URL(fileURLWithPath: "some/file/path")
        let cachesURL = containerURL.appendingPathComponent("Library/Caches/")
        fileManager.containerURL = containerURL
        XCTAssertNotNil(fileManager.containerURL)
        
        // when
        XCTAssertEqual(sut.cachesURL, cachesURL)
        
        // then
        XCTAssertEqual(fileManager.calledGroupIdentifier, appGroupIdentifier)
    }

    func testThatKeyStoreIsInSharedContainer() {
        // given
        let containerURL = URL(fileURLWithPath: "some/file/path")
        fileManager.containerURL = containerURL
        XCTAssertNotNil(fileManager.containerURL)

        // then
        XCTAssertEqual(sut.keyStoreURL, containerURL)
    }
    
    func testThatKeyStoreIsNilWhenContainerIsNil() {
        // given
        fileManager.containerURL = nil
        
        // then
        performIgnoringZMLogError {
            XCTAssertNil(self.sut.keyStoreURL)
        }
    }
    
    func testThatStoreURLIsInSharedContainer_bundleId() {
        // given
        let containerURL = URL(fileURLWithPath: "some/file/path")
        let storeURL = containerURL.appendingPathComponent("\(bundleIdentifier!)/store.wiredatabase")
        fileManager.containerURL = containerURL
        XCTAssertNotNil(fileManager.containerURL)
        
        // then
        XCTAssertEqual(sut.storeURL, storeURL)
    }
}
