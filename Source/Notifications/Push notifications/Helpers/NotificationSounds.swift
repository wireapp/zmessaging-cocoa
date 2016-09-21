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


let ZMLocalNotificationRingingDefaultSoundName = "ringing_from_them_long.caf"
let ZMLocalNotificationPingDefaultSoundName = "ping_from_them.caf"
let ZMLocalNotificationNewMessageDefaultSoundName = "new_message_apns.caf"

func ZMCustomSoundName(_ key: String) -> String? {
    guard let soundName = UserDefaults.standard.object(forKey: key) as? String else { return nil }
    return ZMSound(rawValue: soundName)?.filename()
}

func ZMLocalNotificationRingingSoundName() -> String {
    return ZMCustomSoundName("ZMCallSoundName") ??  ZMLocalNotificationRingingDefaultSoundName
}

func ZMLocalNotificationPingSoundName() -> String {
    return ZMCustomSoundName("ZMPingSoundName") ?? ZMLocalNotificationPingDefaultSoundName
}

func ZMLocalNotificationNewMessageSoundName() -> String {
    return ZMCustomSoundName("ZMMessageSoundName") ?? ZMLocalNotificationNewMessageDefaultSoundName
}


public func findIndex<S: Sequence>(_ sequence: S, predicate: (S.Iterator.Element) -> Bool) -> Int? {
    for (index, element) in sequence.enumerated() {
        if predicate(element) {
            return index
        }
    }
    return nil
}

