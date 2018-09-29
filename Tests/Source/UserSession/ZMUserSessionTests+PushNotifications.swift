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

import XCTest
@testable import WireSyncEngine

class RequestToOpenViewsRecorder: NSObject, ZMRequestsToOpenViewsDelegate {
    
    var lastRequestToShowMessage: (ZMUserSession, ZMConversation, ZMMessage)?
    var lastRequestToShowConversation: (ZMUserSession, ZMConversation)?
    var lastRequestToShowConversationsList: ZMUserSession?
    
    func userSession(_ userSession: ZMUserSession!, show message: ZMMessage!, in conversation: ZMConversation!) {
        lastRequestToShowMessage = (userSession, conversation, message)
    }
    
    func userSession(_ userSession: ZMUserSession!, show conversation: ZMConversation!) {
        lastRequestToShowConversation = (userSession, conversation)
    }
    
    func showConversationList(for userSession: ZMUserSession!) {
        lastRequestToShowConversationsList = userSession
    }
    
}

class ZMUserSessionTests_PushNotifications: ZMUserSessionTestsBase {

    typealias Category = WireSyncEngine.PushNotificationCategory
    typealias ConversationAction = WireSyncEngine.ConversationNotificationAction
    typealias CallAction = WireSyncEngine.CallNotificationAction
    
    func testThatItCallsShowConversationList_ForPushNotificationCategoryConversationWithoutConversation() {
        // given
        let recorder = RequestToOpenViewsRecorder()
        sut.requestToOpenViewDelegate = recorder
        
        // when
        handle(conversationAction: nil, category: .conversation, userInfo: NotificationUserInfo())
        
        // then
        XCTAssertEqual(recorder.lastRequestToShowConversationsList, sut)
    }
    
    func testThatItCallsShowConversationList_ForPushNotificationCategoryConnect() {
        // given
        let sender = ZMUser.insertNewObject(in: uiMOC)
        sender.remoteIdentifier = UUID()

        let recorder = RequestToOpenViewsRecorder()
        sut.requestToOpenViewDelegate = recorder

        let userInfo = userInfoWithConnectionRequest(from: sender)

        // when
        handle(conversationAction: nil, category: .connect, userInfo: userInfo)

        // then
        XCTAssertEqual(recorder.lastRequestToShowConversation?.0, sut)
        XCTAssertEqual(recorder.lastRequestToShowConversation?.1.remoteIdentifier, userInfo.conversationID!)
        XCTAssertFalse(sender.isConnected)
    }

    func testThatItCallsShowConversationListAndConnects_ForPushNotificationCategoryConnectWithAcceptAction() {
        // given
        let sender = ZMUser.insertNewObject(in: uiMOC)
        sender.remoteIdentifier = UUID()
        
        let recorder = RequestToOpenViewsRecorder()
        sut.requestToOpenViewDelegate = recorder

        let userInfo = userInfoWithConnectionRequest(from: sender)

        // when
        handle(conversationAction: .connect, category: .connect, userInfo: userInfo)

        // then
        XCTAssertEqual(recorder.lastRequestToShowConversation?.0, sut)
        XCTAssertEqual(recorder.lastRequestToShowConversation?.1.remoteIdentifier, userInfo.conversationID!)
        XCTAssertTrue(sender.isConnected)
    }

    func testThatItMutesAndDoesNotShowConversation_ForPushNotificationCategoryConversationWithMuteAction() {
        // given
        let recorder = RequestToOpenViewsRecorder()
        let userInfo = userInfoWithConversation()
        let conversation = userInfo.conversation(in: uiMOC)!
        simulateLoggedInUser()

        // when
        handle(conversationAction: .mute, category: .conversation, userInfo: userInfo)

        // then
        XCTAssertNil(recorder.lastRequestToShowConversation)
        XCTAssertTrue(conversation.isSilenced)
    }

