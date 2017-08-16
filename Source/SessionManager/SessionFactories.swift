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


import avs


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
        environment: ZMBackendEnvironment,
        analytics: AnalyticsType? = nil
        ) {
        self.appVersion = appVersion
        self.mediaManager = mediaManager
        self.analytics = analytics
        self.apnsEnvironment = apnsEnvironment
        self.application = application
        self.environment = environment
    }

    func session(for account: Account, storeProvider: LocalStoreProviderProtocol, reachability: ReachabilityProvider) -> ZMUserSession? {
        let transportSession = ZMTransportSession(
            baseURL: environment.backendURL,
            websocketURL: environment.backendWSURL,
            cookieStorage: account.cookieStorage(),
            reachability: reachability,
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


open class UnauthenticatedSessionFactory {

    let environment: ZMBackendEnvironment

    init(environment: ZMBackendEnvironment) {
        self.environment = environment
    }

    func session(withDelegate delegate: UnauthenticatedSessionDelegate, reachability: ReachabilityProvider) -> UnauthenticatedSession {
        let transportSession = UnauthenticatedTransportSession(baseURL: environment.backendURL, reachability: reachability)
        return UnauthenticatedSession(transportSession: transportSession, reachability: reachability, delegate: delegate)
    }

}
