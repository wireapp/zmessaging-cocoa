//
// Wire
// Copyright (C) 2018 Wire Swiss GmbH
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

/**
 * An object that provides
 */

public protocol Pasteboard {

    /// Whether the pasteboard contains a text.
    var hasString: Bool { get }

    /// The text copied by the user.
    /// Always check `hasString` before accessing this value, to avoid.
    /// unnecessary resource consumption.
    var string: String? { get }

}

extension UIPasteboard: Pasteboard {

    public var hasString: Bool {
        if #available(iOS 10, *) {
            return self.hasStrings
        } else {
            return self.string != nil
        }
    }

}