    func testThatItAddsLike_ForPushNotificationCategoryConversationWithLikeAction() {
        // given
        let userInfo = userInfoWithConversation(hasMessage: true)
        let conversation = userInfo.conversation(in: uiMOC)!
        
        simulateLoggedInUser()
        sut.operationStatus.isInBackground = true

        // when
        handle(conversationAction: .like, category: .conversation, userInfo: userInfo)

        // then
        let lastMessage = conversation.messages.lastObject as? ZMMessage
        XCTAssertEqual(lastMessage?.reactions.count, 1)
    }

    func testThatItCallsShowConversation_ForPushNotificationCategoryConversation() {
        // given
        let recorder = RequestToOpenViewsRecorder()
        sut.requestToOpenViewDelegate = recorder

        let userInfo = userInfoWithConversation()

        // when
        handle(conversationAction: nil, category: .conversation, userInfo: userInfo)

        // then
        XCTAssertEqual(recorder.lastRequestToShowConversation?.0, sut)
        XCTAssertEqual(recorder.lastRequestToShowConversation?.1.remoteIdentifier, userInfo.conversationID!)
    }

    func testThatItCallsShowConversationAndAcceptsCall_ForPushNotificationCategoryIncomingCallWithAcceptAction() {
        // given
        simulateLoggedInUser()
        createSelfClient()

        let recorder = RequestToOpenViewsRecorder()
        sut.requestToOpenViewDelegate = recorder

        let userInfo = userInfoWithConversation()
        let conversation = userInfo.conversation(in: uiMOC)!

        let callCenter = createCallCenter()
        simulateIncomingCall(fromUser: conversation.connectedUser!, conversation: conversation)

        // when
        handle(callAction: .accept, category: .incomingCall, userInfo: userInfo)

        // then
        XCTAssertTrue(callCenter.didCallAnswerCall);
        XCTAssertEqual(recorder.lastRequestToShowConversation?.0, sut)
        XCTAssertEqual(recorder.lastRequestToShowConversation?.1.remoteIdentifier, userInfo.conversationID)
    }

    func testThatItDoesNotCallsShowConversationAndRejectsCall_ForPushNotificationCategoryIncomingCallWithIgnoreAction() {
        // given
        simulateLoggedInUser()
        createSelfClient()
        
        let recorder = RequestToOpenViewsRecorder()
        sut.requestToOpenViewDelegate = recorder

        let userInfo = userInfoWithConversation()
        let conversation = userInfo.conversation(in: uiMOC)!

        let callCenter = createCallCenter()
        simulateIncomingCall(fromUser: conversation.connectedUser!, conversation: conversation)

        // when
        handle(callAction: .ignore, category: .incomingCall, userInfo: userInfo)

        // then
        XCTAssertTrue(callCenter.didCallRejectCall);
        XCTAssertNil(recorder.lastRequestToShowConversation)
    }

    func testThatItCallsShowConversationButDoesNotCallBack_ForPushNotificationCategoryMissedCallWithCallBackAction() {
        // given
        simulateLoggedInUser()
        createSelfClient()
        
        let recorder = RequestToOpenViewsRecorder()
        sut.requestToOpenViewDelegate = recorder

        let userInfo = userInfoWithConversation()
        let callCenter = createCallCenter()

        // when
        handle(callAction: .callBack, category: .missedCall, userInfo: userInfo)

        // then
        XCTAssertFalse(callCenter.didCallStartCall);
        XCTAssertEqual(recorder.lastRequestToShowConversation?.0, sut)
        XCTAssertEqual(recorder.lastRequestToShowConversation?.1.remoteIdentifier, userInfo.conversationID!)
    }

    func testThatItDoesNotCallShowConversationAndAppendsAMessage_ForPushNotificationCategoryConversationWithDirectReplyAction() {
        // given
        simulateLoggedInUser()
        sut.operationStatus.isInBackground = true
        
        let recorder = RequestToOpenViewsRecorder()
        sut.requestToOpenViewDelegate = recorder

        let userInfo = userInfoWithConversation()
        let conversation = userInfo.conversation(in: uiMOC)!

        // when
        handle(conversationAction: .reply, category: .conversation, userInfo: userInfo, userText: "Hello World")

        // then
        XCTAssertEqual(conversation.messages.count, 1);
        XCTAssertNil(recorder.lastRequestToShowConversation)
    }

