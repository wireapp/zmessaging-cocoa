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

@testable import WireSyncEngine

class SearchResultTests : MessagingTest {
    
    func testThatItFiltersConnectedUsers() {
        // given
        let connectedUser = ZMUser.insertNewObject(in: uiMOC)
        connectedUser.remoteIdentifier = UUID.create()
        
        let connection = ZMConnection.insertNewObject(in: uiMOC)
        connection.to = connectedUser
        connection.status = .accepted
        
        uiMOC.saveOrRollback()
        
        let handle = "fabio"
        let payload = ["documents": [
            ["id" : connectedUser.remoteIdentifier!,
             "name": "Maria",
             "accent_id": 4],
            ["id" : UUID.create().uuidString,
             "name": "Fabio",
             "accent_id": 4,
             "handle" : handle]
            ]]
        
        // when
        let result = SearchResult(payload: payload, query: "", userSession: mockUserSession)
        
        // then
        XCTAssertEqual(result?.directory.count, 1)
        XCTAssertEqual(result?.directory.first!.handle, handle)
    }
    
    func testThatItFiltersTeamMembers() {
        // given
        let team = Team.insertNewObject(in: uiMOC)
        let user = ZMUser.insertNewObject(in: uiMOC)
        let member = Member.insertNewObject(in: uiMOC)
        
        user.name = "Member A"
        user.remoteIdentifier = UUID.create()
        
        member.team = team
        member.user = user
        
        uiMOC.saveOrRollback()
        
        let handle = "fabio"
        let payload = ["documents": [
            ["id" : user.remoteIdentifier!,
             "name": "Member A",
             "accent_id": 4],
            ["id" : UUID.create().uuidString,
             "name": "Fabio",
             "accent_id": 4,
             "handle" : handle]
            ]]
        
        // when
        let result = SearchResult(payload: payload, query: "", userSession: mockUserSession)
        
        // then
        XCTAssertEqual(result?.directory.count, 1)
        XCTAssertEqual(result?.directory.first!.handle, handle)
    }
    
    func testThatItReturnsAllResultsWhenTheQueryIsNotAHandle() {
        // given
        let name = "User"
        let payload = ["documents": [
            ["id" : UUID.create().uuidString,
             "name": name,
             "accent_id": 4],
            ["id" : UUID.create().uuidString,
             "name": "Fabio",
             "accent_id": 4,
             "handle" : "aa\(name.lowercased())"]
            ]]
        
        // when
        let result = SearchResult(payload: payload, query: name, userSession: mockUserSession)
        
        // then
        XCTAssertEqual(result?.directory.count, 2)
    }
    
    func testThatItReturnsOnlyMatchingHandleResultsWhenTheQueryIsAHandle() {
        // given
        let name = "User";
        let expectedHandle = "aa\(name.lowercased())"
        
        let payload = ["documents": [
            ["id" : UUID.create().uuidString,
             "name": name,
             "accent_id": 4],
            ["id" : UUID.create().uuidString,
             "name": "Fabio",
             "accent_id": 4,
             "handle" : "aa\(name.lowercased())"]
            ]]
        
        // when
        let result = SearchResult(payload: payload, query: "@\(name)", userSession: mockUserSession)!
        
        // then
        XCTAssertEqual(result.directory.count, 1)
        XCTAssertEqual(result.directory.first!.handle, expectedHandle)
    }
        
}
