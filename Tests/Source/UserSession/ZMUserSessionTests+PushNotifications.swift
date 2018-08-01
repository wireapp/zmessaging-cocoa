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

    func testThatItCallsShowConversationList_ForPushNotificationCategoryConversationWithoutConversation() {
        // given
        let recorder = RequestToOpenViewsRecorder()
        let notification = UILocalNotification()
        notification.category = WireSyncEngine.PushNotificationCategory.conversation.rawValue
        sut.requestToOpenViewDelegate = recorder
        application.setInactive()
        
        // when
        sut.handleAction(application: application, with: nil, for: notification, with: [:]) {}
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        sut.didFinishSync()
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(recorder.lastRequestToShowConversationsList, sut)
    }
    
    func testThatItCallsShowConversationList_ForPushNotificationCategoryConnect() {
        // given
        let sender = ZMUser.insertNewObject(in: uiMOC)
        sender.remoteIdentifier = UUID()
        let recorder = RequestToOpenViewsRecorder()
        let notification = notificationWithConnectionRequest(from: sender)
        sut.requestToOpenViewDelegate = recorder
        application.setInactive()
        
        
        // when
        handleNotification(notification, conversationAction: nil)
        
        // then
        XCTAssertEqual(recorder.lastRequestToShowConversation?.0, sut)
        XCTAssertEqual(recorder.lastRequestToShowConversation?.1.remoteIdentifier, notification.zm_conversationRemoteID)
        XCTAssertFalse(sender.isConnected)
    }
    
    func testThatItCallsShowConversationListAndConnects_ForPushNotificationCategoryConnectWithAcceptAction() {
        // given
        let sender = ZMUser.insertNewObject(in: uiMOC)
        sender.remoteIdentifier = UUID()
        let recorder = RequestToOpenViewsRecorder()
        let notification = notificationWithConnectionRequest(from: sender)
        sut.requestToOpenViewDelegate = recorder
        application.setInactive()
        
        
        // when
        handleNotification(notification, conversationAction: .connect)
        
        // then
        XCTAssertEqual(recorder.lastRequestToShowConversation?.0, sut)
        XCTAssertEqual(recorder.lastRequestToShowConversation?.1.remoteIdentifier, notification.zm_conversationRemoteID)
        XCTAssertTrue(sender.isConnected)
    }
    
    func testThatItMutesAndDoesNotShowConversation_ForPushNotificationCategoryConversationWithMuteAction() {
        
        // given
        let recorder = RequestToOpenViewsRecorder()
        let notification = notificationWithConveration(for: .conversation)
        let conversation = notification.conversation(in: uiMOC)!
        simulateLoggedInUser()
        
        // when
        handleNotification(notification, conversationAction: .mute)
        
        // then
        XCTAssertNil(recorder.lastRequestToShowConversation)
        XCTAssertTrue(conversation.isSilenced)
    }
    
    func testThatItAddsLike_ForPushNotificationCategoryConversationWithLikeAction() {
        // given
        let notification = notificationWithConveration(for: .conversation, hasMessage: true)
        let conversation = notification.conversation(in: uiMOC)!
        simulateLoggedInUser()
        sut.operationStatus.isInBackground = true
        
        // when
        handleNotification(notification, conversationAction: .like)
        
        // then
        let lastMessage = conversation.messages.lastObject as? ZMMessage
        XCTAssertEqual(lastMessage?.reactions.count, 1)
    }
    
    func testThatItCallsShowConversation_ForPushNotificationCategoryConversation() {
        // given
        let recorder = RequestToOpenViewsRecorder()
        let notification = notificationWithConveration(for: .conversation)
        sut.requestToOpenViewDelegate = recorder
        application.setInactive()
        
        // when
        handleNotification(notification, conversationAction: nil)
        
        // then
        XCTAssertEqual(recorder.lastRequestToShowConversation?.0, sut)
        XCTAssertEqual(recorder.lastRequestToShowConversation?.1.remoteIdentifier, notification.zm_conversationRemoteID)
    }
    
    func testThatItCallsShowConversationAndAcceptsCall_ForPushNotificationCategoryIncomingCallWithAcceptAction() {
        // given
        simulateLoggedInUser()
        createSelfClient()
        application.setInactive()
        let recorder = RequestToOpenViewsRecorder()
        let callCenter = createCallCenter()
        let notification = notificationWithConveration(for: .incomingCall)
        let conversation = notification.conversation(in: uiMOC)!
        simulateIncomingCall(fromUser: conversation.connectedUser!, conversation: conversation)
        sut.requestToOpenViewDelegate = recorder
        
        // when
        handleNotification(notification, callAction: .accept)
        
        // then
        XCTAssertTrue(callCenter.didCallAnswerCall);
        XCTAssertEqual(recorder.lastRequestToShowConversation?.0, sut)
        XCTAssertEqual(recorder.lastRequestToShowConversation?.1.remoteIdentifier, notification.zm_conversationRemoteID)
    }
    
    func testThatItDoesNotCallsShowConversationAndRejectsCall_ForPushNotificationCategoryIncomingCallWithIgnoreAction() {
        // given
        simulateLoggedInUser()
        createSelfClient()
        application.setInactive()
        let recorder = RequestToOpenViewsRecorder()
        let callCenter = createCallCenter()
        let notification = notificationWithConveration(for: .incomingCall)
        let conversation = notification.conversation(in: uiMOC)!
        simulateIncomingCall(fromUser: conversation.connectedUser!, conversation: conversation)
        sut.requestToOpenViewDelegate = recorder
        
        // when
        handleNotification(notification, callAction: .ignore)
        
        // then
        XCTAssertTrue(callCenter.didCallRejectCall);
        XCTAssertNil(recorder.lastRequestToShowConversation)
    }
    
    func testThatItCallsShowConversationButDoesNotCallBack_ForPushNotificationCategoryMissedCallWithCallBackAction() {
        // given
        simulateLoggedInUser()
        createSelfClient()
        application.setInactive()
        let recorder = RequestToOpenViewsRecorder()
        let callCenter = createCallCenter()
        let notification = notificationWithConveration(for: .missedCall)
        sut.requestToOpenViewDelegate = recorder
        
        // when
        handleNotification(notification, callAction: .callBack)
        
        // then
        XCTAssertFalse(callCenter.didCallStartCall);
        XCTAssertEqual(recorder.lastRequestToShowConversation?.0, sut)
        XCTAssertEqual(recorder.lastRequestToShowConversation?.1.remoteIdentifier, notification.zm_conversationRemoteID)
    }
    
    func testThatItDoesNotCallShowConversationAndAppendsAMessage_ForPushNotificationCategoryConversationWithDirectReplyAction() {
        // given
        simulateLoggedInUser()
        sut.operationStatus.isInBackground = true
        let recorder = RequestToOpenViewsRecorder()
        let notification = notificationWithConveration(for: .conversation)
        let conversation = notification.conversation(in: uiMOC)!
        let responseInfo = [UIUserNotificationActionResponseTypedTextKey : "Hello World"]
        sut.requestToOpenViewDelegate = recorder
        
        // when
        handleNotification(notification, conversationAction: .reply, responseInfo: responseInfo)
        
        // then
        XCTAssertEqual(conversation.messages.count, 1);
        XCTAssertNil(recorder.lastRequestToShowConversation)
    }
    
    func testThatOnLaunchItCallsShowConversationList_ForPushNotificationCategoryConversationWithoutConversation() {
        // given
        simulateLoggedInUser()
        let recorder = RequestToOpenViewsRecorder()
        let notification = UILocalNotification()
        notification.category = WireSyncEngine.PushNotificationCategory.conversation.rawValue
        application.setInactive()
        sut.requestToOpenViewDelegate = recorder
        
        // when
        sut.application(application, didFinishLaunchingWithOptions: [UIApplicationLaunchOptionsKey.localNotification: notification])
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        sut.didFinishSync()
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(recorder.lastRequestToShowConversationsList, sut)
    }

    func testThatOnLaunchItCallsShowConversationConversation_ForPushNotificationCategoryConversation() {
        // given
        simulateLoggedInUser()
        let recorder = RequestToOpenViewsRecorder()
        let notification = notificationWithConveration(for: .conversation)
        application.setInactive()
        sut.requestToOpenViewDelegate = recorder
        
        // when
        sut.application(application, didFinishLaunchingWithOptions: [UIApplicationLaunchOptionsKey.localNotification: notification])
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        sut.didFinishSync()
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(recorder.lastRequestToShowConversation?.0, sut)
        XCTAssertEqual(recorder.lastRequestToShowConversation?.1.remoteIdentifier, notification.zm_conversationRemoteID)
    }
    
}

