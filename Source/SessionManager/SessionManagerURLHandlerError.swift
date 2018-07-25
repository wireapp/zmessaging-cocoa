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
 * Error that occur when processing URL actions.
 */

public enum SessionManagerURLHandlerError {

    /// The URL is missing a required parameter.
    static let missingRequiredParameter = "-2063"

    /// Invalid access credentials.
    static let invalidCookie = "-67700"
    
    /// The validation token was not found.
    static let tokenNotFound = "-25346"

}
