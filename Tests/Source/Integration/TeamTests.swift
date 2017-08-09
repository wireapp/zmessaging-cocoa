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
import WireDataModel
@testable import WireSyncEngine

class TestTeamObserver : NSObject, TeamObserver {

    var token : NSObjectProtocol!
    var observedTeam : Team?
    var notifications: [TeamChangeInfo] = []
    
    init(team: Team? = nil) {
        super.init()
        token = TeamChangeInfo.add(observer: self, for: team)
    }
    
    deinit {
        TeamChangeInfo.remove(observer: token, for: nil)
    }
    
    func teamDidChange(_ changeInfo: TeamChangeInfo) {
        if let observedTeam = observedTeam, (changeInfo.team as? Team) != observedTeam {
            return
        }
        notifications.append(changeInfo)
    }
}

class TeamTests : IntegrationTest {
    
    override func setUp() {
        super.setUp()
        
        createSelfUserAndConversation()
        createExtraUsersAndConversations()
    }

    func remotelyInsertTeam(members: [MockUser], isBound: Bool = true) -> MockTeam {
        var mockTeam : MockTeam!
        mockTransportSession.performRemoteChanges { (session) in
            mockTeam = session.insertTeam(withName: "Super-Team", isBound: isBound, users: Set(members))
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        return mockTeam
    }
}


// MARK : Notifications

extension TeamTests {
    
    func testThatItNotifiesAboutChangedTeamName(){
        // given
        let mockTeam = remotelyInsertTeam(members: [self.selfUser, self.user1])

        XCTAssert(login())
        guard let localSelfUser = user(for: selfUser) else { return XCTFail() }
        XCTAssertTrue(localSelfUser.hasTeam)
        
        let teamObserver = TestTeamObserver()
        
        // when
        mockTransportSession.performRemoteChanges { (session) in
            mockTeam.name = "Super-Duper-Team"
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(teamObserver.notifications.count, 1)
        guard let note = teamObserver.notifications.last else {
            return XCTFail("no notification received")
        }
        XCTAssertTrue(note.nameChanged)
    }
}


// MARK : Member removal
extension TeamTests {
    
