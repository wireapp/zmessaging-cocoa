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
    let flowManager : FlowManagerType
    var analytics: AnalyticsType?
    let application : ZMApplication
    var environment: BackendEnvironmentProvider
    let reachability: ReachabilityProvider & TearDownCapable

    public init(
        appVersion: String,
        application: ZMApplication,
        mediaManager: AVSMediaManager,
        flowManager: FlowManagerType,
        environment: BackendEnvironmentProvider,
        reachability: ReachabilityProvider & TearDownCapable,
        analytics: AnalyticsType? = nil
        ) {
        self.appVersion = appVersion
        self.mediaManager = mediaManager
        self.flowManager = flowManager
        self.analytics = analytics
        self.application = application
        self.environment = environment
        self.reachability = reachability
    }

    func session(for account: Account, storeProvider: LocalStoreProviderProtocol) -> ZMUserSession? {
        let transportSession = ZMTransportSession(
            environment: environment,
            cookieStorage: environment.cookieStorage(for: account),
            reachability: reachability,
            initialAccessToken: nil,
            applicationGroupIdentifier: nil
        )

        return ZMUserSession(
            mediaManager: mediaManager,
            flowManager:flowManager,
            analytics: analytics,
            transportSession: transportSession,
            application: application,
            appVersion: appVersion,
            storeProvider: storeProvider
        )
    }
    
}


open class UnauthenticatedSessionFactory {

    var environment: BackendEnvironmentProvider
    let reachability: ReachabilityProvider

    init(environment: BackendEnvironmentProvider, reachability: ReachabilityProvider) {
        self.environment = environment
        self.reachability = reachability
    }

    func session(withDelegate delegate: UnauthenticatedSessionDelegate) -> UnauthenticatedSession {
        let transportSession = UnauthenticatedTransportSession(environment: environment, reachability: reachability)
        return UnauthenticatedSession(transportSession: transportSession, reachability: reachability, delegate: delegate)
    }

}
