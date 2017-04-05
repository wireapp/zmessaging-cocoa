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


import XCTest
import WireSyncEngine
import ZMCDataModel

class ClientMessageTests_OTR: BaseZMClientMessageTests {
    
    var message: ZMClientMessage!
    
    func assertMessageMetadata(payload: NSData!) {
        let messageMetadata = ZMNewOtrMessageBuilder().mergeFromData(payload).build() as? ZMNewOtrMessage
        AssertOptionalNotNil(messageMetadata) { messageMetadata in
            
            XCTAssertEqual(messageMetadata.sender.client, self.selfClient1.clientId.client)
            self.assertRecipients(messageMetadata.recipients as! [ZMUserEntry])
        }
    }

    func testThatItCreatesPayloadDataForTextMessage() {
        self.syncMOC.performGroupedBlockAndWait {
            
            //given
           self.message = self.conversation.appendOTRMessageWithText(self.name, nonce: NSUUID.createUUID())
            
            //when
            let payload = self.message.encryptedMessagePayloadData()
            
            //then
            self.assertMessageMetadata(payload)
        }
    }
    
    func testThatItCreatesPayloadForZMLastReadMessages() {
        self.syncMOC.performGroupedBlockAndWait {
            // given

            self.conversation.lastReadServerTimeStamp = NSDate()
            self.conversation.remoteIdentifier = NSUUID()
            self.message = ZMConversation.appendSelfConversationWithLastReadOfConversation(self.conversation)
            
            self.expectedRecipients = [self.selfUser.remoteIdentifier!.transportString(): [self.selfClient2.remoteIdentifier]]
            
            // when
            let payload = self.message.encryptedMessagePayloadData()
            
            // then
            self.assertMessageMetadata(payload)
        }
    }

    func testThatItCreatesPayloadForZMClearedMessages() {
        self.syncMOC.performGroupedBlockAndWait {
            // given
            self.conversation.clearedTimeStamp = NSDate()
            self.conversation.remoteIdentifier = NSUUID()
            self.message = ZMConversation.appendSelfConversationWithClearedOfConversation(self.conversation)
            
            self.expectedRecipients = [self.selfUser.remoteIdentifier!.transportString(): [self.selfClient2.remoteIdentifier]]
            
            // when
            let payload = self.message.encryptedMessagePayloadData()
            
            // then
            self.assertMessageMetadata(payload)
        }
    }
    
    func testThatItCreatesPayloadForExternalMessage() {
        
        syncMOC.performGroupedBlockAndWait {
            // given
            self.message = self.conversation.appendOTRMessageWithText(self.textRequiringExternalMessage, nonce: NSUUID.createUUID())
            
            //when
            let payload = self.message.encryptedMessagePayloadData()
            
            //then
            self.assertMessageMetadata(payload)
        }
    }
    
    // MARK: - Helper
    
    private var textRequiringExternalMessage: String {
        var text = "Hello"
        while (text.dataUsingEncoding(NSUTF8StringEncoding)?.length < Int(ZMClientMessageByteSizeExternalThreshold)) {
            text.appendContentsOf(text)
        }
        return text
    }
    
}
