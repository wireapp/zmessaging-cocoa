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
    func sessionManagerDidLogout(error : Error?)
    func sessionManagerWillOpenAccount(_ account: Account)
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
    public fileprivate(set) var activeUserSession: ZMUserSession?
    public fileprivate(set) var backgroundUserSessions: [Account: ZMUserSession] = [:]
    public fileprivate(set) var unauthenticatedSession: UnauthenticatedSession?

    let application: ZMApplication
    var authenticationToken: ZMAuthenticationObserverToken?
    var blacklistVerificator: ZMBlacklistVerificator?
    let reachability: ReachabilityProvider & ReachabilityTearDown
    let pushDispatcher = PushDispatcher()
    
    fileprivate let authenticatedSessionFactory: AuthenticatedSessionFactory
    fileprivate let unauthenticatedSessionFactory: UnauthenticatedSessionFactory
    fileprivate let sharedContainerURL: URL
    fileprivate let dispatchGroup: ZMSDispatchGroup?
    fileprivate var teamObserver: NSObjectProtocol?
    fileprivate var selfObserver: NSObjectProtocol?
    fileprivate var conversationListObserver: NSObjectProtocol?
    fileprivate var connectionRequestObserver: NSObjectProtocol?
    fileprivate var memoryWarningObserver: NSObjectProtocol?
    
    private static var token: Any?
    
    /// The entry point for SessionManager; call this instead of the initializers.
    ///
    public static func create(
        appVersion: String,
        mediaManager: AVSMediaManager,
        analytics: AnalyticsType?,
        delegate: SessionManagerDelegate?,
        application: ZMApplication,
        launchOptions: LaunchOptions,
        blacklistDownloadInterval : TimeInterval,
        completion: @escaping (SessionManager) -> Void
        ) {
        
        token = FileManager.default.executeWhenFileSystemIsAccessible {
            completion(SessionManager(
                appVersion: appVersion,
                mediaManager: mediaManager,
                analytics: analytics,
                delegate: delegate,
                application: application,
                launchOptions: launchOptions,
                blacklistDownloadInterval: blacklistDownloadInterval
            ))
            
            token = nil
        }
    }
    
    public override init() {
        fatal("init() not implemented")
    }
    
    private convenience init(
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
     
        self.memoryWarningObserver = NotificationCenter.default.addObserver(forName: NSNotification.Name.UIApplicationDidReceiveMemoryWarning,
                                                                            object: nil,
                                                                            queue: nil,
                                                                            using: {[weak self] _ in
            guard let `self` = self else {
                return
            }
            self.deactivateAllBackgroundSessions()
        })
    }

    init(
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
        self.pushDispatcher.fallbackClient = self
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
            self.updateCurrentAccount(in: session.managedObjectContext)
            session.application(self.application, didFinishLaunchingWithOptions: launchOptions)
            (launchOptions[.url] as? URL).apply(session.didLaunch)
        }
    }
    
    public func select(_ account: Account) {
        delegate?.sessionManagerWillOpenAccount(account)
        tearDownObservers()
        activeUserSession?.closeAndDeleteCookie(false)
        activeUserSession = nil
        
        select(account: account) { [weak self] (_) in
            self?.accountManager.select(account)
        }
    }
    
    public func addAccount() {
        logoutCurrentSession(deleteCookie: false, error: NSError.userSessionErrorWith(.addAccountRequested, userInfo: nil))
    }
    
    public func delete(account: Account) {
        if let secondAccount = accountManager.accounts.first(where: { $0.userIdentifier != account.userIdentifier }) {
            select(secondAccount)
        } else {
            logoutCurrentSession(deleteCookie: true, error: NSError.userSessionErrorWith(.addAccountRequested, userInfo: nil))
        }
        deleteAccountData(for: account)
    }
    
    public func logoutCurrentSession(deleteCookie: Bool = true) {
        logoutCurrentSession(deleteCookie: deleteCookie, error: nil)
    }
    
    fileprivate func logoutCurrentSession(deleteCookie: Bool = true, error : Error?) {
        guard let currentSession = activeUserSession else {
            return
        }
        
        tearDownObservers()
        
        
        let matchingAccountSession = backgroundUserSessions.first { (account, session) in
            session == currentSession
        }
        
        if let matchingAccount = matchingAccountSession?.key {
            backgroundUserSessions[matchingAccount] = nil
        }
        
        currentSession.closeAndDeleteCookie(deleteCookie)
        activeUserSession = nil
        
        delegate?.sessionManagerDidLogout(error: error)
        
        createUnauthenticatedSession()
    }

    fileprivate func select(account: Account?, completion: @escaping (ZMUserSession) -> Void) {
        guard let account = account else { return createUnauthenticatedSession() }

        if account.isAuthenticated {
            LocalStoreProvider.createStack(
                applicationContainer: sharedContainerURL,
                userIdentifier: account.userIdentifier,
                dispatchGroup: dispatchGroup,
                migration: { [weak self] in self?.delegate?.sessionManagerWillStartMigratingLocalStore() },
                completion: { [weak self] provider in
                    self?.createSession(for: account, with: provider) { session in
                        self?.registerSessionForRemoteNotificationsIfNeeded(session)
                        completion(session)
                    }}
            )
        } else {
            createUnauthenticatedSession()
        }
    }

    public func deleteAccountData(for account: Account) {
        account.cookieStorage().deleteKeychainItems()
        
        let accountID = account.userIdentifier
        self.accountManager.remove(account)
        
        do {
            try FileManager.default.removeItem(at: StorageStack.accountFolder(accountIdentifier: accountID, applicationContainer: sharedContainerURL))
        }
        catch let error {
            log.error("Impossible to delete the acccount \(account): \(error)")
        }
    }
    
    fileprivate func createSession(for account: Account, with provider: LocalStoreProviderProtocol, completion: @escaping (ZMUserSession) -> Void) {
        let session: ZMUserSession
        if let backgroundSession = self.backgroundUserSessions[account] {
            session = backgroundSession
        }
        else {
            guard let newSession = authenticatedSessionFactory.session(for: account, storeProvider: provider) else {
                preconditionFailure("Unable to create session for \(account)")
            }
            session = newSession
            self.backgroundUserSessions[account] = newSession
        }
        
        pushDispatcher.add(client: session)
        
        let selfUser = ZMUser.selfUser(inUserSession: session)
        teamObserver = TeamChangeInfo.add(observer: self, for: nil)
        selfObserver = UserChangeInfo.add(observer: self, forBareUser: selfUser!)
        conversationListObserver = ConversationListChangeInfo.add(observer: self, for: ZMConversationList.conversations(inUserSession: session))
        connectionRequestObserver = ConversationListChangeInfo.add(observer: self, for: ZMConversationList.pendingConnectionConversations(inUserSession: session))

        self.activeUserSession = session
        log.debug("Created ZMUserSession for account \(String(describing: account.userName)) — \(account.userIdentifier)")
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
    
    public func withSession(for account: Account, perform action: @escaping (ZMUserSession)->()) {
        if let session = backgroundUserSessions[account] {
            action(session)
        }
        else {
            LocalStoreProvider.createStack(
                applicationContainer: sharedContainerURL,
                userIdentifier: account.userIdentifier,
                dispatchGroup: dispatchGroup,
                migration: { [weak self] in self?.delegate?.sessionManagerWillStartMigratingLocalStore() },
                completion: { provider in
                    self.activateBackgroungSession(for: account, with: provider, completion: action)
                }
            )
        }
    }
    
    fileprivate func activateBackgroungSession(for account: Account, with provider: LocalStoreProviderProtocol, completion: @escaping (ZMUserSession)->()) {
        guard let newSession = authenticatedSessionFactory.session(for: account, storeProvider: provider) else {
            preconditionFailure("Unable to create session for \(account)")
        }
        self.backgroundUserSessions[account] = newSession
        
        pushDispatcher.add(client: newSession)

        log.debug("Created ZMUserSession for account \(String(describing: account.userName)) — \(account.userIdentifier)")
        let authenticationStatus = unauthenticatedSession?.authenticationStatus
        
        newSession.syncManagedObjectContext.performGroupedBlock {
            newSession.setEmailCredentials(authenticationStatus?.emailCredentials())
            if let registered = authenticationStatus?.completedRegistration {
                newSession.syncManagedObjectContext.registeredOnThisDevice = registered
            }
            
            newSession.managedObjectContext.performGroupedBlock { [weak self] in
                completion(newSession)
                self?.delegate?.sessionManagerCreated(userSession: newSession)
            }
        }
    }
    
    internal func deactivateBackgroundSession(for account: Account) {
        guard let userSession = self.backgroundUserSessions[account] else {
            log.error("No session to tear down for \(account), known sessions: \(self.backgroundUserSessions)")
            return
        }
        userSession.closeAndDeleteCookie(false)
        self.tearDownConversationListObservers()
        self.backgroundUserSessions[account] = nil
    }
    
    internal func deactivateAllBackgroundSessions() {
        self.backgroundUserSessions.forEach { (account, session) in
            if self.activeUserSession != session {
                self.deactivateBackgroundSession(for: account)
            }
        }
    }
    
    fileprivate func tearDownObservers() {
        if let teamObserver = teamObserver {
            TeamChangeInfo.remove(observer: teamObserver, for: nil)
        }
        if let userObserver = selfObserver {
            UserChangeInfo.remove(observer: userObserver, forBareUser: nil)
        }
    }
    
    fileprivate func tearDownConversationListObservers() {
        if let conversationListObserver = conversationListObserver {
            ConversationListChangeInfo.remove(observer: conversationListObserver, for: nil)
        }
        if let connectionRequestObserver = connectionRequestObserver {
            ConversationListChangeInfo.remove(observer: connectionRequestObserver, for: nil)
        }
    }

    deinit {
        if let authenticationToken = authenticationToken {
            ZMUserSessionAuthenticationNotification.removeObserver(for: authenticationToken)
        }
        tearDownObservers()
        tearDownConversationListObservers()
        blacklistVerificator?.teardown()
        activeUserSession?.tearDown()
        unauthenticatedSession?.tearDown()
        reachability.tearDown()
    }
    
    @objc public var isUserSessionActive: Bool {
        return activeUserSession != nil
    }

    func updateProfileImage(imageData: Data) {
        activeUserSession?.enqueueChanges {
            self.activeUserSession?.profileUpdate.updateImage(imageData: imageData)
        }
    }

}

