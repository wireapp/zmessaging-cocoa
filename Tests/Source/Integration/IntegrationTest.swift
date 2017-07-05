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
import WireTesting

@testable import WireSyncEngine

extension IntegrationTest {
    
    @objc
    func _setUp() {
        resetKeychain()
        
        NSManagedObjectContext.setUseInMemoryStore(useInMemoryStore)
        
        application = ApplicationMock()
        mockTransportSession = MockTransportSession(dispatchGroup: self.dispatchGroup)
        WireCallCenterV3Factory.wireCallCenterClass = WireCallCenterV3IntegrationMock.self;
        ZMCallFlowRequestStrategyInternalFlowManagerOverride = MockFlowManager()
        
        createSessionManager()
    }
    
    @objc
    func _tearDown() {
        ZMCallFlowRequestStrategyInternalFlowManagerOverride = nil
        userSession = nil
        unauthenticatedSession = nil
        mockTransportSession?.tearDown()
        mockTransportSession = nil
        sessionManager = nil
    }
    
    func resetKeychain() {
        ZMPersistentCookieStorage.setDoNotPersistToKeychain(!useRealKeychain)
        let cookieStorage = ZMPersistentCookieStorage()
        cookieStorage.deleteUserKeychainItems()
    }
    
    func createSessionManager() {
        
        guard let bundleIdentifier = Bundle.init(for: type(of: self)).bundleIdentifier,
              let mediaManager = mediaManager,
              let application = application,
              let transportSession = transportSession
        else { XCTFail(); return }
        
        let groupIdentifier = "group.\(bundleIdentifier)"
        
        sessionManager = SessionManager(appGroupIdentifier: groupIdentifier,
                                        appVersion: "0.0.0",
                                        transportSession: transportSession,
                                        apnsEnvironment: apnsEnvironment,
                                        mediaManager: mediaManager,
                                        analytics: nil,
                                        delegate: self,
                                        application: application,
                                        launchOptions: [:])
    }
    
}

extension IntegrationTest : SessionManagerDelegate {
    
    public func sessionManagerCreated(userSession: ZMUserSession) {
        self.userSession = userSession
        
        userSession.syncManagedObjectContext.performGroupedBlockAndWait {
            userSession.syncManagedObjectContext.setPersistentStoreMetadata(NSNumber(value: true), key: ZMSkipHotfix)
            userSession.syncManagedObjectContext.add(self.dispatchGroup)
        }
        
        userSession.managedObjectContext.performGroupedBlockAndWait {
            userSession.managedObjectContext.add(self.dispatchGroup)
        }
        
        userSession.managedObjectContext.performGroupedBlock {
            userSession.start()
        }
    }
    
    public func sessionManagerCreated(unauthenticatedSession: UnauthenticatedSession) {
        self.unauthenticatedSession = unauthenticatedSession
    }
    
    public func sessionManagerWillStartMigratingLocalStore() {
        
    }
    
}
