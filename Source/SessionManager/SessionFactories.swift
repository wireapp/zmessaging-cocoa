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
