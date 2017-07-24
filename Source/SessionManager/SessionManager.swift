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
import avs
import WireTransport
import WireUtilities

private let log = ZMSLog(tag: "SessionManager")

open class UnauthenticatedSessionFactory {
    
    let environment: ZMBackendEnvironment
    
    init() {
        self.environment = ZMBackendEnvironment(userDefaults: .standard)
    }
    
    func session(withDelegate delegate: UnauthenticatedSessionDelegate) throws -> UnauthenticatedSession {
        return try UnauthenticatedSession(backendURL: environment.backendURL, delegate: delegate)
    }

}

open class AuthenticatedSessionFactory {
    
    let appGroupIdentifier: String
    let appVersion: String
    let mediaManager: AVSMediaManager
    var analytics: AnalyticsType?
    var apnsEnvironment : ZMAPNSEnvironment?
    let application : ZMApplication
    let environment: ZMBackendEnvironment
    
    public init(appGroupIdentifier: String,
                appVersion: String,
                apnsEnvironment: ZMAPNSEnvironment? = nil,
                application: ZMApplication,
                mediaManager: AVSMediaManager,
                analytics: AnalyticsType? = nil) {
        self.appGroupIdentifier = appGroupIdentifier
        self.appVersion = appVersion
        self.mediaManager = mediaManager
        self.analytics = analytics
        self.apnsEnvironment = apnsEnvironment
        self.application = application
        self.environment = ZMBackendEnvironment(userDefaults: .standard)
    }
    
    func session(for account: Account) -> ZMUserSession? {
        let transportSession = ZMTransportSession(
            baseURL: environment.backendURL,
            websocketURL: environment.backendWSURL,
            cookieStorage: .init(forServerName: environment.backendURL.host!, userIdentifier: account.userIdentifier),
            initialAccessToken: nil,
            sharedContainerIdentifier: nil
        )
        
        return ZMUserSession(
            mediaManager: mediaManager,
            analytics: analytics,
            transportSession: transportSession,
            apnsEnvironment: apnsEnvironment,
            application: application,
            userId: nil,
            appVersion: appVersion,
            appGroupIdentifier: appGroupIdentifier
        )
    }
    
}

@objc
public protocol SessionManagerDelegate : class {
    
    func sessionManagerCreated(unauthenticatedSession : UnauthenticatedSession)
    func sessionManagerCreated(userSession : ZMUserSession)
    func sessionManagerWillStartMigratingLocalStore()
}

@objc
public class SessionManager : NSObject {

    public typealias LaunchOptions = [UIApplicationLaunchOptionsKey : Any]
    
    public let appGroupIdentifier: String
    public let appVersion: String
    fileprivate let authenticatedSessionFactory : AuthenticatedSessionFactory
    fileprivate let unauthenticatedSessionFactory : UnauthenticatedSessionFactory
    
    let application : ZMApplication
    public weak var delegate : SessionManagerDelegate? = nil
    var userSession: ZMUserSession?
    var unauthenticatedSession: UnauthenticatedSession?
    fileprivate let accountManager: AccountManager
    
    public convenience init(appGroupIdentifier: String,
                appVersion: String,
                apnsEnvironment: ZMAPNSEnvironment? = nil,
                mediaManager: AVSMediaManager,
                analytics: AnalyticsType?,
                delegate: SessionManagerDelegate?,
                application: ZMApplication,
                launchOptions: LaunchOptions) {
        
        let authenticatedSessionFactory = AuthenticatedSessionFactory(
            appGroupIdentifier: appGroupIdentifier,
            appVersion: appVersion,
            apnsEnvironment: apnsEnvironment,
            application: application,
            mediaManager: mediaManager,
            analytics: analytics)
        
        let unauthenticatedSessionFactory = UnauthenticatedSessionFactory()
        
        self.init(appGroupIdentifier: appGroupIdentifier,
                  appVersion: appVersion,
                  application: application,
                  authenticatedSessionFactory: authenticatedSessionFactory,
                  unauthenticatedSessionFactory: unauthenticatedSessionFactory,
                  delegate: delegate,
                  launchOptions: launchOptions)
    }
    