// MARK: - TeamObserver

extension SessionManager {
    func updateCurrentAccount(with team: TeamType? = nil, in managedObjectContext: NSManagedObjectContext) {
        let selfUser = ZMUser.selfUser(in: managedObjectContext)
        if let account = accountManager.accounts.first(where: { $0.userIdentifier == selfUser.remoteIdentifier }) {
            if let name = team?.name {
                account.teamName = name
            }
            if let userName = selfUser.name {
                account.userName = userName
            }
            if let userProfileImage = selfUser.imageSmallProfileData, !selfUser.isTeamMember {
                account.imageData = userProfileImage
            }
            else {
                account.imageData = nil
            }
            accountManager.add(account)
        }
    }
}

extension SessionManager: TeamObserver {
    public func teamDidChange(_ changeInfo: TeamChangeInfo) {
        let team = changeInfo.team
        guard let managedObjectContext = (team as? Team)?.managedObjectContext else {
            return
        }
        updateCurrentAccount(with: team, in: managedObjectContext)
    }
}

// MARK: - ZMUserObserver

extension SessionManager: ZMUserObserver {
    public func userDidChange(_ changeInfo: UserChangeInfo) {
        if changeInfo.teamsChanged || changeInfo.nameChanged || changeInfo.imageSmallProfileDataChanged {
            guard let user = changeInfo.user as? ZMUser,
                let managedObjectContext = user.managedObjectContext else {
                return
            }
            let selfUser = ZMUser.selfUser(in: managedObjectContext)
            updateCurrentAccount(with: selfUser.membership?.team, in: managedObjectContext)
        }
    }
}

