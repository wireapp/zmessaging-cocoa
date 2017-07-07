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
    
    static let SelfUserEmail = "myself@user.example.com"
    static let SelfUserPassword = "fgf0934';$@#%"
    
    @objc
    func _setUp() {
        ZMPersistentCookieStorage.setDoNotPersistToKeychain(!useRealKeychain)
        
        NSManagedObjectContext.setUseInMemoryStore(useInMemoryStore)
        
        application = ApplicationMock()
        mockTransportSession = MockTransportSession(dispatchGroup: self.dispatchGroup)
        WireCallCenterV3Factory.wireCallCenterClass = WireCallCenterV3IntegrationMock.self;
        ZMCallFlowRequestStrategyInternalFlowManagerOverride = MockFlowManager()
        mockTransportSession?.cookieStorage.deleteUserKeychainItems()
                
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
        selfUser = nil
        selfConversation = nil
        
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        resetInMemoryDatabases()
    }
    
    func resetInMemoryDatabases() {
        NSManagedObjectContext.resetUserInterfaceContext()
        NSManagedObjectContext.resetSharedPersistentStoreCoordinator()
    }
    
    @objc
    func recreateSessionManager() {
        userSession = nil
        unauthenticatedSession = nil
        sessionManager = nil
        
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        createSessionManager()
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
    
    @objc
    func createDefaultUsersAndConversations() {
        
        mockTransportSession?.performRemoteChanges({ session in
            let selfUser = session.insertSelfUser(withName: "The Self User")
            selfUser.email = IntegrationTest.SelfUserEmail
            selfUser.password = IntegrationTest.SelfUserPassword
            selfUser.phone = ""
            selfUser.accentID = 2
            session.addProfilePicture(to: selfUser)
            session.addV3ProfilePicture(to: selfUser)
            
            let selfConversation = session.insertSelfConversation(withSelfUser: selfUser)
            selfConversation.identifier = selfUser.identifier
            
            self.selfUser = selfUser
            self.selfConversation = selfConversation
        })
        
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
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
        
        unauthenticatedSession.moc.performGroupedBlockAndWait {
            unauthenticatedSession.moc.add(self.dispatchGroup)
        }
    }
    
    public func sessionManagerWillStartMigratingLocalStore() {
        
    }
    
}
