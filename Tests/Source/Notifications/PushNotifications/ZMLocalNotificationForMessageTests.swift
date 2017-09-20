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

import WireTesting;
import WireDataModel;
@testable import WireSyncEngine



// MARK : Text Messages
class ZMLocalNotificationForMessageTests : ZMLocalNotificationForEventTest {

    
    func textNotification(_ conversation: ZMConversation, sender: ZMUser, text: String? = nil, isEphemeral: Bool = false) -> ZMLocalNotificationForMessage? {
        if isEphemeral {
            conversation.messageDestructionTimeout = 0.5
        }
        let message = conversation.appendMessage(withText: text ?? "Hello Hello!") as! ZMOTRMessage
        message.sender = sender
        conversation.lastReadServerTimeStamp = Date()
        message.serverTimestamp = conversation.lastReadServerTimeStamp!.addingTimeInterval(20)
        
        return ZMLocalNotificationForMessage(message: message, application: self.application)
    }
    
    func unknownNotification(_ conversation: ZMConversation, sender: ZMUser) -> ZMLocalNotificationForMessage? {
        
        let message = ZMClientMessage.insertNewObject(in: self.syncMOC)
        message.sender = sender;
        message.visibleInConversation = conversation
        message.nonce = UUID()
        message.serverTimestamp = conversation.lastReadServerTimeStamp!.addingTimeInterval(20)
        
        return ZMLocalNotificationForMessage(message: message, application: self.application)
    }
    
    func alertBodyForNotification(_ conversation: ZMConversation, sender: ZMUser, text: String? = nil, isEphemeral: Bool = false) -> String? {
        guard let notification = textNotification(conversation, sender: sender, text: text, isEphemeral: isEphemeral),
              let uiNote = notification.uiNotifications.first else { return nil }
        return uiNote.alertBody
    }
    
    func alertBodyForUnknownNotification(_ conversation: ZMConversation, sender: ZMUser) -> String? {
        guard let notification = unknownNotification(conversation, sender: sender),
            let uiNote = notification.uiNotifications.first else { return nil }
        return uiNote.alertBody
    }
    
    func testItCreatesMessageNotificationsCorrectly(){
        
        //    "push.notification.add.message.oneonone" = "%1$@: %2$@";
        //    "push.notification.add.message.group" = "%1$@ in %2$@: %3$@";
        //    "push.notification.add.message.group.noconversationname" = "%1$@ in a conversation: %2$@";
        
        XCTAssertEqual(alertBodyForNotification(oneOnOneConversation, sender: sender), "Super User: Hello Hello!")
        XCTAssertEqual(alertBodyForNotification(groupConversation, sender: sender), "Super User in Super Conversation: Hello Hello!")
        XCTAssertEqual(alertBodyForNotification(groupConversationWithoutName, sender: sender), "Super User in a conversation: Hello Hello!")
    }
    
    func testThatObfuscatesNotificationsForEphemeralMessages(){
        XCTAssertEqual(alertBodyForNotification(oneOnOneConversation, sender: sender, isEphemeral: true), "Someone sent you a message")
        XCTAssertEqual(alertBodyForNotification(groupConversation, sender: sender, isEphemeral: true), "Someone sent you a message")
        XCTAssertEqual(alertBodyForNotification(groupConversationWithoutName, sender: sender, isEphemeral: true), "Someone sent you a message")
    }
    
    func testThatItDuplicatesPercentageSignsInTextAndConversationName() {
        // given
        groupConversation.userDefinedName = "100% Wire"
        
        // then
        XCTAssertEqual(alertBodyForNotification(groupConversation, sender: sender, text: "Today we grew by 100%"), "Super User in 100%% Wire: Today we grew by 100%%")
    }
    
    func testThatItSavesTheSenderOfANotification() {
        // given
        let notification = textNotification(oneOnOneConversation, sender: sender)!
        let uiNote = notification.uiNotifications.first!
        
        // then
        XCTAssertEqual(notification.senderUUID, sender.remoteIdentifier);
        XCTAssertEqual(uiNote.zm_senderUUID, sender.remoteIdentifier);
    }

    
    func testThatItSavesTheConversationOfANotification() {
        // given
        let notification = textNotification(oneOnOneConversation, sender: sender)!
        let uiNote = notification.uiNotifications.first!
        
        // then
        XCTAssertEqual(notification.conversationID, oneOnOneConversation.remoteIdentifier);
        XCTAssertEqual(uiNote.zm_conversationRemoteID, oneOnOneConversation.remoteIdentifier);
    }
    
