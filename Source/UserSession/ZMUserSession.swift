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
//

import Foundation

@objc(ZMThirdPartyServicesDelegate)
public protocol ThirdPartyServicesDelegate: NSObjectProtocol {
    
    /// This will get called at a convenient point in time when Hockey and Localytics should upload their data.
    /// We try not to have Hockey and Localytics use the network while we're sync'ing.
    @objc(userSessionIsReadyToUploadServicesData:)
    func userSessionIsReadyToUploadServicesData(userSession: ZMUserSession)
    
}

typealias UserSessionDelegate = UserSessionEncryptionAtRestDelegate

@objcMembers
public class ZMUserSession: NSObject, ZMManagedObjectContextProvider, UserSessionAppLockInterface {
    
    private let appVersion: String
    private var tokens: [Any] = []
    private var tornDown: Bool = false
    
    var isNetworkOnline: Bool = true
    var isPerformingSync: Bool = true {
        willSet {
            notificationDispatcher.operationMode = newValue ? .economical : .normal
        }
    }
    var hasNotifiedThirdPartyServices: Bool = false
    
    var storeProvider: LocalStoreProviderProtocol!
    let application: ZMApplication
    let flowManager: FlowManagerType
    var mediaManager: MediaManagerType
    var analytics: AnalyticsType?
    var transportSession: TransportSessionType
    let storedDidSaveNotifications: ContextDidSaveNotificationPersistence
    let userExpirationObserver: UserExpirationObserver
    var syncStrategy: ZMSyncStrategy?
    var operationLoop: ZMOperationLoop?
    var notificationDispatcher: NotificationDispatcher
    var localNotificationDispatcher: LocalNotificationDispatcher?
    var applicationStatusDirectory: ApplicationStatusDirectory?
    var callStateObserver: CallStateObserver?
    var messageReplyObserver: ManagedObjectContextChangeObserver?
    var likeMesssageObserver: ManagedObjectContextChangeObserver?
    var urlActionProcessors: [URLActionProcessor]?
    let debugCommands: [String: DebugCommand]
    
    public var appLockController: AppLockType
    
    public var hasCompletedInitialSync: Bool = false
    
    public var topConversationsDirectory: TopConversationsDirectory
    
    public var managedObjectContext: NSManagedObjectContext { // TODO jacob we don't want this to be public
        return storeProvider.contextDirectory.uiContext
    }
    
    public var syncManagedObjectContext: NSManagedObjectContext { // TODO jacob we don't want this to be public
        return storeProvider.contextDirectory.syncContext
    }
    
    public var searchManagedObjectContext: NSManagedObjectContext { // TODO jacob we don't want this to be public
        return storeProvider.contextDirectory.searchContext
    }
    
    public var sharedContainerURL: URL { // TODO jacob we don't want this to be public
        return storeProvider.applicationContainer
    }
    
    public var selfUserClient: UserClient? { // TODO jacob we don't want this to be public
        return ZMUser.selfUser(in: managedObjectContext).selfClient()
    }
    
    public var userProfile: UserProfile? {
        return applicationStatusDirectory?.userProfileUpdateStatus
    }
    
    public var userProfileImage: UserProfileImageUpdateProtocol? {
        return applicationStatusDirectory?.userProfileImageUpdateStatus
    }
    
    public var conversationDirectory: ConversationDirectoryType {
        return managedObjectContext.conversationListDirectory()
    }
    
    public var operationStatus: OperationStatus? { // TODO jacob we don't want this to be public
        return applicationStatusDirectory?.operationStatus
    }
    
    public private(set) var networkState: ZMNetworkState = .online {
        didSet {
            if oldValue != networkState {
                ZMNetworkAvailabilityChangeNotification.notify(networkState: networkState, userSession: self)
            }
        }
    }
    
    public var isLoggedIn: Bool { // TODO jacob we don't want this to be public
        return transportSession.cookieStorage.isAuthenticated && applicationStatusDirectory?.clientRegistrationStatus.currentPhase == .registered
    }
    
