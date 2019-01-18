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

class ConversationTests_Confirmation: ConversationTestsBase {
    
    func testThatItSendsAConfirmationWhenReceivingAMessageInAOneOnOneConversation() {
        if (BackgroundAPNSConfirmationStatus.sendDeliveryReceipts) {
            // given
            XCTAssert(login())
            
            let fromClient = user1?.clients.anyObject() as! MockUserClient
            let toClient = selfUser?.clients.anyObject() as! MockUserClient
            let textMessage = ZMGenericMessage.message(content: ZMText.text(with: "Hello"))
            let conversation = self.conversation(for: selfToUser1Conversation!)
            
            let requestPath = "/conversations/\(conversation!.remoteIdentifier!.transportString())/otr/messages?report_missing=\(user1!.identifier)"
            
            // expect
            mockTransportSession?.responseGeneratorBlock = { request in
                if (request.path == requestPath) {
                    guard let hiddenMessage = conversation?.hiddenMessages.first as? ZMClientMessage,
                        let message = conversation?.recentMessages.last as? ZMClientMessage
                        else {
                            XCTFail("Did not insert confirmation message.")
                            return nil
                    }
                    XCTAssertTrue(hiddenMessage.genericMessage!.hasConfirmation())
                    XCTAssertEqual(hiddenMessage.genericMessage!.confirmation.firstMessageId, message.nonce!.transportString())
                }
                return nil
            }
            
            // when
            mockTransportSession?.performRemoteChanges { session in
                self.selfToUser1Conversation?.encryptAndInsertData(from: fromClient, to: toClient, data: textMessage.data())
            }
            XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.1))
            
            // then
            let messages = conversation?.recentMessages
            XCTAssertEqual(messages?.count, 2) // system message & inserted message
            
            guard let request = mockTransportSession?.receivedRequests().last else {return XCTFail()}
            XCTAssertEqual((request as AnyObject).path, requestPath)
            
            XCTAssertEqual(conversation?.lastModifiedDate, messages?.last?.serverTimestamp)
        }
    }
    
    
    func testThatItSetsAMessageToDeliveredWhenReceivingAConfirmationMessageInAOneOnOneConversation() {
        if (BackgroundAPNSConfirmationStatus.sendDeliveryReceipts) {
            
            // given
            XCTAssert(login())
            
            let conversation = self.conversation(for: selfToUser1Conversation!)
            var message : ZMClientMessage!
            self.userSession?.performChanges {
                message = conversation?.append(text: "Hello") as? ZMClientMessage
            }
            XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.1))
            XCTAssertEqual(message.deliveryState, ZMDeliveryState.sent)
            
            let fromClient = user1?.clients.anyObject() as! MockUserClient
            let toClient = selfUser?.clients.anyObject() as! MockUserClient
            let confirmationMessage = ZMGenericMessage.message(content: ZMConfirmation.confirm(messageId: message.nonce!))
            
            // when
            mockTransportSession?.performRemoteChanges { session in
                self.selfToUser1Conversation?.encryptAndInsertData(from: fromClient, to: toClient, data: confirmationMessage.data())
            }
            XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.1))
            
            // then
            // The confirmation message is not inserted
            XCTAssertEqual(conversation?.hiddenMessages.count, 0)
            XCTAssertEqual(message.deliveryState, ZMDeliveryState.delivered)
            
            XCTAssertEqual(conversation?.lastModifiedDate, message.serverTimestamp)
        }
    }
    
    func testThatItSendsANotificationWhenUpdatingTheDeliveryState() {
        guard BackgroundAPNSConfirmationStatus.sendDeliveryReceipts else { return }
        // given
        XCTAssert(login())

        let conversation = self.conversation(for: selfToUser1Conversation!)
        var message : ZMClientMessage!
        self.userSession?.performChanges {
            message = conversation?.append(text: "Hello") as? ZMClientMessage
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.1))
        XCTAssertEqual(conversation?.hiddenMessages.count, 0)
        XCTAssertEqual(message.deliveryState, ZMDeliveryState.sent)

        let fromClient = user1!.clients.anyObject() as! MockUserClient
        let toClient = selfUser!.clients.anyObject() as! MockUserClient
        let confirmationMessage = ZMGenericMessage.message(content: ZMConfirmation.confirm(messageId: message.nonce!))

        let convObserver = ConversationChangeObserver(conversation: conversation)

        let messageObserver = MessageChangeObserver(message: message)

        // when
        mockTransportSession?.performRemoteChanges { session in
            self.selfToUser1Conversation?.encryptAndInsertData(from: fromClient, to: toClient, data: confirmationMessage.data())
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.1))

        // then
        if convObserver!.notifications.count > 0 {
            return XCTFail()
        }
        guard let messageChangeInfo = messageObserver?.notifications.firstObject  as? MessageChangeInfo else {
            return XCTFail()
        }
        XCTAssertTrue(messageChangeInfo.deliveryStateChanged)
    }
}