    init(appGroupIdentifier: String,
         appVersion: String,
         application: ZMApplication,
         authenticatedSessionFactory : AuthenticatedSessionFactory,
         unauthenticatedSessionFactory : UnauthenticatedSessionFactory,
         delegate: SessionManagerDelegate?,
         launchOptions: LaunchOptions) {
        
        SessionManager.enableLogsByEnvironmentVariable()
        ZMBackendEnvironment.setupEnvironments()
        
        self.appGroupIdentifier = appGroupIdentifier
        self.appVersion = appVersion
        self.application = application
        self.delegate = delegate

        let sharedContainerURL = SessionManager.sharedContainerURL(with: appGroupIdentifier)!
        accountManager = AccountManager(sharedDirectory: sharedContainerURL)

        self.authenticatedSessionFactory = authenticatedSessionFactory
        self.unauthenticatedSessionFactory = unauthenticatedSessionFactory
        
        super.init()
        
        select(account: accountManager.selectedAccount) { session in
            session.application(self.application, didFinishLaunchingWithOptions: launchOptions)
            if let url = launchOptions[.url] as? URL {
                session.didLaunch(with: url)
            }
        }
    }

    fileprivate func select(account: Account?, completion: @escaping (ZMUserSession) -> Void) {
        if let account = account { // TODO: Add check if store exists?
            let createSession = { [weak self] in
                guard let `self` = self else { return }
                guard let session = self.authenticatedSessionFactory.session(for: account) else { preconditionFailure("Unable to create session for \(account)") }
                self.userSession = session
                completion(session)
                self.delegate?.sessionManagerCreated(userSession: session)
            }

            if ZMUserSession.needsToPrepareLocalStore(usingAppGroupIdentifier: appGroupIdentifier) {
                delegate?.sessionManagerWillStartMigratingLocalStore()
                ZMUserSession.prepareLocalStore(usingAppGroupIdentifier: appGroupIdentifier) {
                    DispatchQueue.main.async(execute: createSession)
                }
            } else {
                createSession()
            }
        } else {
            createUnauthenticatedSession()
        }
    }

    fileprivate func createUnauthenticatedSession() {
        do {
            let unauthenticatedSession = try unauthenticatedSessionFactory.session(withDelegate: self)
            self.unauthenticatedSession = unauthenticatedSession
            delegate?.sessionManagerCreated(unauthenticatedSession: unauthenticatedSession)
        } catch {
            fatal("Can't create unauthenticated session: \(error)")
        }
    }

    deinit {
        userSession?.tearDown()
    }
    
    @objc public var currentUser: ZMUser? {
        guard let userSession = userSession else { return nil }
        return ZMUser.selfUser(in: userSession.managedObjectContext)
    }
    
    @objc public var isUserSessionActive: Bool {
        return userSession != nil
    }

    func updateProfileImage(imageData: Data) {
        userSession?.enqueueChanges {
            self.userSession?.profileUpdate.updateImage(imageData: imageData)
        }
    }

    static private func sharedContainerURL(with appGroupIdentifier: String) -> URL? {
        if let sharedContainerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            return sharedContainerURL
        } else {
            // Seems like the shared container is not available. This can happen for multiple reasons:
            // 1. The app is compiled with an incorrect provisioning profile (for example by a 3rd party)
            // 2. The app is running on simulator and there is no correct provisioning profile on the system
            // 3. There is another issue with code signing
            //
            // The app should allow not having a shared container in the first 2 cases, in the 3rd case the app should crash
            let environment = ZMDeploymentEnvironment().environmentType()
            if TARGET_IPHONE_SIMULATOR == 0 && (environment == .appStore || environment == .internal) {
                fatal("Unable to create shared container url using app group identifier: \(appGroupIdentifier)")
            } else {
                log.error("Unable to create shared containerwith deployment environment: \(environment.rawValue)")
                log.error("Wire is going to use the APPLICATION SUPPORT directory to store user data")
                return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            }
        }
    }

}

// MARK: - UnauthenticatedSessionDelegate

extension SessionManager: UnauthenticatedSessionDelegate {
    func session(session: UnauthenticatedSession, updatedCredentials credentials: ZMCredentials) {
        if let userSession = userSession, let emailCredentials = credentials as? ZMEmailCredentials {
            userSession.setEmailCredentials(emailCredentials)
        }
    }
    
    func session(session: UnauthenticatedSession, updatedProfileImage imageData: Data) {
        updateProfileImage(imageData: imageData)
    }
    
    func session(session: UnauthenticatedSession, createdAccount account: Account) {
        accountManager.add(account)
        accountManager.select(account)
        select(account: accountManager.selectedAccount) { userSession in
            userSession.setEmailCredentials(session.authenticationStatus.emailCredentials())
            
            userSession.syncManagedObjectContext.performGroupedBlock {
                userSession.syncManagedObjectContext.registeredOnThisDevice = session.authenticationStatus.completedRegistration
            }
            
            if let profileImageData = session.authenticationStatus.profileImageData {
                self.updateProfileImage(imageData: profileImageData)
            }
        }
    }
}