    func testThatItSavesTheMessageNonce() {
        // given
        let message = oneOnOneConversation.appendMessage(withText: "Hello Hello!") as! ZMOTRMessage
        message.sender = sender
        
        let notification = ZMLocalNotificationForMessage(message: message, application: self.application)!
        let uiNote = notification.uiNotifications.first!
        
        // then
        XCTAssertEqual(notification.messageNonce, message.nonce);
        XCTAssertEqual(uiNote.zm_messageNonce, message.nonce);
    }
    
    func testThatItDoesNotCreateANotificationWhenTheConversationIsSilenced(){
        // given
        groupConversation.isSilenced = true
        
        // when
        let notification = textNotification(groupConversation, sender: sender)
        
        // then
        XCTAssertNil(notification)
    }
    
    func testThatItCreatesPushNotificationForMessageOfUnknownType() {
        XCTAssertEqual(alertBodyForUnknownNotification(oneOnOneConversation, sender: sender), "Super User sent a message")
        XCTAssertEqual(alertBodyForUnknownNotification(groupConversation, sender: sender), "Super User sent a message in Super Conversation")
        XCTAssertEqual(alertBodyForUnknownNotification(groupConversationWithoutName, sender: sender), "Super User sent a message")
    }
}


// MARK : Image Asset Messages
extension ZMLocalNotificationForMessageTests {
    
    func imageNotification(_ conversation: ZMConversation, sender: ZMUser, text: String? = nil, isEphemeral : Bool = false) -> ZMLocalNotificationForMessage? {
        if isEphemeral {
            conversation.messageDestructionTimeout = 10
        }
        let message = conversation.appendMessage(withImageData: verySmallJPEGData()) as! ZMAssetClientMessage
        message.sender = sender
        
        return ZMLocalNotificationForMessage(message: message, application: self.application)
    }
    
    func alertBodyForImageNotification(_ conversation: ZMConversation, sender: ZMUser, text: String? = nil, isEphemeral: Bool = false) -> String? {
        guard let notification = imageNotification(conversation, sender: sender, text: text, isEphemeral: isEphemeral),
            let uiNote = notification.uiNotifications.first
        else {
            XCTFail("Failed to create notification")
            return nil
        }
        
        return uiNote.alertBody
    }
    
    
    func testItCreatesImageNotificationsCorrectly(){
        //    "push.notification.add.image.oneonone" = "%1$@ shared a picture";
        //    "push.notification.add.image.group" = "%1$@ shared a picture in %2$@";
        //    "push.notification.add.image.group.noconversationname" = "%1$@ shared a picture";
        
        XCTAssertEqual(alertBodyForImageNotification(oneOnOneConversation, sender: sender), "Super User shared a picture")
        XCTAssertEqual(alertBodyForImageNotification(groupConversation, sender: sender), "Super User shared a picture in Super Conversation")
        XCTAssertEqual(alertBodyForImageNotification(groupConversationWithoutName, sender: sender), "Super User shared a picture in a conversation")
    }
    
    func testThatObfuscatesNotificationsForEphemeralImageMessages(){
        XCTAssertEqual(alertBodyForImageNotification(oneOnOneConversation, sender: sender, isEphemeral: true), "Someone sent you a message")
        XCTAssertEqual(alertBodyForImageNotification(groupConversation, sender: sender, isEphemeral: true), "Someone sent you a message")
        XCTAssertEqual(alertBodyForImageNotification(groupConversationWithoutName, sender: sender, isEphemeral: true), "Someone sent you a message")
    }
    
}


enum FileType {
    case txt, video, audio
    
    var testURL : URL {
        var name : String
        var fileExtension : String
        switch self {
        case .txt:
            name = "Lorem Ipsum"
            fileExtension = "txt"
        case .video:
            name = "video"
            fileExtension = "mp4"
        case  .audio:
            name = "audioFile"
            fileExtension = "m4a"
        }
        return Bundle(for: ZMLocalNotificationForMessageTests.self).url(forResource: name, withExtension: fileExtension)!
    }
    
    var testData : Data {
        return try! Data(contentsOf: testURL)
    }
}

// MARK : File Asset Messages
extension ZMLocalNotificationForMessageTests {

    func messageForFile(_ mimeType: String, nonce: NSUUID){
        let dataBuilder = ZMAssetRemoteDataBuilder()
        dataBuilder.setSha256(Data.secureRandomData(length: 32))
        dataBuilder.setOtrKey(Data.secureRandomData(length: 32))

        let originalBuilder = ZMAssetOriginalBuilder()
        originalBuilder.setMimeType(mimeType)
        originalBuilder.setSize(0)

        
        let assetBuilder = ZMAssetBuilder()
        assetBuilder.setUploaded(dataBuilder.build())
        assetBuilder.setOriginal(originalBuilder.build())

        let genericAssetMessageBuilder = ZMGenericMessageBuilder()
        genericAssetMessageBuilder.setAsset(assetBuilder.build())
        genericAssetMessageBuilder.setMessageId(nonce.transportString())
    }

    
    func assetNotification(_ fileType: FileType, conversation: ZMConversation, sender: ZMUser, isEphemeral: Bool = false) -> ZMLocalNotificationForMessage? {
        let metadata = ZMFileMetadata(fileURL: fileType.testURL)
        let msg = ZMAssetClientMessage.assetClientMessage(with: metadata, nonce: UUID.create(), managedObjectContext: self.syncMOC, expiresAfter: isEphemeral ? 10 : 0)
        msg?.sender = sender
        msg?.visibleInConversation = conversation
        
        return ZMLocalNotificationForMessage(message: msg!, application: self.application)
    }
    
