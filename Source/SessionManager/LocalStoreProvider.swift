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

public protocol LocalStoreProviderProtocol {
    func storeExists(forAppGroupIdentifier appGroupIdentifier:String) -> Bool
    func storeURL(forAppGroupIdentifier appGroupIdentifier: String) -> URL
    func needsToPrepareLocalStore(usingAppGroupIdentifier appGroupIdentifier: String) -> Bool
    func prepareLocalStore(usingAppGroupIdentifier appGroupIdentifier: String, completion completionHandler: (() -> ()))
}

class LocalStoreProvider {
    
}

extension LocalStoreProvider: LocalStoreProviderProtocol {
    func storeURL(forAppGroupIdentifier appGroupIdentifier: String) -> URL {
        fatalError()
    }
    
    func storeExists(forAppGroupIdentifier appGroupIdentifier:String) -> Bool {
        let storeURL = self.storeURL(forAppGroupIdentifier: appGroupIdentifier)
        return NSManagedObjectContext.storeExists(at: storeURL)
    }
    
    func needsToPrepareLocalStore(usingAppGroupIdentifier appGroupIdentifier: String) -> Bool {
        fatalError()
    }
    
    func prepareLocalStore(usingAppGroupIdentifier appGroupIdentifier: String, completion completionHandler: (() -> ())) {
        fatalError()
    }

}
