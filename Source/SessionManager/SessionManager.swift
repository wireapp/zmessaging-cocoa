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

extension Account {
    func cookieStorage() -> ZMPersistentCookieStorage {
        let backendURL = ZMBackendEnvironment(userDefaults: .standard).backendURL.host!
        return ZMPersistentCookieStorage(forServerName: backendURL, userIdentifier: userIdentifier)
    }
}

open class AuthenticatedSessionFactory {

    let appVersion: String
    let mediaManager: AVSMediaManager
    var analytics: AnalyticsType?
    var apnsEnvironment : ZMAPNSEnvironment?
    let application : ZMApplication
    let environment: ZMBackendEnvironment

    public init(
        appVersion: String,
        apnsEnvironment: ZMAPNSEnvironment? = nil,
        application: ZMApplication,
        mediaManager: AVSMediaManager,
        analytics: AnalyticsType? = nil
        ) {
        self.appVersion = appVersion
        self.mediaManager = mediaManager
        self.analytics = analytics
        self.apnsEnvironment = apnsEnvironment
        self.application = application
        ZMBackendEnvironment.setupEnvironments()
        self.environment = ZMBackendEnvironment(userDefaults: .standard)
    }
    
    func session(for account: Account, storeProvider: LocalStoreProviderProtocol) -> ZMUserSession? {
        let transportSession = ZMTransportSession(
            baseURL: environment.backendURL,
            websocketURL: environment.backendWSURL,
            cookieStorage: account.cookieStorage(),
            initialAccessToken: nil,
            sharedContainerIdentifier: nil
        )
        
        return ZMUserSession(
            mediaManager: mediaManager,
            analytics: analytics,
            transportSession: transportSession,
            apnsEnvironment: apnsEnvironment,
            application: application,
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
    public weak var delegate: SessionManagerDelegate? = nil

    let application: ZMApplication
    var userSession: ZMUserSession?
    var unauthenticatedSession: UnauthenticatedSession?
    var authenticationToken: ZMAuthenticationObserverToken?
    
    fileprivate let authenticatedSessionFactory: AuthenticatedSessionFactory
    fileprivate let unauthenticatedSessionFactory: UnauthenticatedSessionFactory
    fileprivate let accountManager: AccountManager
    fileprivate let sharedContainerURL: URL
    fileprivate let dispatchGroup: ZMSDispatchGroup?

    public convenience init(
        appVersion: String,
        mediaManager: AVSMediaManager,
        analytics: AnalyticsType?,
        delegate: SessionManagerDelegate?,
        application: ZMApplication,
        launchOptions: LaunchOptions
        ) {

        let unauthenticatedSessionFactory = UnauthenticatedSessionFactory()
        let authenticatedSessionFactory = AuthenticatedSessionFactory(
            appVersion: appVersion,
            apnsEnvironment: nil, // TODO
            application: application,
            mediaManager: mediaManager,
            analytics: analytics
          )

        self.init(
            appVersion: appVersion,
            authenticatedSessionFactory: authenticatedSessionFactory,
            unauthenticatedSessionFactory: unauthenticatedSessionFactory,
            delegate: delegate,
            application: application,
            launchOptions: launchOptions
        )
    }

    public init(
        appVersion: String,
        authenticatedSessionFactory: AuthenticatedSessionFactory,
        unauthenticatedSessionFactory: UnauthenticatedSessionFactory,
        delegate: SessionManagerDelegate?,
        application: ZMApplication,
        launchOptions: LaunchOptions,
        dispatchGroup: ZMSDispatchGroup? = nil
        ) {

        SessionManager.enableLogsByEnvironmentVariable()
        self.appVersion = appVersion
        self.application = application
        self.delegate = delegate
        self.dispatchGroup = dispatchGroup

        guard let sharedContainerURL = Bundle.main.appGroupIdentifier.map(FileManager.sharedContainerDirectory) else {
            preconditionFailure("Unable to get shared container URL")
        }

        self.sharedContainerURL = sharedContainerURL
        self.accountManager = AccountManager(sharedDirectory: sharedContainerURL)
        self.authenticatedSessionFactory = authenticatedSessionFactory
        self.unauthenticatedSessionFactory = unauthenticatedSessionFactory
        
        super.init()
        authenticationToken = ZMUserSessionAuthenticationNotification.addObserver(self)

        if let account = accountManager.selectedAccount {
            selectInitialAccount(account, launchOptions: launchOptions)
        } else {
            // We do not have an account, this means we are either dealing with a fresh install,
            // or an update from a previous version and need to store the initial Account.
            // In order to do so we open the old database and get the userId.
            LocalStoreProvider.openOldDatabaseRetrievingSelfUser(
                in: sharedContainerURL,
                dispatchGroup: dispatchGroup,
                migration: { [weak self] in self?.delegate?.sessionManagerWillStartMigratingLocalStore() },
                completion: { [weak self] user in
                    guard let `self` = self else { return }
                    if let user = user {
                        let account = Account(userName: user.name ?? "", userIdentifier: user.remoteIdentifier!, teamName: user.team?.name)
                        self.accountManager.addAndSelect(account)
                        let migrator = ZMPersistentCookieStorageMigrator(userIdentifier: user.remoteIdentifier!, serverName: authenticatedSessionFactory.environment.backendURL.host!)
                        _ = migrator.createStoreMigratingLegacyStoreIfNeeded()
                    }

                    self.selectInitialAccount(self.accountManager.selectedAccount, launchOptions: launchOptions)
            })
        }
    }

    private func selectInitialAccount(_ account: Account?, launchOptions: LaunchOptions) {
        select(account: account) { [weak self] session in
            guard let `self` = self else { return }
            session.application(self.application, didFinishLaunchingWithOptions: launchOptions)
            (launchOptions[.url] as? URL).apply(session.didLaunch)
        }
    }

    fileprivate func select(account: Account?, completion: @escaping (ZMUserSession) -> Void) {
        guard let account = account else { return createUnauthenticatedSession() }
        let storeProvider = LocalStoreProvider(sharedContainerDirectory: sharedContainerURL, userIdentifier: account.userIdentifier, dispatchGroup: dispatchGroup)

        if nil != account.cookieStorage().authenticationCookieData {
            storeProvider.createStorageStack(
                migration: { [weak self] in self?.delegate?.sessionManagerWillStartMigratingLocalStore() },
                completion: { [weak self] provider in self?.createSession(for: account, with: provider, completion: completion) }
            )
        } else {
            createUnauthenticatedSession()
        }
    }

    fileprivate func createSession(for account: Account, with provider: LocalStoreProviderProtocol, completion: (ZMUserSession) -> Void) {
        guard let session = authenticatedSessionFactory.session(for: account, storeProvider: provider) else {
            preconditionFailure("Unable to create session for \(account)")
        }

        self.userSession = session
        let authenticationStatus = unauthenticatedSession?.authenticationStatus

        session.syncManagedObjectContext.performGroupedBlock {
            session.setEmailCredentials(authenticationStatus?.emailCredentials())
            if let registered = authenticationStatus?.completedRegistration {
                session.syncManagedObjectContext.registeredOnThisDevice = registered
            }
        }

        delegate?.sessionManagerCreated(userSession: session)
        completion(session)
    }

    fileprivate func createUnauthenticatedSession() {
        self.unauthenticatedSession?.tearDown()
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
        accountManager.addAndSelect(account)

        let provider = LocalStoreProvider(sharedContainerDirectory: sharedContainerURL, userIdentifier: account.userIdentifier, dispatchGroup: dispatchGroup)

        provider.createStorageStack(migration: nil) { [weak self] provider in
            self?.createSession(for: account, with: provider) { userSession in
                if let profileImageData = session.authenticationStatus.profileImageData {
                    self?.updateProfileImage(imageData: profileImageData)
                }
            }
        }
    }

}

// MARK: - ZMAuthenticationObserver

extension SessionManager: ZMAuthenticationObserver {

    @objc public func authenticationDidFail(_ error: Error) {
        // no-op
    }

    @objc public func authenticationDidSucceed() {
        if nil != userSession {
            return RequestAvailableNotification.notifyNewRequestsAvailable(self)
        }
    }

}