    func alertBodyForAssetNotification(_ fileType: FileType, conversation: ZMConversation, sender: ZMUser, isEphemeral: Bool = false) -> String? {
        guard let notification = assetNotification(fileType, conversation: conversation, sender: sender, isEphemeral: isEphemeral),
            let uiNote = notification.uiNotifications.first else { return nil }
        
        return uiNote.alertBody
    }
    
    func testThatItCreatesFileAddNotificationsCorrectly() {
        //    "push.notification.add.file.group" = "%1$@ shared a file in %2$@";
        //    "push.notification.add.file.group.noconversationname" = "%1$@ shared a file in a conversation";
        //    "push.notification.add.file.oneonone" = "%1$@ shared a file";
        //
        
        XCTAssertEqual(alertBodyForAssetNotification(.txt, conversation: oneOnOneConversation, sender: sender), "Super User shared a file")
        XCTAssertEqual(alertBodyForAssetNotification(.txt, conversation: groupConversation, sender: sender), "Super User shared a file in Super Conversation")
        XCTAssertEqual(alertBodyForAssetNotification(.txt, conversation: groupConversationWithoutName, sender: sender), "Super User shared a file in a conversation")
    }
    
    func testThatItCreatesVideoAddNotificationsCorrectly() {
        //    "push.notification.add.file.group" = "%1$@ shared a file in %2$@";
        //    "push.notification.add.file.group.noconversationname" = "%1$@ shared a file in a conversation";
        //    "push.notification.add.file.oneonone" = "%1$@ shared a file";
        //
        
        XCTAssertEqual(alertBodyForAssetNotification(.video, conversation: oneOnOneConversation, sender: sender), "Super User shared a video")
        XCTAssertEqual(alertBodyForAssetNotification(.video, conversation: groupConversation, sender: sender), "Super User shared a video in Super Conversation")
        XCTAssertEqual(alertBodyForAssetNotification(.video, conversation: groupConversationWithoutName, sender: sender), "Super User shared a video in a conversation")
    }
    
    func testThatItCreatesEphemeralFileAddNotificationsCorrectly() {
        XCTAssertEqual(alertBodyForAssetNotification(.txt, conversation: oneOnOneConversation, sender: sender, isEphemeral: true), "Someone sent you a message")
        XCTAssertEqual(alertBodyForAssetNotification(.txt, conversation: groupConversation, sender: sender, isEphemeral: true), "Someone sent you a message")
        XCTAssertEqual(alertBodyForAssetNotification(.txt, conversation: groupConversationWithoutName, sender: sender, isEphemeral: true), "Someone sent you a message")
    }
    
    func testThatItCreatesEphemeralVideoAddNotificationsCorrectly() {
        XCTAssertEqual(alertBodyForAssetNotification(.video, conversation: oneOnOneConversation, sender: sender, isEphemeral: true), "Someone sent you a message")
        XCTAssertEqual(alertBodyForAssetNotification(.video, conversation: groupConversation, sender: sender, isEphemeral: true), "Someone sent you a message")
        XCTAssertEqual(alertBodyForAssetNotification(.video, conversation: groupConversationWithoutName, sender: sender, isEphemeral: true), "Someone sent you a message")
    }
    
//    func testThatItCreatesAudioNotificationsCorrectly() {
//        //    "push.notification.add.audio.group" = "%1$@ shared an audio message in %2$@";
//        //    "push.notification.add.audio.group.noconversationname" = "%1$@ shared an audio message in a conversation";
//        //    "push.notification.add.audio.oneonone" = "%1$@ shared an audio message";
//        
//        XCTAssertEqual(alertBodyForAssetNotification(.Audio, conversation: oneOnOneConversation, sender: sender), "Super User shared an audio message")
//        XCTAssertEqual(alertBodyForAssetNotification(.Audio, conversation: groupConversation, sender: sender), "Super User shared an audio message in Super Conversation")
//        XCTAssertEqual(alertBodyForAssetNotification(.Audio, conversation: groupConversationWithoutName, sender: sender), "Super User shared an audio message in a conversation")
//    }
}


