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

class TeamTests : IntegrationTestBase {

    func remotelyInsertTeam(members: [MockUser]) -> MockTeam {
        var mockTeam : MockTeam!
        mockTransportSession.performRemoteChanges { (session) in
            mockTeam = session.insertTeam(withName: "Super-Team", users: Set(members))
        }
        XCTAssert(waitForEverythingToBeDone())
        return mockTeam
    }
}



    // MARK : Notifications

extension TeamTests {
    

    func testThatItNotifiesAboutNewTeamInsertedRemotely(){
        // given
        XCTAssert(logInAndWaitForSyncToBeComplete())
        let selfUserObserver = UserChangeObserver(user: ZMUser.selfUser(in: uiMOC))!

        // when
        _ = remotelyInsertTeam(members: [self.selfUser, self.user1])
        
        // then
        XCTAssertEqual(ZMUser.selfUser(in: uiMOC).teams.count, 1)

        XCTAssertEqual(selfUserObserver.notifications.count, 1)
        guard let note = selfUserObserver.notifications.lastObject as? UserChangeInfo else {
            return XCTFail("no notification received")
        }
        XCTAssertTrue(note.teamsChanged)
    }
    
    func testThatItNotifiesAboutChangedTeamName(){
        // given
        XCTAssert(logInAndWaitForSyncToBeComplete())
        let mockTeam = remotelyInsertTeam(members: [self.selfUser, self.user1])
        
        let teamObserver = TestTeamObserver()
        
        // when
        mockTransportSession.performRemoteChanges { (session) in
            mockTeam.name = "Super-Duper-Team"
        }
        XCTAssert(waitForEverythingToBeDone())
        
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
        XCTAssert(logInAndWaitForSyncToBeComplete())
        let mockTeam = remotelyInsertTeam(members: [self.selfUser, self.user1])

        let user = self.user(for: user1)!
        XCTAssertEqual(user.teams.count, 1)
        
        // when
        mockTransportSession.performRemoteChanges { (session) in
            session.removeMember(with: self.user1, from: mockTeam)
        }
        XCTAssert(waitForEverythingToBeDone())
        
        // then
        XCTAssertEqual(user.teams.count, 0)
    }
    
    func testThatSelfUserCanBeRemovedRemotely(){
        // given
        XCTAssert(logInAndWaitForSyncToBeComplete())
        let mockTeam = remotelyInsertTeam(members: [self.selfUser, self.user1])
        
        XCTAssertEqual(ZMUser.selfUser(in: uiMOC).teams.count, 1)
        
        // when
        mockTransportSession.performRemoteChanges { (session) in
            session.removeMember(with: self.selfUser, from: mockTeam)
        }
        XCTAssert(waitForEverythingToBeDone())
        
        // then
        XCTAssertEqual(ZMUser.selfUser(in: uiMOC).teams.count, 0)
    }
    
    func testThatItNotifiesAboutSelfUserRemovedRemotely(){
        // given
        XCTAssert(logInAndWaitForSyncToBeComplete())
        let mockTeam = remotelyInsertTeam(members: [self.selfUser, self.user1])
        let selfUserObserver = UserChangeObserver(user: ZMUser.selfUser(in: uiMOC))!

        // when
        mockTransportSession.performRemoteChanges { (session) in
            session.removeMember(with: self.selfUser, from: mockTeam)
        }
        XCTAssert(waitForEverythingToBeDone())
        
        // then
        XCTAssertEqual(selfUserObserver.notifications.count, 1)
        guard let userChange = selfUserObserver.notifications.lastObject as? UserChangeInfo else {
            return XCTFail("no notification received")
        }
        XCTAssertTrue(userChange.teamsChanged)
    }
    
    func testThatItNotifiesAboutOtherUserRemovedRemotely(){
        // given
        XCTAssert(logInAndWaitForSyncToBeComplete())
        let mockTeam = remotelyInsertTeam(members: [self.selfUser, self.user1])
        let teamObserver = TestTeamObserver()
        
        // when
        mockTransportSession.performRemoteChanges { (session) in
            session.removeMember(with: self.user1, from: mockTeam)
        }
        XCTAssert(waitForEverythingToBeDone())
        
        // then
        XCTAssertEqual(teamObserver.notifications.count, 1)
        guard let change = teamObserver.notifications.last else {
            return XCTFail("no notification received")
        }
        XCTAssertTrue(change.membersChanged)
    }
    
    func disabled_testThatItDeletesAllConversationsWhenTheSelfMemberIsRemoved() {
        // given
        XCTAssert(logInAndWaitForSyncToBeComplete())
        let mockTeam = remotelyInsertTeam(members: [self.selfUser, self.user1])

        mockTransportSession.performRemoteChanges { (session) in
            session.insertTeamConversation(to: mockTeam, with: [self.selfUser, self.user1])
        }
        XCTAssert(waitForEverythingToBeDone())
        
        let team = self.team(for: mockTeam)
        let list = ZMConversationList.conversations(inUserSession: self.userSession, team: team)
        let listObserver = ConversationListChangeObserver(conversationList: list)!
        
        XCTAssertEqual(list.count, 1)
        
        // when
        mockTransportSession.performRemoteChanges { (session) in
            //session.removeMember(self.selfUser, fromTeam: mockTeam)
        }
        XCTAssert(waitForEverythingToBeDone())
        
        // then
        XCTAssertEqual(list.count, 0)
        
        XCTAssertEqual(listObserver.notifications.count, 1)
        guard let note = listObserver.notifications.lastObject as? ConversationListChangeInfo else {
            return XCTFail("no notification received")
        }
        XCTAssertEqual(note.deletedIndexes, [0])
    }

}


