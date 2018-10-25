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

import WireSystem

internal enum BuildType {
    case production
    case alpha
    case development
    case `internal`

    init?(bundleID: String) {
        switch bundleID {
        case "com.wearezeta.zclient.ios": self = .production
        case "com.wearezeta.zclient-alpha": self = .alpha
        case "com.wearezeta.zclient.ios-development": self = .development
        case "com.wearezeta.zclient.ios-internal": self = .internal
        default: return nil
        }
    }
    
    var certificateName: String {
        switch self {
        case .production:
            return "com.wire"
        case .alpha:
            return "com.wire.ent"
        case .development:
            return "com.wire.dev.ent"
        case .internal:
            return "com.wire.int.ent"
        }
    }
    
    var bundleID: String {
        switch self {
        case .production:
            return "com.wearezeta.zclient.ios"
        case .alpha:
            return "com.wearezeta.zclient-alpha"
        case .development:
            return "com.wearezeta.zclient.ios-development"
        case .internal:
            return "com.wearezeta.zclient.ios-internal"
        }
        
    }
}

extension BuildType {
    static func setupBuildTypes() {
        ZMAPNSEnvironment.setupForProduction(withCertificateName: BuildType.production.certificateName)
        [BuildType.alpha, .development, .internal].forEach {
            ZMAPNSEnvironment.setupForEnterprise(withBundleId: $0.bundleID, withCertificateName: $0.certificateName)
        }
    }
}
