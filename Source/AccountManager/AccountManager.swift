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
public protocol AccountStateDelegate : class {
    
    func unauthenticatedSessionCreated(session : UnauthenticatedSession)
    func userSessionCreated(session : ZMUserSession)
    
}

@objc
public class AccountManager : NSObject {
    public let appGroupIdentifier: String
    public let appVersion: String
    public let mediaManager: AVSMediaManager
    public var analytics: AnalyticsType?
    let transportSession: ZMTransportSession
    public weak var delegate : AccountStateDelegate? = nil
    
    public init(appGroupIdentifier: String, appVersion: String, mediaManager: AVSMediaManager, analytics: AnalyticsType?, delegate: AccountStateDelegate?) {
        self.appGroupIdentifier = appGroupIdentifier
        self.appVersion = appVersion
        self.mediaManager = mediaManager
        self.analytics = analytics
        self.delegate = delegate
        
        ZMBackendEnvironment.setupEnvironments()
        let environment = ZMBackendEnvironment(userDefaults: .standard)
        let backendURL = environment.backendURL
        let websocketURL = environment.backendWSURL
        transportSession = ZMTransportSession(baseURL: backendURL,
                                              websocketURL: websocketURL,
                                              initialAccessToken: nil,
                                              sharedContainerIdentifier: nil)
        
        super.init()

        if storeExists {
        
            // TODO migrate if necessary
            
            let userSession = ZMUserSession(mediaManager: mediaManager,
                                            analytics: analytics,
                                            transportSession: transportSession,
                                            userId:nil,
                                            appVersion: appVersion,
                                            appGroupIdentifier: appGroupIdentifier)!
            
            delegate?.userSessionCreated(session: userSession)
        } else {
        }
    }
    
    public var isLoggedIn: Bool {
        return transportSession.cookieStorage.authenticationCookieData != nil
    }
    
    var storeExists : Bool {
        guard let storeURL = ZMUserSession.storeURL(forAppGroupIdentifier: appGroupIdentifier) else { return false }
        return FileManager.default.fileExists(atPath: storeURL.path)
    }
    
}
