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

import Foundation
import WireDataModel

public struct SearchOptions : OptionSet {
    public let rawValue: Int

    public static let contacts = SearchOptions(rawValue: 1 << 0)
    public static let addressBook = SearchOptions(rawValue: 1 << 1)
    public static let teamMembers = SearchOptions(rawValue: 1 << 2)
    public static let directory = SearchOptions(rawValue: 1 << 3)
    public static let conversations = SearchOptions(rawValue: 1 << 4)
    
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
}

public struct SearchRequest {
    
    let maxQueryLength = 200
    
    public init(query: String, searchOptions: SearchOptions, team: Team? = nil) {
        self.query = query.truncated(at: maxQueryLength)
        self.searchOptions = searchOptions
        self.team = team
    }
    
    var team : Team? = nil
    let query : String
    let searchOptions: SearchOptions
    
}