    public var isNotificationContentHidden: Bool {
        get {
            guard let value = managedObjectContext.persistentStoreMetadata(forKey: LocalNotificationDispatcher.ZMShouldHideNotificationContentKey) as? NSNumber else {
                return false
            }
            
            return value.boolValue
        }
        set {
            managedObjectContext.setPersistentStoreMetadata(NSNumber(booleanLiteral: newValue), key: LocalNotificationDispatcher.ZMShouldHideNotificationContentKey)
        }
    }
    
    weak var delegate: UserSessionDelegate?
    
    // TODO remove this property and move functionality to separate protocols under UserSessionDelegate
    public weak var sessionManager: SessionManagerType?
     
    public weak var thirdPartyServicesDelegate: ThirdPartyServicesDelegate?
    
    // MARK: - Tear down
    
    deinit {
        require(tornDown, "tearDown must be called before the ZMUserSession is deallocated")
    }
    
    public func tearDown() {
        guard !tornDown else { return }
        
        tokens.removeAll()
        application.unregisterObserverForStateChange(self)
        callStateObserver = nil
        syncStrategy?.tearDown()
        syncStrategy = nil
        operationLoop?.tearDown()
        operationLoop = nil
        transportSession.tearDown()
        applicationStatusDirectory = nil
        notificationDispatcher.tearDown()
        
        // Wait for all sync operations to finish
        syncManagedObjectContext.performGroupedBlockAndWait { }
        
        let uiMOC = storeProvider.contextDirectory.uiContext
        storeProvider = nil
        
        let shouldWaitOnUIMoc = !(OperationQueue.current == OperationQueue.main && uiMOC?.concurrencyType == .mainQueueConcurrencyType)
        if shouldWaitOnUIMoc {
            uiMOC?.performAndWait {
                // warning: this will hang if the uiMoc queue is same as self.requestQueue (typically uiMoc queue is the main queue)
            }
        }
        
        NotificationCenter.default.removeObserver(self)
        
        tornDown = true
    }
    
    @objc
    public init(transportSession: TransportSessionType,
                mediaManager: MediaManagerType,
                flowManager: FlowManagerType,
                analytics: AnalyticsType?,
                syncStrategy: ZMSyncStrategy? = nil,
                operationLoop: ZMOperationLoop? = nil,
                application: ZMApplication,
                appVersion: String,
                storeProvider: LocalStoreProviderProtocol,
                configuration: Configuration) {
        
        storeProvider.contextDirectory.syncContext.performGroupedBlockAndWait {
            storeProvider.contextDirectory.syncContext.analytics = analytics
            storeProvider.contextDirectory.syncContext.zm_userInterface = storeProvider.contextDirectory.uiContext
        }
        storeProvider.contextDirectory.uiContext.zm_sync = storeProvider.contextDirectory.syncContext
        
        self.application = application
        self.appVersion = appVersion
        self.flowManager = flowManager
        self.mediaManager = mediaManager
        self.analytics = analytics
        self.storeProvider = storeProvider
        self.transportSession = transportSession
        self.notificationDispatcher = NotificationDispatcher(managedObjectContext: storeProvider.contextDirectory.uiContext)
        self.storedDidSaveNotifications = ContextDidSaveNotificationPersistence(accountContainer: storeProvider.accountContainer)
        self.userExpirationObserver = UserExpirationObserver(managedObjectContext: storeProvider.contextDirectory.uiContext)
        self.topConversationsDirectory = TopConversationsDirectory(managedObjectContext: storeProvider.contextDirectory.uiContext)
        self.debugCommands = ZMUserSession.initDebugCommands()
        self.appLockController = AppLockController(config: configuration.appLockConfig, selfUser: ZMUser.selfUser(in: storeProvider.contextDirectory.uiContext))
        super.init()
        
        ZMUserAgent.setWireAppVersion(appVersion)
        
        configureCaches()
        
        syncManagedObjectContext.performGroupedBlockAndWait {
            self.localNotificationDispatcher = LocalNotificationDispatcher(in: storeProvider.contextDirectory.syncContext)
            self.configureTransportSession()
            self.applicationStatusDirectory = self.createApplicationStatusDirectory()
            self.syncStrategy = syncStrategy ?? self.createSyncStrategy()
            self.operationLoop = operationLoop ?? self.createOperationLoop()
            self.urlActionProcessors = self.createURLActionProcessors()
            self.callStateObserver = CallStateObserver(localNotificationDispatcher: self.localNotificationDispatcher!,
                                                       contextProvider: self,
                                                       callNotificationStyleProvider: self)
        }

        registerForCalculateBadgeCountNotification()
        registerForRegisteringPushTokenNotification()
        registerForBackgroundNotifications()
        enableBackgroundFetch()
        observeChangesOnShareExtension()
        startEphemeralTimers()
        notifyUserAboutChangesInAvailabilityBehaviourIfNeeded()
        RequestAvailableNotification.notifyNewRequestsAvailable(self)
        restoreDebugCommandsState()
    }
    
