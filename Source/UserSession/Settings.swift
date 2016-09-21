// 
// Wire
// Copyright (C) 2016 Wire Swiss GmbH
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


enum SettingsKeys {
    case shouldSendOnlyEncrypted
}

@objc
public final class ZMSettings: NSObject {
    
    /// Shared settings
    public static let sharedSettings : ZMSettings = ZMSettings()
    
    /// Isolation queue to change settings
    fileprivate let isolationQueue : DispatchQueue
    
    /// Internal settings storage
    fileprivate var settingsStorage : [SettingsKeys:Bool]
    
    override init() {
        isolationQueue = DispatchQueue(label: "ZMSettings", attributes: DispatchQueue.Attributes.concurrent)
        settingsStorage = [:]
        super.init()
    }
    
    /// Gets the boolean value of a key with a sync barrier
    fileprivate func getBoolValue(_ key: SettingsKeys) -> Bool {
        var value : Bool?
        isolationQueue.sync {
            value = self.settingsStorage[key]
        }
        if let value = value {
            return value
        }
        return false;
    }
    
    /// Sets the boolean value of a key with an async barrier
    fileprivate func setBoolValue(_ key: SettingsKeys, value: Bool) {
        isolationQueue.async(flags: .barrier, execute: {
            self.settingsStorage[key] = value
        }) 
    }
}
