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
import ZMTesting

class DeleteMessagesTests: ConversationTestsBase {

    func testThatItCreatesARequestToSendADeletedMessageAndDeletesItLocallencrypty() {
        // given
        XCTAssertTrue(logInAndWaitForSyncToBeComplete())
        var message: ZMConversationMessage! = nil
        
        userSession.performChanges {
            let conversation = self.conversationForMockConversation(self.selfToUser1Conversation)
            message = conversation.appendMessageWithText("Hello")
        }
        
        XCTAssertTrue(waitForEverythingToBeDone())
        XCTAssertNotNil(message)

        // when
        mockTransportSession.resetReceivedRequests()
        userSession.performChanges {
            ZMMessage.deleteForEveryone(message)
        }
        XCTAssertTrue(waitForEverythingToBeDone())

        // then
        let requests = mockTransportSession.receivedRequests()
        XCTAssertEqual(requests.count, 1)
        guard let request = requests.first else { return XCTFail() }
        XCTAssertEqual(request.method, ZMTransportRequestMethod.MethodPOST)
        XCTAssertEqual(request.path, "/conversations/\(selfToUser1Conversation.identifier)/otr/messages")
        XCTAssertTrue(message.hasBeenDeleted)
    }

    func testThatItDeletesAMessageIfItIsDeletedRemotelyByTheSender() {
        // given
        XCTAssertTrue(logInAndWaitForSyncToBeComplete())
        
        let fromClient = user1.clients.anyObject() as! MockUserClient
        let toClient = selfUser.clients.anyObject() as! MockUserClient
        let textMessage = ZMGenericMessage(text: "Hello", nonce: NSUUID.createUUID().transportString())
        
        // when
        mockTransportSession.performRemoteChanges { session in
            self.selfToUser1Conversation.encryptAndInsertDataFromClient(fromClient, toClient: toClient, data: textMessage.data())
        }
        
        XCTAssertTrue(waitForEverythingToBeDone())
        
        // then
        let conversation = conversationForMockConversation(selfToUser1Conversation)
        let messages = conversation.messages
        XCTAssertEqual(messages.count, 2) // system message & inserted message
        guard let message = messages.lastObject as? ZMClientMessage where message.textMessageData?.messageText == "Hello" else { return XCTFail() }
        let genericMessage = ZMGenericMessage(deleteMessage: message.nonce.transportString(), nonce: NSUUID.createUUID().transportString())
        
        // when
        mockTransportSession.performRemoteChanges { session in
            self.selfToUser1Conversation.encryptAndInsertDataFromClient(fromClient, toClient: toClient, data: genericMessage.data())
        }
        
        XCTAssertTrue(waitForEverythingToBeDone())
        
        // then
        XCTAssertTrue(message.hasBeenDeleted)
        XCTAssertEqual(conversation.messages.count, 2) // 2x system message
        XCTAssertNotEqual(conversation.messages.firstObject as? ZMClientMessage, message)
        guard let systemMessage = conversation.messages.lastObject as? ZMSystemMessage else { return XCTFail() }
        XCTAssertEqual(systemMessage.systemMessageType, ZMSystemMessageType.MessageDeletedForEveryone)
    }
    
    func testThatItDoesNotDeleteAMessageIfItIsDeletedRemotelyBySomeoneElse() {
        // given
        XCTAssertTrue(logInAndWaitForSyncToBeComplete())
        
        let firstClient = user1.clients.anyObject() as! MockUserClient
        let secondClient = user2.clients.anyObject() as! MockUserClient
        let selfClient = selfUser.clients.anyObject() as! MockUserClient
        let textMessage = ZMGenericMessage(text: "Hello", nonce: NSUUID.createUUID().transportString())
        
        // when
        mockTransportSession.performRemoteChanges { session in
            self.selfToUser1Conversation.encryptAndInsertDataFromClient(firstClient, toClient: selfClient, data: textMessage.data())
        }
        
        XCTAssertTrue(waitForEverythingToBeDone())
        
        // then
        let conversation = conversationForMockConversation(selfToUser1Conversation)
        let messages = conversation.messages
        XCTAssertEqual(messages.count, 2) // system message & inserted message
        guard let message = messages.lastObject as? ZMClientMessage where message.textMessageData?.messageText == "Hello" else { return XCTFail() }
        
        let genericMessage = ZMGenericMessage(deleteMessage: message.nonce.transportString(), nonce: NSUUID.createUUID().transportString())
        
        // when
        mockTransportSession.performRemoteChanges { session in
            self.selfToUser1Conversation.encryptAndInsertDataFromClient(secondClient, toClient: selfClient, data: genericMessage.data())
        }
        
        XCTAssertTrue(waitForEverythingToBeDone())
        
        // then
        XCTAssertFalse(message.hasBeenDeleted)
        XCTAssertEqual(conversation.messages.count, 2) // system message & inserted message
        XCTAssertEqual(conversation.messages.lastObject as? ZMClientMessage, message)
    }

