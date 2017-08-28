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
public typealias LaunchOptions = [UIApplicationLaunchOptionsKey : Any]


@objc public protocol SessionManagerDelegate : class {
    func sessionManagerCreated(unauthenticatedSession : UnauthenticatedSession)
    func sessionManagerCreated(userSession : ZMUserSession)
    func sessionManagerDidLogout()
    func sessionManagerWillSuspendSession()
    func sessionManagerWillStartMigratingLocalStore()
    func sessionManagerDidBlacklistCurrentVersion()
}



/// The `SessionManager` class handles the creation of `ZMUserSession` and `UnauthenticatedSession`
/// objects, the handover between them as well as account switching.
///
/// There are multiple things neccessary in order to store (and switch between) multiple accounts on one device, a couple of them are:
/// 1. The folder structure in the app sandbox has to be modeled in a way in which files can be associated with a single account.
/// 2. The login flow should not rely on any persistent state (e.g. no database has to be created on disk before being logged in).
/// 3. There has to be a persistence layer storing information about accounts and the currently selected / active account.
/// 
/// The wire account database and a couple of other related files are stored in the shared container in a folder named by the accounts
/// `remoteIdentifier`. All information about different accounts on a device are stored by the `AccountManager` (see the documentation
/// of that class for more information). The `SessionManager`s main responsibility at the moment is checking whether there is a selected 
/// `Account` or not, and creating an `UnauthenticatedSession` or `ZMUserSession` accordingly. An `UnauthenticatedSession` is used
/// to create requests to either log in existing users or to register new users. It uses its own `UnauthenticatedOperationLoop`, 
/// which is a stripped down version of the regular `ZMOperationLoop`. This unauthenticated operation loop only uses a small subset
/// of transcoders needed to perform the login / registration (and related phone number verification) requests. For more information
/// see `UnauthenticatedOperationLoop`.
///
/// The result of using an `UnauthenticatedSession` is retrieving a remoteIdentifier of a logged in user, as well as a valid cookie.
/// Once those became available, the session will notify the session manager, which in turn will create a regular `ZMUserSession`.
/// For more information about the cookie retrieval consult the documentation in `UnauthenticatedSession`.
///
/// The flow creating either an `UnauthenticatedSession` or `ZMUserSession` after creating an instance of `SessionManager` 
/// is depicted on a high level in the following diagram:
///
///
/// +-----------------------------------------+
/// |         `SessionManager.init`           |
/// +-----------------------------------------+
///
///                    +
///                    |
///                    |
///                    v
///
/// +-----------------------------------------+        YES           Load the selected Account and its
/// | Is there a stored and selected Account? |   +------------->    cookie from disk.
/// +-----------------------------------------+                      Create a `ZMUserSession` using the cookie.
///
///                    +
///                    |
///                    | NO
///                    |
///                    v
///
/// +------------------+---------------------+
/// | Check if there is a database present   |        YES           Open the existing database, retrieve the user identifier,
/// | in the legacy directory (not keyed by  |  +-------------->    create an account with it and select it. Migrate the existing
/// | the users remoteIdentifier)?           |                      cookie for that account and start at the top again.
/// +----------------------------------------+
///
///                    +
///                    |
///                    | NO
///                    |
///                    v
///
/// +------------------+---------------------+
/// | Create a `UnauthenticatedSession` to   |
/// | start the registration or login flow.  |
/// +----------------------------------------+
///


@objc public class SessionManager : NSObject {

    public let appVersion: String
    var isAppVersionBlacklisted = false
    public weak var delegate: SessionManagerDelegate? = nil
    public let accountManager: AccountManager
    public fileprivate(set) var userSession: ZMUserSession?
    public fileprivate(set) var unauthenticatedSession: UnauthenticatedSession?

    let application: ZMApplication
    var authenticationToken: ZMAuthenticationObserverToken?
    var blacklistVerificator: ZMBlacklistVerificator?
    let reachability: ReachabilityProvider & ReachabilityTearDown

    fileprivate let authenticatedSessionFactory: AuthenticatedSessionFactory
    fileprivate let unauthenticatedSessionFactory: UnauthenticatedSessionFactory
    fileprivate let sharedContainerURL: URL
    fileprivate let dispatchGroup: ZMSDispatchGroup?

