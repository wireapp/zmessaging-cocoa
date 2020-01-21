//
// Wire
// Copyright (C) 2019 Wire Swiss GmbH
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

import UIKit

/// SessionManagerConfiguration is configuration class which can be used when initializing a SessionManager configure
/// change the default behaviour.

@objcMembers
public class SessionManagerConfiguration: NSObject, NSCopying, Codable {
    
    /// If set to true then the session manager will delete account data instead of just asking the user to re-authenticate when the cookie or client gets invalidated.
    ///
    /// The default value of this property is `false`.
    public var wipeOnCookieInvalid: Bool
    
    /// The `blacklistDownloadInterval` configures at which rate we update the client blacklist
    ///
    /// The default value of this property is `6 hours`
    public var blacklistDownloadInterval: TimeInterval
    
    /// The `blockOnJailbreakOrRoot` configures if app should lock when the device is jailbroken
    ///
    /// The default value of this property is `false`
    public var blockOnJailbreakOrRoot: Bool
    
    /// If set to true then the session manager will delete account data on a jailbroken device.
    ///
    /// The default value of this property is `false`
    public var wipeOnJailbreakOrRoot: Bool
    
    /// `The messageRetentionInterval` if specified will limit how long messages are retained. Messages older than
    /// the the `messageRetentionInterval` will be deleted.
    ///
    /// The default value of this property is `nil`, i.e. messages are kept forever.
    public var messageRetentionInterval: TimeInterval?
    
    /// If set to true then the session manager will ask to re-authenticate after device reboot.
    ///
    /// The default value of this property is `false`
    public var authenticateAfterReboot: Bool
    
    /// The `failedPasswordThresholdBeforeWipe` configures the limit of failed password attempts before
    /// which the session manager will delete account data.
    ///
    /// The default value of this property is `nil`, i.e. threshold is ignored
    public var failedPasswordThresholdBeforeWipe: Int?
    
    public init(wipeOnCookieInvalid: Bool = false,
                blacklistDownloadInterval: TimeInterval = 6 * 60 * 60,
                blockOnJailbreakOrRoot: Bool = false,
                wipeOnJailbreakOrRoot: Bool = false,
                messageRetentionInterval: TimeInterval? = nil,
                authenticateAfterReboot: Bool = false,
                failedPasswordThresholdBeforeWipe: Int? = nil) {
        self.wipeOnCookieInvalid = wipeOnCookieInvalid
        self.blacklistDownloadInterval = blacklistDownloadInterval
        self.blockOnJailbreakOrRoot = blockOnJailbreakOrRoot
        self.wipeOnJailbreakOrRoot = wipeOnJailbreakOrRoot
        self.messageRetentionInterval = messageRetentionInterval
        self.authenticateAfterReboot = authenticateAfterReboot
        self.failedPasswordThresholdBeforeWipe = failedPasswordThresholdBeforeWipe
    }
    
    public func copy(with zone: NSZone? = nil) -> Any {
        let copy = SessionManagerConfiguration(wipeOnCookieInvalid: wipeOnCookieInvalid,
                                               blacklistDownloadInterval: blacklistDownloadInterval,
                                               blockOnJailbreakOrRoot: blockOnJailbreakOrRoot,
                                               wipeOnJailbreakOrRoot: wipeOnJailbreakOrRoot,
                                               messageRetentionInterval: messageRetentionInterval,
                                               authenticateAfterReboot: authenticateAfterReboot,
                                               failedPasswordThresholdBeforeWipe: failedPasswordThresholdBeforeWipe)
        
        return copy
    }
    
    public static var defaultConfiguration: SessionManagerConfiguration {
        return SessionManagerConfiguration()
    }
    
    public static func load(from URL: URL) -> SessionManagerConfiguration? {
        guard let data = try? Data(contentsOf: URL) else { return nil }
        
        let decoder = JSONDecoder()
        
        return  try? decoder.decode(SessionManagerConfiguration.self, from: data)
    }
}