// MARK : Member adding

extension TeamTests {
    
    func testThatSelfUserCanBeAddedRemotely(){
        // given
        XCTAssert(logInAndWaitForSyncToBeComplete())
        let mockTeam = remotelyInsertTeam(members: [self.user1])
        XCTAssertEqual(ZMUser.selfUser(in: uiMOC).teams.count, 0)

        // when
        mockTransportSession.performRemoteChanges { (session) in
            session.insertMember(with: self.selfUser, in: mockTeam)
        }
        XCTAssert(waitForEverythingToBeDone())
        
        // then
        XCTAssertEqual(ZMUser.selfUser(in: uiMOC).teams.count, 1)
    }
    
    func testThatOtherUserCanBeAddedRemotely(){
        // given
        XCTAssert(logInAndWaitForSyncToBeComplete())
        let mockTeam = remotelyInsertTeam(members: [self.selfUser])
        
        let user = self.user(for: user1)!
        XCTAssertEqual(user.teams.count, 0)

        
        // when
        mockTransportSession.performRemoteChanges { (session) in
            session.insertMember(with: self.user1, in: mockTeam)
        }
        XCTAssert(waitForEverythingToBeDone())
        
        // then
        XCTAssertEqual(user.teams.count, 1)

    }
    
    func testThatItNotifiesAboutSelfUserAddedRemotely(){
        // given
        XCTAssert(logInAndWaitForSyncToBeComplete())
        let mockTeam = remotelyInsertTeam(members: [self.user1])
        
        let selfUserObserver = UserChangeObserver(user: ZMUser.selfUser(in: uiMOC))!
        let teamObserver = TestTeamObserver()
        
        // when
        mockTransportSession.performRemoteChanges { (session) in
            session.insertMember(with: self.selfUser, in: mockTeam)
        }
        XCTAssert(waitForEverythingToBeDone())
        
        // then
        XCTAssertEqual(selfUserObserver.notifications.count, 1)
        guard let userChange = selfUserObserver.notifications.lastObject as? UserChangeInfo else {
            return XCTFail("no notification received")
        }
        XCTAssertTrue(userChange.teamsChanged)
        
        XCTAssertEqual(teamObserver.notifications.count, 2)
        guard let nameChange = teamObserver.notifications.first, let memberChange = teamObserver.notifications.last else {
            return XCTFail("no notification received")
        }
        XCTAssertTrue(nameChange.nameChanged)
        XCTAssertTrue(memberChange.membersChanged)
    }
    
    func testThatItNotifiesAboutOtherUserAddedRemotely(){
        // given
        XCTAssert(logInAndWaitForSyncToBeComplete())
        let mockTeam = remotelyInsertTeam(members: [self.selfUser])
        let teamObserver = TestTeamObserver()
        
        // when
        mockTransportSession.performRemoteChanges { (session) in
            session.insertMember(with: self.user1, in: mockTeam)
        }
        XCTAssert(waitForEverythingToBeDone())
        
        // then
        XCTAssertEqual(teamObserver.notifications.count, 1)
        guard let memberChange = teamObserver.notifications.last else {
            return XCTFail("no notification received")
        }
        XCTAssertTrue(memberChange.membersChanged)
    }
    
}

// MARK : Conversation Member Handling

extension TeamTests {

    func testThatYouCanAddAMemberToATeamConversation_SelfIsMember(){
    
    }
    
    func testThatYouCanRemoveAMemberFromATeamConversation_SelfIsMember(){
    
    }

    func testThatYouCanNotAddAMemberToATeamConversation_SelfIsGuest(){
        
    }
    
    func testThatYouCanNOTRemoveAMemberFromATeamConversation_SelfIsGuest(){
    
    }

}

// MARK : Remotely Deleted Team

extension TeamTests {

    func testThatItDeltesARemotelyDeletedTeamAfterPerfomingSlowSyncCausedByMissedEvents() {
        // Given
        // 1. Insert local team, which will not be returned by mock transport when fetching /teams
        let localOnlyTeamId = UUID.create()
        let localOnlyTeam = Team.insertNewObject(in: uiMOC)
        localOnlyTeam.remoteIdentifier = localOnlyTeamId
        XCTAssert(uiMOC.saveOrRollback())

        // 2. Force a slow sync by returning a 404 when hitting /notifications
        mockTransportSession.responseGeneratorBlock = { request in
            if request.path.hasPrefix("/notifications") && !request.path.contains("cancel_fallback") {
                defer { self.mockTransportSession.responseGeneratorBlock = nil }
                return ZMTransportResponse(payload: nil, httpStatus: 404, transportSessionError: nil)
            }
            return nil
        }

        // When
        XCTAssert(logInAndWaitForSyncToBeComplete())
        XCTAssert(waitForEverythingToBeDone())

        // Then
        // Assert that the local team got deleted after trying to refetch it AFTER the slow sync was performed.
        let team = Team.fetch(withRemoteIdentifier: localOnlyTeamId, in: uiMOC)
        XCTAssert(team == nil || team!.isDeleted)
    }

}