    func testThatOnLaunchItCallsShowConversationList_ForPushNotificationCategoryConversationWithoutConversation() {
        // given
        simulateLoggedInUser()
        let recorder = RequestToOpenViewsRecorder()
        sut.requestToOpenViewDelegate = recorder

        // when
        handle(conversationAction: nil, category: .conversation, userInfo: NotificationUserInfo())

        // then
        XCTAssertEqual(recorder.lastRequestToShowConversationsList, sut)
    }

    func testThatOnLaunchItCallsShowConversationConversation_ForPushNotificationCategoryConversation() {
        // given
        simulateLoggedInUser()
        let recorder = RequestToOpenViewsRecorder()
        sut.requestToOpenViewDelegate = recorder
        
        let userInfo = userInfoWithConversation()

        // when
        handle(conversationAction: nil, category: .conversation, userInfo: userInfo)
        
        // then
        XCTAssertEqual(recorder.lastRequestToShowConversation?.0, sut)
        XCTAssertEqual(recorder.lastRequestToShowConversation?.1.remoteIdentifier, userInfo.conversationID!)
    }
    
}

extension ZMUserSessionTests_PushNotifications {
    
    func handle(conversationAction: ConversationAction?, category: Category, userInfo: NotificationUserInfo, userText: String? = nil) {
        handle(action: conversationAction?.rawValue ?? "", category: category.rawValue, userInfo: userInfo, userText: userText)
    }
    
    func handle(callAction: CallAction, category: Category, userInfo: NotificationUserInfo) {
        handle(action: callAction.rawValue, category: category.rawValue, userInfo: userInfo)
    }
    
    func handle(action: String, category: String, userInfo: NotificationUserInfo, userText: String? = nil) {
        sut.handleNotificationResponse(actionIdentifier: action, categoryIdentifier: category, userInfo: userInfo, userText: userText) {}
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        sut.didFinishSync()
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    }
    
    func userInfoWithConversation(hasMessage: Bool = false) -> NotificationUserInfo {
        let conversationId = UUID()
        var messageNonce: UUID?
        syncMOC.performGroupedBlockAndWait {
            
            let conversation = ZMConversation.insertNewObject(in: self.syncMOC)
            conversation.conversationType = .oneOnOne
            conversation.remoteIdentifier = conversationId
            
            let sender = ZMUser.insertNewObject(in: self.syncMOC)
            sender.remoteIdentifier = UUID()
            
            let connection = ZMConnection.insertNewObject(in: self.syncMOC)
            connection.conversation = conversation
            connection.to = sender
            connection.status = .accepted
            
            if hasMessage {
                let message = conversation.append(text: "123") as? ZMClientMessage
                message?.markAsSent()
                messageNonce = message?.nonce
            }
            
            self.syncMOC.saveOrRollback()
        }
        
        let userInfo = NotificationUserInfo()
        userInfo.conversationID = conversationId
        
        if hasMessage {
            userInfo.messageNonce = messageNonce
        }
        
        return userInfo
    }
    
    func userInfoWithConnectionRequest(from sender: ZMUser) -> NotificationUserInfo {
        let conversation = ZMConversation.insertNewObject(in: uiMOC)
        conversation.conversationType = .connection
        conversation.remoteIdentifier = UUID()
        
        let connection = ZMConnection.insertNewObject(in: uiMOC)
        connection.conversation = conversation
        connection.to = sender
        connection.status = .pending
        
        uiMOC.saveOrRollback()

        let userInfo = NotificationUserInfo()
        userInfo.conversationID = conversation.remoteIdentifier
        userInfo.senderID = sender.remoteIdentifier
        
        return userInfo
    }
}