extension ZMUserSessionTests_PushNotifications {
    
    func handleNotification(_ notification: UILocalNotification, conversationAction: WireSyncEngine.PushNotificationCategory.ConversationAction?, responseInfo: [AnyHashable : Any] = [:]) {
        sut.handleAction(application: application, with: conversationAction?.rawValue, for: notification, with: responseInfo) {}
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        sut.didFinishSync()
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    }
    
    func handleNotification(_ notification: UILocalNotification, callAction: WireSyncEngine.PushNotificationCategory.CallAction?) {
        sut.handleAction(application: application, with: callAction?.rawValue, for: notification, with: [:]) {}
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        sut.didFinishSync()
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    }
    
    func notificationWithConveration(for category: WireSyncEngine.PushNotificationCategory, hasMessage: Bool = false) -> UILocalNotification {
        
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
                let message = conversation.appendMessage(withText: "123") as? ZMClientMessage
                message?.markAsSent()
                messageNonce = message?.nonce
            }
            
            self.syncMOC.saveOrRollback()
        }
        
        let notification = UILocalNotification()
        notification.category = category.rawValue
        notification.userInfo = ["conversationIDString" : conversationId.transportString()]
        
        if hasMessage {
            notification.userInfo?["messageNonceString"] = messageNonce?.transportString()
        }
        
        return notification
    }
    
    func notificationWithConnectionRequest(from sender: ZMUser) -> UILocalNotification {
        let conversation = ZMConversation.insertNewObject(in: uiMOC)
        conversation.conversationType = .connection
        conversation.remoteIdentifier = UUID()
        
        let connection = ZMConnection.insertNewObject(in: uiMOC)
        connection.conversation = conversation
        connection.to = sender
        connection.status = .pending
        
        uiMOC.saveOrRollback()
        
        let notification = UILocalNotification()
        notification.category = WireSyncEngine.PushNotificationCategory.connect.rawValue
        notification.userInfo = ["conversationIDString" : conversation.remoteIdentifier!.transportString(),
                                 "senderIDString" : sender.remoteIdentifier.transportString()]
        
        return notification
    }
    
}
