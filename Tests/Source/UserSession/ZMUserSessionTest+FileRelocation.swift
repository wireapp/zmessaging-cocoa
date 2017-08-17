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

class ZMUserSessionRelocationTests : ZMUserSessionTestsBase {

    func testThatItMovesCaches() throws {
        // given
        let oldLocation = FileManager.default.cachesURLForAccount(with: nil, in: self.sut.sharedContainerURL)
        if FileManager.default.fileExists(atPath: oldLocation.path) {
            let items = try! FileManager.default.contentsOfDirectory(at: oldLocation, includingPropertiesForKeys:nil)
            items.forEach{ try! FileManager.default.removeItem(at: $0) }
        }
        
        let _ = UserImageLocalCache(location: oldLocation)
        let itemNames = try! FileManager.default.contentsOfDirectory(atPath: oldLocation.path)
        XCTAssertTrue(itemNames.count > 0)
        
        // when
        ZMUserSession.moveCachesIfNeededForAccount(with: self.userIdentifier, in: self.sut.sharedContainerURL)
        
        // then
        let newLocation = FileManager.default.cachesURLForAccount(with: self.userIdentifier, in: self.sharedContainerURL)
        let movedItemNames = try FileManager.default.contentsOfDirectory(atPath: newLocation.path)
        XCTAssertTrue(movedItemNames.count > 0)
        itemNames.forEach {
            XCTAssertTrue(movedItemNames.contains($0))
        }
    }
}
