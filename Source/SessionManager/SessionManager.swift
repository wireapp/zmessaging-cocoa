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
    
    func session(withDelegate delegate: UnauthenticatedSessionDelegate) -> UnauthenticatedSession {
        let transportSession = UnauthenticatedTransportSession(baseURL: environment.backendURL)
        return UnauthenticatedSession(transportSession: transportSession, delegate: delegate)
    }

}

open class AuthenticatedSessionFactory {
    
    let storeProvider: LocalStoreProviderProtocol
    let appVersion: String
    let mediaManager: AVSMediaManager
    var analytics: AnalyticsType?
    var apnsEnvironment : ZMAPNSEnvironment?
    let application : ZMApplication
    let environment: ZMBackendEnvironment
    
    public init(storeProvider: LocalStoreProviderProtocol,
                appVersion: String,
                apnsEnvironment: ZMAPNSEnvironment? = nil,
                application: ZMApplication,
                mediaManager: AVSMediaManager,
                analytics: AnalyticsType? = nil) {
        self.storeProvider = storeProvider
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
            storeProvider: storeProvider
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

    public let appVersion: String
    public let storeProvider: LocalStoreProviderProtocol
    public weak var delegate: SessionManagerDelegate? = nil
    
    fileprivate let authenticatedSessionFactory: AuthenticatedSessionFactory
    fileprivate let unauthenticatedSessionFactory: UnauthenticatedSessionFactory
    fileprivate let accountManager: AccountManager
    
    let application: ZMApplication
    var userSession: ZMUserSession?
    var unauthenticatedSession: UnauthenticatedSession?
    var authenticationToken: ZMAuthenticationObserverToken?
    
    public convenience init(
        appVersion: String,
        mediaManager: AVSMediaManager,
        analytics: AnalyticsType?,
        delegate: SessionManagerDelegate?,
        application: ZMApplication,
        launchOptions: LaunchOptions
        ) {

        let localStoreProvider = LocalStoreProvider()
        let unauthenticatedSessionFactory = UnauthenticatedSessionFactory()
        let authenticatedSessionFactory = AuthenticatedSessionFactory(
            storeProvider: localStoreProvider,
            appVersion: appVersion,
            apnsEnvironment: nil, // TODO
            application: application,
            mediaManager: mediaManager,
            analytics: analytics
          )

        self.init(storeProvider: localStoreProvider,
                  appVersion: appVersion,
                  authenticatedSessionFactory: authenticatedSessionFactory,
                  unauthenticatedSessionFactory: unauthenticatedSessionFactory,
                  delegate: delegate,
                  application: application,
                  launchOptions: launchOptions)
    }
    
    public init(
        storeProvider: LocalStoreProviderProtocol,
        appVersion: String,
        authenticatedSessionFactory: AuthenticatedSessionFactory,
        unauthenticatedSessionFactory: UnauthenticatedSessionFactory,
        delegate: SessionManagerDelegate?,
        application: ZMApplication,
        launchOptions: LaunchOptions
        ) {

        SessionManager.enableLogsByEnvironmentVariable()

        self.storeProvider = storeProvider
        self.appVersion = appVersion
        self.application = application
        self.delegate = delegate

        guard let sharedContainerURL = storeProvider.sharedContainerDirectory else { preconditionFailure("Unable to get shared container URL") }
        accountManager = AccountManager(sharedDirectory: sharedContainerURL)

        self.authenticatedSessionFactory = authenticatedSessionFactory
        self.unauthenticatedSessionFactory = unauthenticatedSessionFactory
        
        super.init()
        authenticationToken = ZMUserSessionAuthenticationNotification.addObserver(self)
        
        select(account: accountManager.selectedAccount) { [weak self] session in
            guard let `self` = self else { return }
            session.application(self.application, didFinishLaunchingWithOptions: launchOptions)
            (launchOptions[.url] as? URL).apply(session.didLaunch)
        }
    }

    fileprivate func select(account: Account?, completion: @escaping (ZMUserSession) -> Void) {
        if let account = account, storeProvider.storeExists { // TODO: Add check if store exists for passed account
            if storeProvider.needsToPrepareLocalStore {
                delegate?.sessionManagerWillStartMigratingLocalStore()
                storeProvider.prepareLocalStore {
                    DispatchQueue.main.async { [weak self] in
                        self?.createSession(for: account, completion: completion)
                    }
                }
            } else {
                createSession(for: account, completion: completion)
            }
        } else {
            createUnauthenticatedSession()
        }
    }

    private func createSession(for account: Account, completion: (ZMUserSession) -> Void) {
        guard let session = authenticatedSessionFactory.session(for: account) else { preconditionFailure("Unable to create session for \(account)") }
        self.userSession = session
        delegate?.sessionManagerCreated(userSession: session)
        completion(session)
    }

    fileprivate func createUnauthenticatedSession() {
        let unauthenticatedSession = unauthenticatedSessionFactory.session(withDelegate: self)
        self.unauthenticatedSession = unauthenticatedSession
        delegate?.sessionManagerCreated(unauthenticatedSession: unauthenticatedSession)
    }

    deinit {
        userSession?.tearDown()
        unauthenticatedSession?.tearDown()
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

        select(account: accountManager.selectedAccount) { [weak self] userSession in
            userSession.setEmailCredentials(session.authenticationStatus.emailCredentials())
            userSession.syncManagedObjectContext.performGroupedBlock {
                userSession.syncManagedObjectContext.registeredOnThisDevice = session.authenticationStatus.completedRegistration
            }
            
            if let profileImageData = session.authenticationStatus.profileImageData {
                self?.updateProfileImage(imageData: profileImageData)
            }
        }
    }

}

// MARK: - ZMAuthenticationObserver

extension SessionManager: ZMAuthenticationObserver {

    @objc public func authenticationDidFail(_ error: Error) {
        guard self.unauthenticatedSession == nil else { return }

        // Dispose the user session if it is there
        userSession?.tearDown()
        userSession = nil

        createUnauthenticatedSession()
    }

    @objc public func authenticationDidSucceed() {
        // no-op for now
    }

}