    public convenience init(
        appVersion: String,
        mediaManager: AVSMediaManager,
        analytics: AnalyticsType?,
        delegate: SessionManagerDelegate?,
        application: ZMApplication,
        launchOptions: LaunchOptions,
        blacklistDownloadInterval : TimeInterval
        ) {
        
        ZMBackendEnvironment.setupEnvironments()
        let environment = ZMBackendEnvironment(userDefaults: .standard)
        let group = ZMSDispatchGroup(dispatchGroup: DispatchGroup(), label: "Session manager reachability")!
        let flowManager = FlowManager(mediaManager: mediaManager)

        let serverNames = [environment.backendURL, environment.backendWSURL].flatMap{ $0.host }
        let reachability = ZMReachability(serverNames: serverNames, observer: nil, queue: .main, group: group)
        let unauthenticatedSessionFactory = UnauthenticatedSessionFactory(environment: environment, reachability: reachability)
        let authenticatedSessionFactory = AuthenticatedSessionFactory(
            appVersion: appVersion,
            apnsEnvironment: nil,
            application: application,
            mediaManager: mediaManager,
            flowManager: flowManager,
            environment: environment,
            reachability: reachability,
            analytics: analytics
          )

        self.init(
            appVersion: appVersion,
            authenticatedSessionFactory: authenticatedSessionFactory,
            unauthenticatedSessionFactory: unauthenticatedSessionFactory,
            reachability: reachability,
            delegate: delegate,
            application: application,
            launchOptions: launchOptions
        )
        self.blacklistVerificator = ZMBlacklistVerificator(checkInterval: blacklistDownloadInterval,
                                                           version: appVersion,
                                                           working: nil,
                                                           application: application,
                                                           blacklistCallback:
            { [weak self] (blacklisted) in
                guard let `self` = self, !self.isAppVersionBlacklisted else { return }
                
                if blacklisted {
                    self.isAppVersionBlacklisted = true
                    self.delegate?.sessionManagerDidBlacklistCurrentVersion()
                }
        })
        
    }

    public init(
        appVersion: String,
        authenticatedSessionFactory: AuthenticatedSessionFactory,
        unauthenticatedSessionFactory: UnauthenticatedSessionFactory,
        reachability: ReachabilityProvider & ReachabilityTearDown,
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
        self.reachability = reachability
        super.init()
        authenticationToken = ZMUserSessionAuthenticationNotification.addObserver(self)

        if let account = accountManager.selectedAccount {
            selectInitialAccount(account, launchOptions: launchOptions)
        } else {
            // We do not have an account, this means we are either dealing with a fresh install,
            // or an update from a previous version and need to store the initial Account.
            // In order to do so we open the old database and get the user identifier.
            LocalStoreProvider.fetchUserIDFromLegacyStore(
                in: sharedContainerURL,
                migration: { [weak self] in self?.delegate?.sessionManagerWillStartMigratingLocalStore() },
                completion: { [weak self] identifier in
                    guard let `self` = self else { return }
                    identifier.apply(self.migrateAccount)
                    self.selectInitialAccount(self.accountManager.selectedAccount, launchOptions: launchOptions)
            })
        }
    }

    /// Creates an account with the given identifier and migrates its cookie storage.
    private func migrateAccount(with identifier: UUID) {
        let account = Account(userName: "", userIdentifier: identifier)
        accountManager.addAndSelect(account)
        let migrator = ZMPersistentCookieStorageMigrator(userIdentifier: identifier, serverName: authenticatedSessionFactory.environment.backendURL.host!)
        _ = migrator.createStoreMigratingLegacyStoreIfNeeded()
    }

    private func selectInitialAccount(_ account: Account?, launchOptions: LaunchOptions) {
        select(account: account) { [weak self] session in
            guard let `self` = self else { return }
            session.application(self.application, didFinishLaunchingWithOptions: launchOptions)
            (launchOptions[.url] as? URL).apply(session.didLaunch)
        }
    }
    
    public func select(_ account: Account) {
        delegate?.sessionManagerWillSuspendSession()
        userSession?.closeAndDeleteCookie(false)
        userSession = nil
        
        select(account: account) { [weak self] (_) in
            self?.accountManager.select(account)
        }
    }
    
