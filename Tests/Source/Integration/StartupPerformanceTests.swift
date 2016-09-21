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
import XCTest

class StartupPerformanceTests: MessagingTest {

    override func setUp() {
        super.setUp()
        self.createData()
    }
    
    private func createData() {

        let NumberOfUsers = 500; // half are connected
        let UsersPerConversation = 50
        let NumberOfGroupConversations = 200;
        let NumberOfMessages = 200;
        
        var users : [ZMUser] = []
        
        let jpeg1 = self.dataForResource("DownsampleImageRotated3", `extension`: "jpg")
        let jpeg2 = self.dataForResource("Church_1MB_medium", `extension`: "jpg")
        
        // create users
        for u in 0...NumberOfUsers {
            let user = ZMUser.insertNewObjectInManagedObjectContext(self.syncMOC)
            user.name = "Name of user \(u+1)"
            user.imageMediumData = (u % 2 == 0) ? jpeg1 : jpeg2
            user.imageSmallProfileData = self.verySmallJPEGData()
            user.remoteIdentifier = self.createUUID()
            
            // if connected...
            if u % 2 == 0 {
                let connection = ZMConnection.insertNewObjectInManagedObjectContext(self.syncMOC)
                connection.to = user
                connection.conversation = ZMConversation.insertNewObjectInManagedObjectContext(self.syncMOC)
                connection.conversation.conversationType = .OneOnOne
                connection.conversation.mutableOtherActiveParticipants.addObject(user)
                connection.conversation.remoteIdentifier = self.createUUID()
            }
            users.append(user)
        }
        
        // create conversations
        for c in 0...NumberOfGroupConversations {
            
            let conv = ZMConversation.insertNewObjectInManagedObjectContext(self.syncMOC)
            conv.userDefinedName = "Conversation #\(c+1)"
            conv.remoteIdentifier = self.createUUID()
            conv.conversationType = .Group
            
            // add users
            for idx in 0...min(UsersPerConversation, NumberOfUsers) {
                let userIndex = ((c+idx+19)*167) % NumberOfUsers // pseudo-random
                conv.addParticipant(users[userIndex])
            }
            
            // create messages
            for m in 0...NumberOfMessages {
                var message : ZMMessage
                if m % 3 == 0 { // image
                    let msg = ZMImageMessage.insertNewObjectInManagedObjectContext(self.syncMOC)
                    msg.mediumData = m % 2 == 0 ? jpeg1 : jpeg2
                    message = msg
                }
                else { // text
                    let msg = ZMTextMessage.insertNewObjectInManagedObjectContext(self.syncMOC)
                    msg.text = "This is the text of message number \(m+1) in conversation number \(c+1)"
                    message = msg
                }
                message.sender = users[m % NumberOfUsers]
                message.conversation = conv
                message.nonce = self.createUUID()
                message.eventID = self.createEventID()
            }
            
            conv.lastReadEventID = (conv.messages.lastObject! as! ZMMessage).eventID
            conv.lastEventID = conv.lastReadEventID
            conv.lastModifiedDate = NSDate(timeIntervalSince1970: 23125323)
        }
        
        self.syncMOC.saveOrRollback()
    }
    
    override func tearDown() {
        super.tearDown()
    }

    func testPerformance() {
        
        class TestObserver : NSObject, ZMConversationListObserver
        {
            @objc func conversationListDidChange(changeInfo: zmessaging.ConversationListChangeInfo!) {
                
            }
        }
        
        // This is an example of a performance test case.
        self.measureBlock() {
            let session = self.dummyUserSession()
            session.start()
            
            let list = ZMConversation.conversationsInUserSession(session)
            let observer = TestObserver()
            
            let token = list.addConversationListObserver(observer)
            list.removeConversationListObserverForToken(token)
            
            session.tearDown()
        }
    }

}
