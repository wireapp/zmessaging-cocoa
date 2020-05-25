/*
 * Wire
 * Copyright (C) 2020 Wire Swiss GmbH
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */

import Foundation

/// A configuration class used specify behaviour of the Wire's calling implementation.

@objcMembers
public class WireCallCenterConfiguration: NSObject, Codable {

    /// The maximum number of participants allowed in a group video call.

    public let videoParticipantsLimit = 4

    /// Whether conference (SFT) calling is enabled.

    public let useConferenceCalling = false

}
