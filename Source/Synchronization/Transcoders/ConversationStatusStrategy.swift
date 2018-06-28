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
import WireDataModel

@objc
public final class ConversationStatusStrategy : ZMObjectSyncStrategy, ZMContextChangeTracker {

    let lastReadKey = "lastReadServerTimeStamp"
    let clearedKey = "clearedTimeStamp"
    
    public func objectsDidChange(_ objects: Set<NSManagedObject>) {
        var didUpdateConversation = false
        objects.forEach{
            if let conv = $0 as? ZMConversation {
                if conv.hasLocalModifications(forKey: lastReadKey){
                    conv.resetLocallyModifiedKeys(Set(arrayLiteral: lastReadKey))
                    ZMConversation.appendSelfConversation(withLastReadOf: conv)
                    didUpdateConversation = true
                }
                if conv.hasLocalModifications(forKey: clearedKey) {
                    conv.resetLocallyModifiedKeys(Set(arrayLiteral: clearedKey))
                    conv.deleteOlderMessages()
                    ZMConversation.appendSelfConversation(withClearedOf: conv)
                    didUpdateConversation = true
                }
            }
        }
        
        if didUpdateConversation {
            self.managedObjectContext?.enqueueDelayedSave()
        }
    }
    
    public func fetchRequestForTrackedObjects() -> NSFetchRequest<NSFetchRequestResult>? {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: ZMConversation.entityName())
        return request
    }
    
    public func addTrackedObjects(_ objects: Set<NSManagedObject>) {
        objectsDidChange(objects)
    }
    
}
