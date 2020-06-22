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
            let textMessage = GenericMessage(content: Text(content: "Hello"))
            let conversation = self.conversation(for: selfToUser1Conversation!)
            
            let requestPath = "/conversations/\(conversation!.remoteIdentifier!.transportString())/otr/messages"
            
            // expect
            mockTransportSession?.responseGeneratorBlock = { request in
                if (request.path == requestPath) {
                    guard let hiddenMessage = conversation?.hiddenMessages.first as? ZMClientMessage,
                        let message = conversation?.lastMessage as? ZMClientMessage
                        else {
                            XCTFail("Did not insert confirmation message.")
                            return nil
                    }
                    XCTAssertTrue(hiddenMessage.underlyingMessage!.hasConfirmation)
                    XCTAssertEqual(hiddenMessage.underlyingMessage!.confirmation.firstMessageID, message.nonce!.transportString())
                }
                return nil
            }
            
            // when
            mockTransportSession?.performRemoteChanges { session in
                do {
                    self.selfToUser1Conversation?.encryptAndInsertData(from: fromClient, to: toClient, data: try textMessage.serializedData())
                } catch {
                    XCTFail()
                }
            }
            XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.1))
            
            // then
            XCTAssertEqual(conversation?.allMessages.count, 2) // system message & inserted message
            
            guard let request = mockTransportSession?.receivedRequests().last else {return XCTFail()}
            XCTAssertEqual((request as AnyObject).path, requestPath)
            
            XCTAssertEqual(conversation?.lastModifiedDate, conversation?.lastMessage?.serverTimestamp)
        }
    }
    
    func testThatItSetsAMessageToDeliveredWhenReceivingNewMessagesInAOneOnOneConversation() {
        if (BackgroundAPNSConfirmationStatus.sendDeliveryReceipts) {
            // given
            
            XCTAssert(login())
            
            let fromClient = user1?.clients.anyObject() as! MockUserClient
            let toClient = selfUser?.clients.anyObject() as! MockUserClient
            let conversation = self.conversation(for: selfToUser1Conversation!)
            let requestPath = "/conversations/\(conversation!.remoteIdentifier!.transportString())/otr/messages"
            
            
            // expect
            mockTransportSession?.responseGeneratorBlock = { request in
                if (request.path == requestPath) {

                    guard let conversation = conversation, let hiddenMessage = conversation.hiddenMessages.first(where: { (item) -> Bool in
                            return (item as? ZMClientMessage)?.underlyingMessage!.confirmation.moreMessageIds != nil
                    }) as? ZMClientMessage else { return nil }
                    
                    var nonces = Set(conversation.allMessages.compactMap { $0.nonce?.transportString() })
                    XCTAssertTrue(hiddenMessage.underlyingMessage!.hasConfirmation)
                    XCTAssertNotNil(nonces.remove(hiddenMessage.underlyingMessage!.confirmation.firstMessageID))
                    XCTAssertNotNil(hiddenMessage.underlyingMessage!.confirmation.moreMessageIds)
                    let moreMessageIds = Set(hiddenMessage.underlyingMessage!.confirmation.moreMessageIds)
                    XCTAssertTrue(moreMessageIds.isSubset(of: nonces))
                    
                }
                return nil
            }
            
            // when
            performIgnoringZMLogError {
             
                self.mockTransportSession?.performRemoteChanges { session in
                    do {
                        session.simulatePushChannelClosed()
                        let textMessage1 = GenericMessage(content: Text(content: "Hello!"), nonce: UUID())
                        self.selfToUser1Conversation?.encryptAndInsertData(from: fromClient, to: toClient, data: try textMessage1.serializedData())
                        self.spinMainQueue(withTimeout: 0.2)
                        let textMessage2 = GenericMessage(content: Text(content: "It's me!"), nonce: UUID())
                        self.selfToUser1Conversation?.encryptAndInsertData(from: fromClient, to: toClient, data: try textMessage2.serializedData())
                        session.simulatePushChannelOpened()
                    }
                    catch {
                        XCTFail()
                    }
                }
                XCTAssert(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
            }
            
            // then
            XCTAssertEqual(conversation?.allMessages.count, 3) // system message & inserted message
            
            guard let request = mockTransportSession?.receivedRequests().last else {return XCTFail()}
            XCTAssertEqual((request as AnyObject).path, requestPath)
            
            // We should confirm all message deliveries with one message
            XCTAssertEqual(mockTransportSession.receivedRequests().filter({ $0.method == ZMTransportRequestMethod.methodPOST && $0.path.contains("conversations/")}).count, 1)
            
            XCTAssertEqual(conversation?.lastModifiedDate, conversation?.lastMessage?.serverTimestamp)
        }
    }
    
    func testThatItSetsAMessageToDeliveredWhenReceivingAConfirmationMessageInAOneOnOneConversation() {
        if (BackgroundAPNSConfirmationStatus.sendDeliveryReceipts) {
            
            // given
            XCTAssert(login())
            
            let conversation = self.conversation(for: selfToUser1Conversation!)
            var message : ZMClientMessage!
            self.userSession?.perform {
                message = conversation?.append(text: "Hello") as? ZMClientMessage
            }
            XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.1))
            XCTAssertEqual(message.deliveryState, ZMDeliveryState.sent)
            
            let fromClient = user1?.clients.anyObject() as! MockUserClient
            let toClient = selfUser?.clients.anyObject() as! MockUserClient
            let confirmationMessage = GenericMessage(content: Confirmation(messageId: message.nonce!))
            
            // when
            mockTransportSession?.performRemoteChanges { session in
                do {
                    self.selfToUser1Conversation?.encryptAndInsertData(from: fromClient, to: toClient, data: try confirmationMessage.serializedData())
                } catch {
                    XCTFail()
                }
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
        self.userSession?.perform {
            message = conversation?.append(text: "Hello") as? ZMClientMessage
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.1))
        XCTAssertEqual(conversation?.hiddenMessages.count, 0)
        XCTAssertEqual(message.deliveryState, ZMDeliveryState.sent)

        let fromClient = user1!.clients.anyObject() as! MockUserClient
        let toClient = selfUser!.clients.anyObject() as! MockUserClient
        let confirmationMessage = GenericMessage(content: Confirmation(messageId: message.nonce!, type: .init()))

        let convObserver = ConversationChangeObserver(conversation: conversation)

        let messageObserver = MessageChangeObserver(message: message)

        // when
        mockTransportSession?.performRemoteChanges { session in
            do {
                self.selfToUser1Conversation?.encryptAndInsertData(from: fromClient, to: toClient, data: try confirmationMessage.serializedData())
            } catch {
                XCTFail()
            }
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

