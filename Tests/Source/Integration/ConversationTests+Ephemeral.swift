//
//  ConversationTests+Ephemeral.swift
//  zmessaging-cocoa
//
//  Created by Sabine Geithner on 04/10/16.
//  Copyright © 2016 Zeta Project Gmbh. All rights reserved.
//

import Foundation


class ConversationTests_Ephemeral : ConversationTestsBase {
    
    override func tearDown(){
        syncMOC.performGroupedBlockAndWait {
            self.syncMOC.zm_teardownMessageObfuscationTimer()
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        uiMOC.performGroupedBlockAndWait {
            self.uiMOC.zm_teardownMessageDeletionTimer()
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        super.tearDown()
    }
    
    var obfuscationTimer : ZMMessageDestructionTimer {
        return syncMOC.zm_messageObfuscationTimer
    }
    
    var deletionTimer : ZMMessageDestructionTimer {
        return uiMOC.zm_messageDeletionTimer
    }
}

extension ConversationTests_Ephemeral {

    func testThatItCreatesAndSendsAnEphemeralMessage(){
        // given
        XCTAssertTrue(logInAndWaitForSyncToBeComplete())
        
        let conversation = self.conversation(for: selfToUser1Conversation)!
        self.userSession.performChanges{
            _ = conversation.appendMessage(withText: "Hello") as! ZMClientMessage
        }
        XCTAssertTrue(waitForEverythingToBeDone())
        mockTransportSession.resetReceivedRequests()
        
        // when
        conversation.messageDestructionTimeout = 100
        var message : ZMClientMessage!
        self.userSession.performChanges{
            message = conversation.appendMessage(withText: "Hello") as! ZMClientMessage
            XCTAssertTrue(message.isEphemeral)
        }
        XCTAssertTrue(waitForEverythingToBeDone())

        // then
        XCTAssertEqual(mockTransportSession.receivedRequests().count, 1)
        XCTAssertEqual(message.deliveryState, ZMDeliveryState.sent)
        XCTAssertTrue(message.isEphemeral)
        XCTAssertEqual(obfuscationTimer.runningTimersCount, 1)
        XCTAssertEqual(deletionTimer.runningTimersCount, 0)
    }
    
    func testThatItDeletesAnEphemeralMessage(){
        // given
        XCTAssertTrue(logInAndWaitForSyncToBeComplete())
        
        let conversation = self.conversation(for: selfToUser1Conversation)!
        let messageCount = conversation.messages.count

        // insert ephemeral message
        conversation.messageDestructionTimeout = 0.1
        var ephemeral : ZMClientMessage!
        self.userSession.performChanges{
            ephemeral = conversation.appendMessage(withText: "Hello") as! ZMClientMessage
        }
        XCTAssertTrue(waitForEverythingToBeDone())
        spinMainQueue(withTimeout: 0.5)
        XCTAssertTrue(ephemeral.isObfuscated)
        XCTAssertEqual(conversation.messages.count, messageCount+1)

        // when
        // other client deletes ephemeral message
        let fromClient = user1.clients.anyObject() as! MockUserClient
        let toClient = selfUser.clients.anyObject() as! MockUserClient
        let deleteMessage = ZMGenericMessage(deleteMessage: ephemeral.nonce.transportString(), nonce:UUID.create().transportString())
        
        mockTransportSession.performRemoteChanges { session in
            self.selfToUser1Conversation.encryptAndInsertData(from: fromClient, to: toClient, data: deleteMessage.data())
        }
        XCTAssertTrue(waitForEverythingToBeDone())
        
        // then
        XCTAssertNotEqual(ephemeral.visibleInConversation, conversation)
        XCTAssertEqual(ephemeral.hiddenInConversation, conversation)
        XCTAssertNil(ephemeral.sender)
        XCTAssertEqual(conversation.messages.count, messageCount)
    }
    
    func remotelyInsertEphemeralMessage(conversation: MockConversation) {
        let fromClient = user1.clients.anyObject() as! MockUserClient
        let toClient = selfUser.clients.anyObject() as! MockUserClient
        let text = ZMText(message: "foo", linkPreview: nil)!
        let genericMessage = ZMGenericMessage.genericMessage(pbMessage: text, messageID:UUID.create().transportString(), expiresAfter: NSNumber(value:0.1))
        XCTAssertEqual(genericMessage.ephemeral.expireAfterMillis, 100)
        XCTAssertTrue(genericMessage.hasEphemeral())
        
        mockTransportSession.performRemoteChanges { session in
            conversation.encryptAndInsertData(from: fromClient, to: toClient, data: genericMessage.data())
        }
        XCTAssertTrue(waitForEverythingToBeDone())
    }
    
    func testThatItSendsADeletionMessageForAnEphemeralMessageWhenTheTimerFinishes(){
        // given
        XCTAssertTrue(logInAndWaitForSyncToBeComplete())
        
        let conversation = self.conversation(for: selfToUser1Conversation)!
        let messageCount = conversation.messages.count

        // the other  user inserts an ephemeral message
        remotelyInsertEphemeralMessage(conversation: selfToUser1Conversation)
        guard let ephemeral = conversation.messages.lastObject as? ZMClientMessage,
              let genMessage = ephemeral.genericMessage, genMessage.hasEphemeral()
        else {
            return XCTFail()
        }
        XCTAssertEqual(genMessage.ephemeral.expireAfterMillis, 100)
        XCTAssertEqual(conversation.messages.count, messageCount+1)
        mockTransportSession.resetReceivedRequests()
        
        // when
        // we start the destruction timer
        self.userSession.performChanges{
            ephemeral.startDestructionIfNeeded()
        }
        XCTAssertTrue(waitForEverythingToBeDone())
        spinMainQueue(withTimeout:0.5)
        
        // then
        XCTAssertEqual(mockTransportSession.receivedRequests().count, 1)
        XCTAssertEqual(conversation.messages.count, messageCount)

        // the ephemeral message is hidden
        XCTAssertNotEqual(ephemeral.visibleInConversation, conversation)
        XCTAssertEqual(ephemeral.hiddenInConversation, conversation)
        XCTAssertNil(ephemeral.sender)

        guard let delete = conversation.hiddenMessages.firstObject as? ZMClientMessage,
              let deleteMessage = delete.genericMessage, deleteMessage.hasDeleted(),
              deleteMessage.deleted.messageId == ephemeral.nonce.transportString()
        else {
            return XCTFail()
        }
    }
    
    func testThatItSendsANotificationThatTheMessageWasObfuscatedWhenTheTimerRunsOut() {
        // given
        XCTAssertTrue(logInAndWaitForSyncToBeComplete())
        
        let conversation = self.conversation(for: selfToUser1Conversation)!
        
        // when
        conversation.messageDestructionTimeout = 1.0
        var ephemeral : ZMClientMessage!
        self.userSession.performChanges{
            ephemeral = conversation.appendMessage(withText: "Hello") as! ZMClientMessage
        }
        XCTAssertTrue(waitForEverythingToBeDone())

        let messageObserver = MessageChangeObserver(message: ephemeral)!
        spinMainQueue(withTimeout: 1.1)
        
        // then
        XCTAssertTrue(ephemeral.isObfuscated)
        guard let messageChangeInfo = messageObserver.notifications.firstObject  as? MessageChangeInfo else {
            return XCTFail()
        }
        XCTAssertTrue(messageChangeInfo.isObfuscatedChanged)
        messageObserver.tearDown()
    }
    
}