    func testThatOtherUserCanBeRemovedRemotely(){
        // given
        let mockTeam = remotelyInsertTeam(members: [self.selfUser, self.user1])

        XCTAssert(login())

        let user = self.user(for: user1)!
        let localSelfUser = self.user(for: selfUser)!
        XCTAssert(user.hasTeam)
        XCTAssert(localSelfUser.hasTeam)

        // when
        mockTransportSession.performRemoteChanges { (session) in
            session.removeMember(with: self.user1, from: mockTeam)
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertFalse(user.hasTeam)
    }
    
    func testThatSelfUserCanBeRemovedRemotely(){
        // given
        let mockTeam = remotelyInsertTeam(members: [self.selfUser, self.user1])

        XCTAssert(login())

        XCTAssert(ZMUser.selfUser(in: userSession!.managedObjectContext).hasTeam)
        
        // when
        mockTransportSession.performRemoteChanges { (session) in
            session.removeMember(with: self.selfUser, from: mockTeam)
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertFalse(ZMUser.selfUser(in: userSession!.managedObjectContext).hasTeam)
    }
    
    func testThatItNotifiesAboutSelfUserRemovedRemotely(){
        // given
        let mockTeam = remotelyInsertTeam(members: [self.selfUser, self.user1])

        XCTAssert(login())
        let selfUserObserver = UserChangeObserver(user: ZMUser.selfUser(in: userSession!.managedObjectContext))!

        // when
        mockTransportSession.performRemoteChanges { (session) in
            session.removeMember(with: self.selfUser, from: mockTeam)
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertGreaterThanOrEqual(selfUserObserver.notifications.count, 1)
        guard let userChange = selfUserObserver.notifications.firstObject as? UserChangeInfo else {
            return XCTFail("no notification received")
        }
        XCTAssertTrue(userChange.teamsChanged)
    }
    
    func testThatItNotifiesAboutOtherUserRemovedRemotely(){
        // given
        let mockTeam = remotelyInsertTeam(members: [self.selfUser, self.user1])

        XCTAssert(login())
        let teamObserver = TestTeamObserver()
        
        // when
        mockTransportSession.performRemoteChanges { (session) in
            session.removeMember(with: self.user1, from: mockTeam)
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(teamObserver.notifications.count, 1)
        guard let change = teamObserver.notifications.last else {
            return XCTFail("no notification received")
        }
        XCTAssertTrue(change.membersChanged)
    }
    
    func testThatItDeletesAllTeamConversationsWhenTheSelfMemberIsRemoved() {
        // given
        let mockTeam = remotelyInsertTeam(members: [self.selfUser, self.user1])

        XCTAssert(login())
        let list = ZMConversationList.conversations(inUserSession: self.userSession!)
        XCTAssertEqual(list.count, 3)

        mockTransportSession.performRemoteChanges { (session) in
            session.insertTeamConversation(to: mockTeam, with: [self.selfUser, self.user1], creator: self.user1)
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        let listObserver = ConversationListChangeObserver(conversationList: list)!
        XCTAssertEqual(list.count, 4)
        
        // when
        mockTransportSession.performRemoteChanges { (session) in
            session.removeMember(with: self.selfUser, from: mockTeam)
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(list.count, 3)
        
        XCTAssertEqual(listObserver.notifications.count, 1)
        guard let note = listObserver.notifications.lastObject as? ConversationListChangeInfo else {
            return XCTFail("no notification received")
        }
        XCTAssertEqual(note.deletedIndexes, [0])
    }

}


// MARK : Member adding

extension TeamTests {
    
    func testThatOtherUserCanBeAddedRemotely(){
        // given
        let mockTeam = remotelyInsertTeam(members: [self.selfUser])
        XCTAssert(login())
        
        let user = self.user(for: user1)!
        XCTAssertFalse(user.hasTeam)
        
        // when
        mockTransportSession.performRemoteChanges { (session) in
            session.insertMember(with: self.user1, in: mockTeam)
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssert(user.hasTeam)
    }
    
    func testThatItNotifiesAboutOtherUserAddedRemotely(){
        // given
        let mockTeam = remotelyInsertTeam(members: [self.selfUser])

        XCTAssert(login())
        let teamObserver = TestTeamObserver()
        
        // when
        mockTransportSession.performRemoteChanges { (session) in
            session.insertMember(with: self.user1, in: mockTeam)
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(teamObserver.notifications.count, 1)
        guard let memberChange = teamObserver.notifications.last else {
            return XCTFail("no notification received")
        }
        XCTAssertTrue(memberChange.membersChanged)
    }
    
}

// MARK : Remotely Deleted Team

extension TeamTests {

    // See TeamSyncRequestStrategy.skipTeamSync
    func testThatItDeletesARemotelyDeletedTeamAfterPerfomingSlowSyncCausedByMissedEvents() {
        XCTAssert(login())
        
        // Given
        // 1. Insert local team, which will not be returned by mock transport when fetching /teams
        let localOnlyTeamId = UUID.create()
        let localOnlyTeam = Team.insertNewObject(in: userSession!.managedObjectContext)
        localOnlyTeam.remoteIdentifier = localOnlyTeamId
        XCTAssert(userSession!.managedObjectContext.saveOrRollback())
        
        // 2. Force a slow sync by returning a 404 when hitting /notifications
        mockTransportSession.responseGeneratorBlock = { request in
            if request.path.hasPrefix("/notifications") && !request.path.contains("cancel_fallback") {
                defer { self.mockTransportSession.responseGeneratorBlock = nil }
                return ZMTransportResponse(payload: nil, httpStatus: 404, transportSessionError: nil)
            }
            return nil
        }
        
        // When
        recreateSessionManager() // this will trigger a quick sync
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // Then
        // Assert that the local team got deleted after trying to refetch it AFTER the slow sync was performed.
        let team = Team.fetch(withRemoteIdentifier: localOnlyTeamId, in: userSession!.managedObjectContext)
        XCTAssert(team == nil || team!.isDeleted)
    }

}