    func testThatItRetriesToSendADeletedMessageIfItCouldNotBeSentBefore() {
        // given
        XCTAssertTrue(logInAndWaitForSyncToBeComplete())
        var message: ZMConversationMessage! = nil
        
        userSession.performChanges {
            let conversation = self.conversationForMockConversation(self.selfToUser1Conversation)
            message = conversation.appendMessageWithText("Hello")
        }
        
        XCTAssertTrue(waitForEverythingToBeDone())
        XCTAssertNotNil(message)
        
        // when
        mockTransportSession.resetReceivedRequests()
        var requestCount = 0
        
        mockTransportSession.responseGeneratorBlock = { request in
            guard request.path == "/conversations/\(self.selfToUser1Conversation.identifier)/otr/messages" else { return nil }
            if requestCount < 4 {
                requestCount += 1
                return ZMTransportResponse(transportSessionError: .tryAgainLaterError())
            }
            
            return nil
        }
        
        userSession.performChanges {
            ZMMessage.deleteForEveryone(message)
        }
        XCTAssertTrue(waitForEverythingToBeDone())

        // then
        let requests = mockTransportSession.receivedRequests()
        XCTAssertEqual(requests.count, 5)
        XCTAssertEqual(requestCount, 4)
        guard let request = requests.last else { return XCTFail() }
        XCTAssertEqual(request.method, ZMTransportRequestMethod.MethodPOST)
        XCTAssertEqual(request.path, "/conversations/\(selfToUser1Conversation.identifier)/otr/messages")
        XCTAssertTrue(message.hasBeenDeleted)
    }
    
    func testThatItNotifiesTheObserverIfAMessageGetsDeletedRemotely() {
        // given
        XCTAssertTrue(logInAndWaitForSyncToBeComplete())
        
        let fromClient = user1.clients.anyObject() as! MockUserClient
        let toClient = selfUser.clients.anyObject() as! MockUserClient
        let textMessage = ZMGenericMessage(text: "Hello", nonce: NSUUID.createUUID().transportString())
        
        // when
        mockTransportSession.performRemoteChanges { session in
            self.selfToUser1Conversation.encryptAndInsertDataFromClient(fromClient, toClient: toClient, data: textMessage.data())
        }
        
        XCTAssertTrue(waitForEverythingToBeDone())
        let conversation = conversationForMockConversation(selfToUser1Conversation)
        let window = conversation.conversationWindowWithSize(10)
        let observer = MessageWindowChangeObserver(messageWindow: window)
        
        // then
        let messages = conversation.messages
        XCTAssertEqual(messages.count, 2) // system message & inserted message
        guard let message = messages.lastObject as? ZMClientMessage where message.textMessageData?.messageText == "Hello" else { return XCTFail() }
        let genericMessage = ZMGenericMessage(deleteMessage: message.nonce.transportString(), nonce: NSUUID.createUUID().transportString())
        
        // when
        mockTransportSession.performRemoteChanges { session in
            self.selfToUser1Conversation.encryptAndInsertDataFromClient(fromClient, toClient: toClient, data: genericMessage.data())
        }
        
        XCTAssertTrue(waitForEverythingToBeDone())
        
        // then
        XCTAssertTrue(message.hasBeenDeleted)
        XCTAssertEqual(conversation.messages.count, 2) // 2x system message
        
        XCTAssertEqual(observer.notifications.count, 1)
        guard let note = observer.notifications.firstObject as? MessageWindowChangeInfo else { return XCTFail() }
        XCTAssertEqual(note.deletedIndexes.count, 1) // Deleted the original message
        XCTAssertEqual(note.insertedIndexes.count, 1) // Inserted the system message

        observer.tearDown()
    }

}