    private func configureTransportSession() {
        transportSession.pushChannel.clientID = selfUserClient?.remoteIdentifier
        transportSession.setNetworkStateDelegate(self)
        transportSession.setAccessTokenRenewalFailureHandler { [weak self] (response) in
            self?.transportSessionAccessTokenDidFail(response: response)
        }
    }
    
    private func configureCaches() {
        let cacheLocation = FileManager.default.cachesURLForAccount(with: storeProvider.userIdentifier, in: storeProvider.applicationContainer)
        ZMUserSession.moveCachesIfNeededForAccount(with: storeProvider.userIdentifier, in: storeProvider.applicationContainer)
        
        let userImageCache = UserImageLocalCache(location: cacheLocation)
        let fileAssetCache = FileAssetCache(location: cacheLocation)
        
        managedObjectContext.zm_userImageCache = userImageCache
        managedObjectContext.zm_fileAssetCache = fileAssetCache
        managedObjectContext.zm_searchUserCache = NSCache()
        
        syncManagedObjectContext.performGroupedBlockAndWait {
            self.syncManagedObjectContext.zm_userImageCache = userImageCache
            self.syncManagedObjectContext.zm_fileAssetCache = fileAssetCache
        }

    }
    
    private func createApplicationStatusDirectory() -> ApplicationStatusDirectory {
        let applicationStatusDirectory = ApplicationStatusDirectory(withManagedObjectContext: self.syncManagedObjectContext,
                                                                     cookieStorage: transportSession.cookieStorage,
                                                                     requestCancellation: transportSession,
                                                                     application: application,
                                                                     syncStateDelegate: self,
                                                                     analytics: analytics)
        
        applicationStatusDirectory.clientRegistrationStatus.prepareForClientRegistration()
        self.hasCompletedInitialSync = !applicationStatusDirectory.syncStatus.isSlowSyncing
        
        return applicationStatusDirectory
    }
    
    private func createURLActionProcessors() -> [URLActionProcessor] {
        return [
            DeepLinkURLActionProcessor(contextProvider: self),
            ConnectToBotURLActionProcessor(contextprovider: self,
                                           transportSession: transportSession,
                                           eventProcessor: syncStrategy!)
        ]
    }
    
    private func createSyncStrategy() -> ZMSyncStrategy {
        let strategyFactory = RequestStrategyFactory(contextDirectory: storeProvider.contextDirectory,
                                                     applicationStatusDirectory: applicationStatusDirectory!,
                                                     cookieStorage: transportSession.cookieStorage,
                                                     pushMessageHandler: localNotificationDispatcher!,
                                                     flowManager: flowManager,
                                                     updateEventProcessor: self,
                                                     localNotificationDispatcher: localNotificationDispatcher!)
        
        return ZMSyncStrategy(storeProvider: storeProvider,
                              notificationsDispatcher: notificationDispatcher,
                              applicationStatusDirectory: applicationStatusDirectory!,
                              application: application,
                              requestStrategyFactory: strategyFactory)
    }
    