extension ZMLocalNotificationForMessageTests {

    func knockNotification(_ conversation: ZMConversation, sender: ZMUser, isEphemeral : Bool = false) -> ZMLocalNotificationForMessage? {
        if isEphemeral {
            conversation.messageDestructionTimeout = 10
        }
        let message = conversation.appendKnock() as! ZMClientMessage
        message.sender = sender
        
        return ZMLocalNotificationForMessage(message: message, application: self.application)
    }
    
    func alertBodyForKnockNotification(_ conversation: ZMConversation, sender: ZMUser, isEphemeral: Bool = false) -> String? {
        guard let notification = knockNotification(conversation, sender: sender, isEphemeral: isEphemeral),
            let uiNote = notification.uiNotifications.first else { return nil }
        
        return uiNote.alertBody
    }
    
    func testThatItCreatesKnockNotificationsCorrectly() {
        //"push.notification.knock.group" = "%1$@ pinged %3$@ times in %2$@";
        //"push.notification.knock.group.noconversationname" = "%1$@ pinged %2$@ times in a conversation";
        //"push.notification.knock.oneonone" = "%1$@ pinged you %2$@ times";
        
        XCTAssertEqual(alertBodyForKnockNotification(oneOnOneConversation, sender: sender), "Super User pinged ")
        XCTAssertEqual(alertBodyForKnockNotification(groupConversation, sender: sender), "Super User pinged in Super Conversation")
        XCTAssertEqual(alertBodyForKnockNotification(groupConversationWithoutName, sender: sender), "Super User pinged in a conversation")
    }
    
    func testThatItCreatesEphemeralKnockNotificationsCorrectly() {
        XCTAssertEqual(alertBodyForKnockNotification(oneOnOneConversation, sender: sender, isEphemeral: true), "Someone sent you a message")
        XCTAssertEqual(alertBodyForKnockNotification(groupConversation, sender: sender, isEphemeral: true), "Someone sent you a message")
        XCTAssertEqual(alertBodyForKnockNotification(groupConversationWithoutName, sender: sender, isEphemeral: true), "Someone sent you a message")
    }
    
    func testThatItCopiesKnocksCorrectly(){
        // given
        guard let notification = knockNotification(oneOnOneConversation, sender: sender) else {return XCTFail()}
        let secondKnock = oneOnOneConversation.appendKnock() as! ZMClientMessage
        secondKnock.sender = sender
        
        // when
        guard let secondNotification = notification.copyByAddingMessage(secondKnock),
              let uiNote = secondNotification.uiNotifications.last
        else { return }
        
        // then
        XCTAssertEqual(uiNote.alertBody, "Super User pinged 2 times")
    }
    
    func testItDoesNotCopyKnocksFromDifferentSenders(){
        // given
        guard let notification = knockNotification(groupConversation, sender: sender) else {return XCTFail()}
        
        // when
        let secondKnock = oneOnOneConversation.appendKnock() as! ZMClientMessage
        secondKnock.sender = otherUser
        
        // when
        let secondNotification = notification.copyByAddingMessage(secondKnock)

        // then
        XCTAssertNil(secondNotification)
    }

}


extension ZMLocalNotificationForMessageTests {

    func editNotification(_ message: ZMOTRMessage, sender: ZMUser, text: String) -> ZMLocalNotificationForMessage? {
        let editMessage = ZMOTRMessage.edit(message, newText: text)
        editMessage!.sender = sender
        return ZMLocalNotificationForMessage(message: editMessage as! ZMClientMessage, application: self.application)
    }
    
    func alertBodyForEditNotification(_ conversation: ZMConversation, sender: ZMUser, text: String) -> String? {
        let message = conversation.appendMessage(withText: "Foo") as! ZMClientMessage
        message.markAsSent()
        guard let notification = editNotification(message, sender: sender, text: text),
            let uiNote = notification.uiNotifications.first else { return nil }
        
        return uiNote.alertBody
    }
    
    
    func testThatItCreatesANotificationForAnEditMessage(){
        
        //    "push.notification.add.message.oneonone" = "%1$@: %2$@";
        //    "push.notification.add.message.group" = "%1$@ in %2$@: %3$@";
        //    "push.notification.add.message.group.noconversationname" = "%1$@ in a conversation: %2$@";
        
        XCTAssertEqual(alertBodyForEditNotification(oneOnOneConversation, sender: sender, text: "Edited Text"), "Super User: Edited Text")
        XCTAssertEqual(alertBodyForEditNotification(groupConversation, sender: sender, text: "Edited Text"), "Super User in Super Conversation: Edited Text")
        XCTAssertEqual(alertBodyForEditNotification(groupConversationWithoutName, sender: sender, text: "Edited Text"), "Super User in a conversation: Edited Text")
    }
    
}




