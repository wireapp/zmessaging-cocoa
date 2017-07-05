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

@objc
public protocol SessionManagerDelegate : class {
    
    func sessionManagerCreated(unauthenticatedSession : UnauthenticatedSession)
    func sessionManagerCreated(userSession : ZMUserSession)
    func sessionManagerWillStartMigratingLocalStore()
}

@objc
public class SessionManager : NSObject {
    public let appGroupIdentifier: String
    public let appVersion: String
    public let mediaManager: AVSMediaManager
    public var analytics: AnalyticsType?
    let transportSession: ZMTransportSession
    public weak var delegate : SessionManagerDelegate? = nil
    var authenticationToken: Any?
    let authenticationStatus: ZMAuthenticationStatus
    var userSession: ZMUserSession?
    
    public init(appGroupIdentifier: String, appVersion: String, mediaManager: AVSMediaManager, analytics: AnalyticsType?, delegate: SessionManagerDelegate?, application: ZMApplication, launchOptions: [UIApplicationLaunchOptionsKey : Any]) {
        self.appGroupIdentifier = appGroupIdentifier
        self.appVersion = appVersion
        self.mediaManager = mediaManager
        self.analytics = analytics
        self.delegate = delegate
        
        ZMBackendEnvironment.setupEnvironments()
        let environment = ZMBackendEnvironment(userDefaults: .standard)
        let backendURL = environment.backendURL
        let websocketURL = environment.backendWSURL
        let cookieStorage = ZMPersistentCookieStorage(forServerName: backendURL.host!)
        authenticationStatus = ZMAuthenticationStatus(cookieStorage: cookieStorage)
        transportSession = ZMTransportSession(baseURL: backendURL,
                                              websocketURL: websocketURL,
                                              cookieStorage: cookieStorage,
                                              initialAccessToken: nil,
                                              sharedContainerIdentifier: nil)
        
        super.init()
        
        authenticationToken = ZMUserSessionAuthenticationNotification.addObserver(self)

        if storeExists {
            let createSession = {
                let userSession = ZMUserSession(mediaManager: mediaManager,
                                                analytics: analytics,
                                                transportSession: self.transportSession,
                                                userId:nil,
                                                appVersion: appVersion,
                                                appGroupIdentifier: appGroupIdentifier)!
                
                delegate?.sessionManagerCreated(userSession: userSession)
                userSession.application(application, didFinishLaunchingWithOptions: launchOptions)
                if let url = launchOptions[.url] as? URL {
                    userSession.didLaunch(with: url)
                }
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
            do {
                let unauthenticatedSession = try UnauthenticatedSession(authenticationStatus: authenticationStatus, transportSession: transportSession, delegate: self)
                delegate?.sessionManagerCreated(unauthenticatedSession: unauthenticatedSession)
            } catch let error {
                fatal("Can't create unauthenticated session: \(error)")
            }
        }
    }
    
    public var isLoggedIn: Bool {
        return transportSession.cookieStorage.authenticationCookieData != nil
    }
    
    var storeExists : Bool {
        guard let storeURL = ZMUserSession.storeURL(forAppGroupIdentifier: appGroupIdentifier) else { return false }
        return FileManager.default.fileExists(atPath: storeURL.path)
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

extension SessionManager: UnauthenticatedSessionDelegate {
    func session(session: UnauthenticatedSession, updatedCredentials credentials: ZMCredentials) {
        if let userSession = userSession, let emailCredentials = credentials as? ZMEmailCredentials {
            userSession.setEmailCredentials(emailCredentials)
        }
    }
    
    func session(session: UnauthenticatedSession, updatedProfileImage imageData: Data) {
        updateProfileImage(imageData: imageData)
    }
}

extension SessionManager: ZMAuthenticationObserver {
    
    @objc public func authenticationDidSucceed() {
        guard self.userSession == nil else { return }
        let userSession = ZMUserSession(mediaManager: mediaManager,
                                        analytics: analytics,
                                        transportSession: transportSession,
                                        userId:nil,
                                        appVersion: appVersion,
                                        appGroupIdentifier: appGroupIdentifier)!
        self.userSession = userSession
        userSession.setEmailCredentials(authenticationStatus.emailCredentials())
        
        userSession.syncManagedObjectContext.performGroupedBlock {
            userSession.syncManagedObjectContext.registeredOnThisDevice = self.authenticationStatus.completedRegistration
        }
        
        if let profileImageData =  authenticationStatus.profileImageData {
            updateProfileImage(imageData: profileImageData)
        }
        
        delegate?.sessionManagerCreated(userSession: userSession)
    }
}