    public func logoutCurrentSession(deleteCookie: Bool = true) {
        userSession?.closeAndDeleteCookie(deleteCookie)
        userSession = nil
        delegate?.sessionManagerDidLogout()

        createUnauthenticatedSession()
    }

    fileprivate func select(account: Account?, completion: @escaping (ZMUserSession) -> Void) {
        guard let account = account else { return createUnauthenticatedSession() }

        if nil != account.cookieStorage().authenticationCookieData {
            LocalStoreProvider.createStack(
                applicationContainer: sharedContainerURL,
                userIdentifier: account.userIdentifier,
                dispatchGroup: dispatchGroup,
                migration: { [weak self] in self?.delegate?.sessionManagerWillStartMigratingLocalStore() },
                completion: { [weak self] provider in self?.createSession(for: account, with: provider, completion: completion) }
            )
        } else {
            createUnauthenticatedSession()
        }
    }

    fileprivate func createSession(for account: Account, with provider: LocalStoreProviderProtocol, completion: @escaping (ZMUserSession) -> Void) {
        guard let session = authenticatedSessionFactory.session(for: account, storeProvider: provider) else {
            preconditionFailure("Unable to create session for \(account)")
        }

        self.userSession = session
        log.debug("Created ZMUserSession for account \(account.userName) — \(account.userIdentifier)")
        let authenticationStatus = unauthenticatedSession?.authenticationStatus

        session.syncManagedObjectContext.performGroupedBlock {
            session.setEmailCredentials(authenticationStatus?.emailCredentials())
            if let registered = authenticationStatus?.completedRegistration {
                session.syncManagedObjectContext.registeredOnThisDevice = registered
            }

            session.managedObjectContext.performGroupedBlock { [weak self] in
                completion(session)
                self?.delegate?.sessionManagerCreated(userSession: session)
            }
        }
    }

    fileprivate func createUnauthenticatedSession() {
        log.debug("Creating unauthenticated session")
        self.unauthenticatedSession?.tearDown()
        let unauthenticatedSession = unauthenticatedSessionFactory.session(withDelegate: self)
        self.unauthenticatedSession = unauthenticatedSession
        delegate?.sessionManagerCreated(unauthenticatedSession: unauthenticatedSession)
    }

    deinit {
        if let authenticationToken = authenticationToken {
            ZMUserSessionAuthenticationNotification.removeObserver(for: authenticationToken)
        }
        
        blacklistVerificator?.teardown()
        userSession?.tearDown()
        unauthenticatedSession?.tearDown()
        reachability.tearDown()
    }

    @objc public var currentUser: ZMUser? {
        guard let moc = userSession?.managedObjectContext  else { return nil }
        return ZMUser.selfUser(in: moc)
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

    public func session(session: UnauthenticatedSession, updatedCredentials credentials: ZMCredentials) {
        if let userSession = userSession, let emailCredentials = credentials as? ZMEmailCredentials {
            userSession.setEmailCredentials(emailCredentials)
        }
    }
    
    public func session(session: UnauthenticatedSession, updatedProfileImage imageData: Data) {
        updateProfileImage(imageData: imageData)
    }
    
    public func session(session: UnauthenticatedSession, createdAccount account: Account) {
        accountManager.addAndSelect(account)

        dispatchGroup?.enter()
        LocalStoreProvider.createStack(applicationContainer: sharedContainerURL, userIdentifier: account.userIdentifier, dispatchGroup: dispatchGroup) { [weak self] provider in
            self?.createSession(for: account, with: provider) { userSession in
                if let profileImageData = session.authenticationStatus.profileImageData {
                    self?.updateProfileImage(imageData: profileImageData)
                }
                self?.dispatchGroup?.leave()
            }
        }
    }

}

// MARK: - ZMAuthenticationObserver

extension SessionManager: ZMAuthenticationObserver {

    @objc public func clientRegistrationDidSucceed() {
        log.debug("Tearing down unauthenticated session as reaction to successfull client registration")
        unauthenticatedSession?.tearDown()
        unauthenticatedSession = nil
    }

    @objc public func authenticationDidSucceed() {
        if nil != userSession {
            return RequestAvailableNotification.notifyNewRequestsAvailable(self)
        }
    }

}