    private func createOperationLoop() -> ZMOperationLoop {
        return ZMOperationLoop(transportSession: transportSession,
                               requestStrategy: syncStrategy,
                               updateEventProcessor: self,
                               applicationStatusDirectory: applicationStatusDirectory!,
                               uiMOC: managedObjectContext,
                               syncMOC: syncManagedObjectContext)
    }
    
    func startRequestLoopTracker() {        
        transportSession.requestLoopDetectionCallback = { path in
            guard !path.hasSuffix("/typing") else { return }

            Logging.network.warn("Request loop happening at path: \(path)")
            
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Notification.Name(rawValue: ZMLoggingRequestLoopNotificationName),
                                                object: nil,
                                                userInfo: ["path": path])
            }
        }
    }
    
    private func registerForCalculateBadgeCountNotification() {
        tokens.append(NotificationInContext.addObserver(name: .calculateBadgeCount, context: managedObjectContext.notificationContext) { [weak self] (_) in
            self?.calculateBadgeCount()
        })
    }
    
    private func registerForBackgroundNotifications() {
        application.registerObserverForDidEnterBackground(self, selector: #selector(applicationDidEnterBackground(_:)))
        application.registerObserverForWillEnterForeground(self, selector: #selector(applicationWillEnterForeground(_:)))
        
    }
    
    private func enableBackgroundFetch() {
        // We enable background fetch by setting the minimum interval to something different from UIApplicationBackgroundFetchIntervalNever
        application.setMinimumBackgroundFetchInterval(10.0 * 60.0 + Double(arc4random_uniform(5 * 60)))
    }
    
    private func notifyUserAboutChangesInAvailabilityBehaviourIfNeeded() {
        syncManagedObjectContext.performGroupedBlock {
            self.localNotificationDispatcher?.notifyAvailabilityBehaviourChangedIfNeeded()
        }
    }
    
    // MARK: - Network
    
    public func requestSlowSync() {
        applicationStatusDirectory?.requestSlowSync()
    }
    
    private func transportSessionAccessTokenDidFail(response: ZMTransportResponse) {
        managedObjectContext.performGroupedBlock {
            let selfUser = ZMUser.selfUser(in: self.managedObjectContext)
            let error = NSError.userSessionErrorWith(.accessTokenExpired, userInfo: selfUser.loginCredentials.dictionaryRepresentation)
            PostLoginAuthenticationNotification.notifyAuthenticationInvalidated(error: error, context: self.managedObjectContext)
        }
    }
    
    // MARK: - Perform changes
    
    public func saveOrRollbackChanges() {
        managedObjectContext.saveOrRollback()
    }
    
    @objc(performChanges:)
    public func perform(_ changes: @escaping () -> Void) {
        managedObjectContext.performGroupedBlockAndWait { [weak self] in
            changes()
            self?.saveOrRollbackChanges()
        }
    }
    
    @objc(enqueueChanges:)
    public func enqueue(_ changes: @escaping () -> Void) {
        enqueue(changes, completionHandler: nil)
    }
    
    @objc(enqueueChanges:completionHandler:)
    public func enqueue(_ changes: @escaping () -> Void, completionHandler: (() -> Void)?) {
        managedObjectContext.performGroupedBlock { [weak self] in
            changes()
            self?.saveOrRollbackChanges()
            completionHandler?()
        }
    }
    
    @objc(enqueueDelayedChanges:completionHandler:)
    public func enqueueDelayed(_ changes: @escaping () -> Void, completionHandler: (() -> Void)?) {
        managedObjectContext.performGroupedBlock { [weak self] in
            changes()
            self?.saveOrRollbackChanges()
            
            let group = ZMSDispatchGroup(label: "enqueueDelayedChanges")
            self?.managedObjectContext.enqueueDelayedSave(with: group)
            
            group?.notify(on: DispatchQueue.global(qos: .background), block: {
                self?.managedObjectContext.performGroupedBlock {
                    completionHandler?()
                }
            })
        }
    }
    
    // MARK: - Account
    
    public func initiateUserDeletion() {
        syncManagedObjectContext.performGroupedBlock {
            self.syncManagedObjectContext.setPersistentStoreMetadata(NSNumber(booleanLiteral: true), key: DeleteAccountRequestStrategy.userDeletionInitiatedKey)
            RequestAvailableNotification.notifyNewRequestsAvailable(self)
        }
    }
    
}

extension ZMUserSession: ZMNetworkStateDelegate {
    
    public func didReceiveData() {
        managedObjectContext.performGroupedBlock { [weak self] in
            self?.isNetworkOnline = true
            self?.updateNetworkState()
        }
    }
    
    public func didGoOffline() {
        managedObjectContext.performGroupedBlock { [weak self] in
            self?.isNetworkOnline = false
            self?.updateNetworkState()
            self?.saveOrRollbackChanges()
            
        }
    }
    
    func updateNetworkState() {
        let state: ZMNetworkState
        
        if isNetworkOnline {
            if isPerformingSync {
                state = .onlineSynchronizing
            } else {
                state = .online
            }
        } else {
            state = .offline
        }
        
        networkState = state
    }
    
}

extension ZMUserSession: ZMSyncStateDelegate {
    
    public func didStartSlowSync() {
        managedObjectContext.performGroupedBlock { [weak self] in
            self?.isPerformingSync = true
            self?.notificationDispatcher.isEnabled = false
            self?.updateNetworkState()
        }
    }
    
    public func didFinishSlowSync() {
        managedObjectContext.performGroupedBlock { [weak self] in
            self?.hasCompletedInitialSync = true
            self?.notificationDispatcher.isEnabled = true
            
            if let context = self?.managedObjectContext {
                ZMUserSession.notifyInitialSyncCompleted(context: context)
            }
        }
    }
    
    public func didStartQuickSync() {
        managedObjectContext.performGroupedBlock { [weak self] in
            self?.isPerformingSync = true
            self?.updateNetworkState()
        }
    }
    
    public func didFinishQuickSync() {
        guard let syncStrategy = syncStrategy else { return }
        
        syncStrategy.processAllEventsInBuffer()
        processEvents()
        
        managedObjectContext.performGroupedBlock { [weak self] in
            self?.notifyThirdPartyServices()
        }
    }
    
    func processEvents() {
        guard let syncStrategy = syncStrategy else { return }
        
        managedObjectContext.performGroupedBlock { [weak self] in
            self?.isPerformingSync = true
            self?.updateNetworkState()
        }
        
        let hasMoreEventsToProcess = syncStrategy.processEventsIfReady()
        
        managedObjectContext.performGroupedBlock { [weak self] in
            self?.isPerformingSync = hasMoreEventsToProcess
            self?.updateNetworkState()
        }
    }
    
    public func didRegister(_ userClient: UserClient!) {
        
        // If during registration user allowed notifications,
        // The push token can only be registered after client registration
        transportSession.pushChannel.clientID = userClient.remoteIdentifier
        registerCurrentPushToken()
    }
    
    func notifyThirdPartyServices() {
        if !hasNotifiedThirdPartyServices {
            hasNotifiedThirdPartyServices = true
            thirdPartyServicesDelegate?.userSessionIsReadyToUploadServicesData(userSession: self)
        }
    }
    
}

extension ZMUserSession: URLActionProcessor {
    func process(urlAction: URLAction, delegate: PresentationDelegate?) {
        urlActionProcessors?.forEach({ $0.process(urlAction: urlAction, delegate: delegate)} )
    }
}

// TODO jacob temporary solution while refactoring
extension ZMUserSession: UpdateEventProcessor {
    
    public func storeUpdateEvents(_ updateEvents: [ZMUpdateEvent], ignoreBuffer: Bool) {
        syncStrategy?.storeUpdateEvents(updateEvents, ignoreBuffer: ignoreBuffer)
    }
    
    public func storeAndProcessUpdateEvents(_ updateEvents: [ZMUpdateEvent], ignoreBuffer: Bool) {
        syncStrategy?.storeAndProcessUpdateEvents(updateEvents, ignoreBuffer: ignoreBuffer)
    }
        
}