// MARK: - UnauthenticatedSessionDelegate

extension SessionManager: UnauthenticatedSessionDelegate {

    public func session(session: UnauthenticatedSession, updatedCredentials credentials: ZMCredentials) -> Bool {
        guard let userSession = activeUserSession, let emailCredentials = credentials as? ZMEmailCredentials else { return false }
        
        userSession.setEmailCredentials(emailCredentials)
        RequestAvailableNotification.notifyNewRequestsAvailable(nil)
        return true
    }
    
    public func session(session: UnauthenticatedSession, updatedProfileImage imageData: Data) {
        updateProfileImage(imageData: imageData)
    }
    
    public func session(session: UnauthenticatedSession, createdAccount account: Account) {
        accountManager.addAndSelect(account)

        let group = self.dispatchGroup
        group?.enter()
        LocalStoreProvider.createStack(applicationContainer: sharedContainerURL, userIdentifier: account.userIdentifier, dispatchGroup: dispatchGroup) { [weak self] provider in
            self?.createSession(for: account, with: provider) { userSession in
                self?.registerSessionForRemoteNotificationsIfNeeded(userSession)
                if let profileImageData = session.authenticationStatus.profileImageData {
                    self?.updateProfileImage(imageData: profileImageData)
                }
                group?.leave()
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
        if nil != activeUserSession {
            return RequestAvailableNotification.notifyNewRequestsAvailable(self)
        }
    }
    
    public func authenticationDidFail(_ error: Error) {
        let error = error as NSError
        
        guard let userSessionErrorCode = ZMUserSessionErrorCode(rawValue: UInt(error.code)) else {
            return
        }
        
        switch userSessionErrorCode {
        case .accountDeleted:
            logoutCurrentSession(deleteCookie: true, error: error)
            if let deletedAccount = accountManager.selectedAccount {
                delete(account: deletedAccount)
            }
        case .clientDeletedRemotely,
             .accessTokenExpired:
            logoutCurrentSession(deleteCookie: true, error: error)
        default:
            delegate?.sessionManagerDidLogout(error: error)
            
            if unauthenticatedSession == nil {
                createUnauthenticatedSession()
            }
        }
    }

}

extension SessionManager: PushDispatcherClient {
    public func registerSessionForRemoteNotificationsIfNeeded(_ session: ZMUserSession) {
        session.managedObjectContext.performGroupedBlock {
            // Refresh the Voip token if needed
            self.pushDispatcher.lastKnownPushTokens.forEach { type, actualToken in
                switch type {
                case .voip:
                    if actualToken != session.managedObjectContext.pushKitToken.deviceToken {
                        session.managedObjectContext.pushKitToken = nil
                        session.setPushKitToken(actualToken)
                    }
                case .regular:
                    if actualToken != session.managedObjectContext.pushToken.deviceToken {
                        session.managedObjectContext.pushToken = nil
                        session.setPushToken(actualToken)
                    }
                }
            }
            
            session.registerForRemoteNotifications()
        }
    }
    
    public func didRegisteredForRemoteNotifications(with token: Data) {
        self.pushDispatcher.didRegisteredForRemoteNotifications(with: token)
    }
    
    public func didReceiveRemoteNotification(_ notification: [AnyHashable: Any], fetchCompletionHandler: @escaping (UIBackgroundFetchResult)->()) {
        self.pushDispatcher.didReceiveRemoteNotification(notification, fetchCompletionHandler: fetchCompletionHandler)
    }
    
    func wakeAllAccounts(for payload: [AnyHashable: Any], from source: ZMPushNotficationType, completion: ZMPushNotificationCompletionHandler?) {
        log.error("Push is not specifict to account, fetching all")
        self.accountManager.accounts.forEach { account in
            self.withSession(for: account, perform: { userSession in
                userSession.receivedPushNotification(with: payload, from: source, completion: completion)
            })
        }
    }
    
    public func receivedPushNotification(with payload: [AnyHashable: Any], from source: ZMPushNotficationType, completion: ZMPushNotificationCompletionHandler?) {
        
        guard !payload.isPayloadMissingUserInformation() else {
            self.wakeAllAccounts(for: payload, from: source, completion: completion)
            return
        }
        
        guard let userInfoData = payload[PushChannelDataKey] as? [String: Any] else {
            log.debug("No data dictionary in notification userInfo payload");
            return
        }
        
        guard let userIdString = userInfoData[PushChannelUserIDKey] as? String else {
            return
        }
        
        let userId = UUID(uuidString: userIdString)
    
        let matchingAccounts = self.accountManager.accounts.filter { (account) -> Bool in
            account.userIdentifier == userId
        }
        
        assert(matchingAccounts.count <= 1)
        
        if let account = matchingAccounts.first {
            self.withSession(for: account, perform: { userSession in
                userSession.receivedPushNotification(with: payload, from: source, completion: completion)
            })
        }
        else {
            self.wakeAllAccounts(for: payload, from: source, completion: completion)
        }
    }
}

// MARK: - ConversationListObserver

extension SessionManager: ZMConversationListObserver {
    
    public func conversationListDidChange(_ changeInfo: ConversationListChangeInfo) {
        
        // find which account/session the conversation list belongs to & update count
        guard let moc = changeInfo.conversationList.managedObjectContext else { return }
        
        for (account, session) in backgroundUserSessions where session.managedObjectContext == moc {
            account.unreadConversationCount = Int(ZMConversation.unreadConversationCount(in: moc))
        }
    }
}
