//
// Wire
// Copyright (C) 2020 Wire Swiss GmbH
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

import XCTest
@testable import WireSyncEngine

class FeatureConfigRequestStrategyTests: MessagingTest {

    var mockApplicationStatus: MockApplicationStatus!
    var sut: FeatureConfigRequestStrategy!

    override func setUp() {
        super.setUp()
        mockApplicationStatus = MockApplicationStatus()
        mockApplicationStatus.mockSynchronizationState = .slowSyncing

        sut = FeatureConfigRequestStrategy(withManagedObjectContext: syncMOC,
                                           applicationStatus: mockApplicationStatus)
    }

    override func tearDown() {
        mockApplicationStatus = nil
        sut = nil
        super.tearDown()
    }

    // MARK: Single configuration
    func test_ItGeneratesARequest_ToFetchASingleConfig() {
        self.syncMOC.performGroupedAndWait { moc in
            // given
            let feature = self.createFeature(.appLock, in: moc)
            feature.needsToBeUpdatedFromBackend = true

            // when
            self.boostrapChangeTrackers(with: feature)
            guard let request = self.sut.nextRequestIfAllowed() else { return XCTFail() }

            // then
            XCTAssertEqual(request.path, "/teams/\(feature.team!.remoteIdentifier!.transportString())/features/appLock")
            return
        }
    }

    func test_ItDoesNotGenerateARequest_ToFetchASingleConfig_WhenNotNeeded() {
        self.syncMOC.performGroupedAndWait { moc in
            // given
            let feature = self.createFeature(.appLock, in: moc)
            feature.needsToBeUpdatedFromBackend = false

            // when
            self.boostrapChangeTrackers(with: feature)
            let request = self.sut.nextRequestIfAllowed()

            // then
            XCTAssertNil(request)
            return
        }
    }

    func test_ItDoesNotGenerateARequest_ToFetchASingleConfig_WithoutATeam() {
        self.syncMOC.performGroupedAndWait { moc in
            // given
            let feature = self.createFeature(.appLock, in: moc)
            feature.team = nil
            feature.needsToBeUpdatedFromBackend = true

            // when
            self.boostrapChangeTrackers(with: feature)
            let request = self.sut.nextRequestIfAllowed()

            // then
            XCTAssertNil(request)
            return
        }
    }

    // MARK: - All configurations
    func test_ItGeneratesARequest_ToFetchAllConfigs() {
        self.syncMOC.performGroupedAndWait { moc in
            // given
            let teamId = self.createTeam(for: .selfUser(in: moc)).remoteIdentifier!

            // when
            Feature.triggerBackendRefreshForAllConfigs()
            guard let request = self.sut.nextRequestIfAllowed() else { return XCTFail() }

            // then
            XCTAssertEqual(request.path, "/teams/\(teamId.transportString())/features")
            return
        }
    }

    func test_ItDoesNotGenerateARequest_ToFetchAllConfigs_WithoutATeam() {
        self.syncMOC.performGroupedAndWait { moc in
            // given
            XCTAssertNil(ZMUser.selfUser(in: moc).team)

            // when
            Feature.triggerBackendRefreshForAllConfigs()
            let request = self.sut.nextRequestIfAllowed()

            // then
            XCTAssertNil(request)
        }
    }

}

// MARK: - Helpers
private extension FeatureConfigRequestStrategyTests {

    @discardableResult
    func createTeam(for user: ZMUser) -> Team {
        let context = user.managedObjectContext!

        let team = Team.insertNewObject(in: context)
        team.name = "Wire Amazing Team"
        team.remoteIdentifier = .create()

        let membership = Member.insertNewObject(in: context)
        membership.team = team
        membership.user = user

        return team
    }

    private func createFeature(_ name: Feature.Name, in context: NSManagedObjectContext) -> Feature {
        return Feature.createOrUpdate(
            name: name,
            status: .enabled,
            config: nil,
            team: createTeam(for: .selfUser(in: context)),
            context: context
        )
    }

    func boostrapChangeTrackers(with objects: ZMManagedObject...) {
        sut.contextChangeTrackers.forEach {
            $0.objectsDidChange(Set(objects))
        }

    }

}
