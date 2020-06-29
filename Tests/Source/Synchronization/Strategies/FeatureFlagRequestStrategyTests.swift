//
//  FeatureFlagRequestStrategyTests.swift
//  WireSyncEngine-iOS-Tests
//
//  Created by Marco Maddalena on 29/06/2020.
//  Copyright © 2020 Zeta Project Gmbh. All rights reserved.
//

import Foundation
@testable import WireSyncEngine

class FeatureFlagRequestStrategyTests: MessagingTest {
    
    var sut: FeatureFlagRequestStrategy!
    var mockSyncStatus: MockSyncStatus!
    var mockSyncStateDelegate: MockSyncStateDelegate!
    var mockApplicationStatus: MockApplicationStatus!
    
    var selfUser: ZMUser!
    var team: Team!
    
    
    override func setUp() {
        super.setUp()
        mockSyncStateDelegate = MockSyncStateDelegate()
        mockSyncStatus = MockSyncStatus(managedObjectContext: syncMOC, syncStateDelegate: mockSyncStateDelegate)
        mockApplicationStatus = MockApplicationStatus()
        mockApplicationStatus.mockSynchronizationState = .synchronizing
        
        sut = FeatureFlagRequestStrategy(withManagedObjectContext: syncMOC,
                                         applicationStatus: mockApplicationStatus,
                                         syncStatus: mockSyncStatus)
        
        team = Team.insertNewObject(in: self.syncMOC)
        team.name = "Wire Amazing Team"
        team.remoteIdentifier = UUID.create()
        selfUser = ZMUser.selfUser(in: self.syncMOC)
        selfUser.teamIdentifier = team.remoteIdentifier
        uiMOC.saveOrRollback()
        
        syncMOC.performGroupedBlockAndWait {
            FeatureFlag.insert(with: .digitalSignature,
                               value: false,
                               team: self.team,
                               context: self.syncMOC)
        }
    }
    
    override func tearDown() {
        sut = nil
        mockSyncStatus = nil
        mockApplicationStatus = nil
        mockSyncStateDelegate = nil
        selfUser = nil
        team = nil
        super.tearDown()
    }
    
    // MARK: - Slow Sync
    
    func testThatItRequestsFeatureFlags_DuringSlowSync() {
        syncMOC.performGroupedBlockAndWait {
            // GIVEN
            self.mockSyncStatus.mockPhase = .fetchingFeatureFlags
            
            // WHEN
            guard
                let teamId = self.selfUser.teamIdentifier?.uuidString,
                let request = self.sut.nextRequest()
            else {
                return XCTFail()
            }
            
            // THEN
            XCTAssertEqual(request.path, "/teams/\(teamId)/features/digital-signatures")
        }
    }
    
    func testThatItFinishSlowSyncPhase_WhenFeatureFlagsExist() {
        syncMOC.performGroupedBlockAndWait {
            // GIVEN
            self.mockSyncStatus.mockPhase = .fetchingFeatureFlags
            
            guard
                let teamId = self.selfUser.teamIdentifier?.uuidString,
                let request = self.sut.nextRequest()
            else {
                return XCTFail()
            }
            
            // WHEN
            let encoder = JSONEncoder()
            let data = try! encoder.encode(SignatureFeatureFlagResponse(status: false))
            let urlResponse = HTTPURLResponse(url: URL(string: "/teams/\(teamId)/features/digital-signatures")!,
                                              statusCode: 200,
                                              httpVersion: nil,
                                              headerFields: nil)!
            let response = ZMTransportResponse(httpurlResponse: urlResponse,
                                               data: data,
                                               error: nil)
            request.complete(with: response)
        }
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
            
        // THEN
        syncMOC.performGroupedBlockAndWait {
            XCTAssertTrue(self.mockSyncStatus.didCallFinishCurrentSyncPhase)
        }
    }
    
    func testThatItFinishSlowSyncPhase_WhenFeatureFlagsDontExist() {
        syncMOC.performGroupedBlockAndWait {
            // GIVEN
            self.mockSyncStatus.mockPhase = .fetchingFeatureFlags
            guard let request = self.sut.nextRequest() else {
                return XCTFail()
            }
            
            // WHEN
            request.complete(with: ZMTransportResponse(payload: nil,
                                                       httpStatus: 404,
                                                       transportSessionError: nil))
        }
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // THEN
        syncMOC.performGroupedBlockAndWait {
            XCTAssertTrue(self.mockSyncStatus.didCallFinishCurrentSyncPhase)
        }
    }
    
    func testThatItItUpdatesSignatureFeatureFlag() {
        let updatedValue = true
        
        syncMOC.performGroupedBlockAndWait {
            // GIVEN
            let featureFlag = FeatureFlag.updateOrCreate(with: .digitalSignature,
                                                         value: updatedValue,
                                                         team: self.team,
                                                         context: self.syncMOC)
            featureFlag.isEnabled = updatedValue
            self.syncMOC.saveOrRollback()
        }
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // THEN
        syncMOC.performGroupedBlockAndWait {
            let featureFlag = FeatureFlag.fetch(with: .digitalSignature,
                                          team: self.team,
                                          context: self.syncMOC)
            XCTAssertEqual(featureFlag?.isEnabled, updatedValue)
        }
    }
}
