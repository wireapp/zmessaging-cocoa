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

import Foundation

public enum ZMSoundName: String {

    case call = "ZMCallSoundName"
    case ping = "ZMPingSoundName"
    case newMessage = "ZMMessageSoundName"

    public var fileName: String {
        return customFileName ?? defaultFileName
    }

    private var defaultFileName: String {
        switch self {
        case .call: return "ringing_from_them_long.caf"
        case .ping: return "ping_from_them.caf"
        case .newMessage: return "new_message_apns.caf"
        }
    }

    private var customFileName: String? {
        guard let soundName = UserDefaults.standard.object(forKey: rawValue) as? String else { return nil }
        return ZMSound(rawValue: soundName)?.filename()
    }

}
