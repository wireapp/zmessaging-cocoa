//
// Wire
// Copyright (C) 2020 Wire Swiss GmbH
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

class LocalNotificationContentTypeTest: ZMLocalNotificationTests {

    func testThatItCreatesACorrectLocalNotificationContentTypeForTheLocationMessage() {
        // given
        let location = WireProtos.Location.with {
            $0.latitude = 0.0
            $0.longitude = 0.0
        }
        let message = GenericMessage(content: location)
        let event = createUpdateEvent(UUID.create(), conversationID: UUID.create(), genericMessage: message)

        // when
         let contentType = LocalNotificationContentType.typeForMessage(event, conversation: groupConversation, in: self.syncMOC)

        // then
        XCTAssertEqual(contentType, LocalNotificationContentType.location)
    }

    func testThatItCreatesACorrectLocalNotificationContentTypeForTheKnockMessage() {
        // given
        let message = GenericMessage(content: WireProtos.Knock.with { $0.hotKnock = true })
        let event = createUpdateEvent(UUID.create(), conversationID: UUID.create(), genericMessage: message)

        // when
        let contentType = LocalNotificationContentType.typeForMessage(event, conversation: groupConversation, in: self.syncMOC)

        // then
        XCTAssertEqual(contentType, LocalNotificationContentType.knock)
    }

    func testThatItCreatesACorrectLocalNotificationContentTypeForTheEphemeralMessage() {
        // given
        let message = GenericMessage(content: Text(content: "Ephemeral Message"), nonce: UUID(), expiresAfter: 100)
        let event = createUpdateEvent(UUID.create(), conversationID: UUID.create(), genericMessage: message)

        // when
        let contentType = LocalNotificationContentType.typeForMessage(event, conversation: groupConversation, in: self.syncMOC)

        // then
        XCTAssertEqual(contentType, LocalNotificationContentType.ephemeral(isMention: false, isReply: false))
    }
    
    func testThatItCreatesACorrectLocalNotificationContentTypeForTheTextMessage() {
           // given
           let message = GenericMessage(content: Text(content: "Text Message"))
           let event = createUpdateEvent(UUID.create(), conversationID: UUID.create(), genericMessage: message)

           // when
           let contentType = LocalNotificationContentType.typeForMessage(event, conversation: groupConversation, in: self.syncMOC)

           // then
           XCTAssertEqual(contentType, LocalNotificationContentType.text("Text Message", isMention: false, isReply: false))
       }

    func testThatItCreatesACorrectLocalNotificationContentTypeForTheAudioMessage() {
        // given
        let url = Bundle(for: LocalNotificationDispatcherTests.self).url(forResource: "video", withExtension: "mp4")
        let audioMetadata = ZMAudioMetadata(fileURL: url!, duration: 100)
        let message = GenericMessage(content: WireProtos.Asset(audioMetadata))
        let event = createUpdateEvent(UUID.create(), conversationID: UUID.create(), genericMessage: message)
        
        // when
        let contentType = LocalNotificationContentType.typeForMessage(event, conversation: groupConversation, in: self.syncMOC)
        
        // then
        XCTAssertEqual(contentType, LocalNotificationContentType.audio)
    }

    func testThatItCreatesACorrectLocalNotificationContentTypeForTheVideoMessage() {
        // given
        let videoMetadata = ZMVideoMetadata(fileURL: self.fileURL(forResource: "video", extension: "mp4"), thumbnail: self.verySmallJPEGData())
        let message = GenericMessage(content: WireProtos.Asset(videoMetadata))
        let event = createUpdateEvent(UUID.create(), conversationID: UUID.create(), genericMessage: message)

        // when
        let contentType = LocalNotificationContentType.typeForMessage(event, conversation: groupConversation, in: self.syncMOC)

        // then
        XCTAssertEqual(contentType, LocalNotificationContentType.video)
    }

    func testThatItCreatesACorrectLocalNotificationContentTypeForTheFileMessage() {
        // given
        let fileMetaData = createFileMetadata()
        let message = GenericMessage(content: WireProtos.Asset(fileMetaData))
        let event = createUpdateEvent(UUID.create(), conversationID: UUID.create(), genericMessage: message)

        // when
        let contentType = LocalNotificationContentType.typeForMessage(event, conversation: groupConversation, in: self.syncMOC)

        // then
        XCTAssertEqual(contentType!, LocalNotificationContentType.fileUpload)
    }
    
    func testThatItCreatesASystemMessageNotificationContentTypeForTheMemberJoinEvent() {
        // given
        let event = createMemberJoinUpdateEvent(UUID.create(), conversationID: UUID.create())

        // when
        let contentType = LocalNotificationContentType.typeForMessage(event, conversation: groupConversation, in: self.syncMOC)

        // then
        XCTAssertEqual(contentType, LocalNotificationContentType.participantsAdded)
    }

    
    func testThatItCreatesASystemMessageNotificationContentTypeForTheMemberLeaveEvent() {
        // given
        let event = createMemberLeaveUpdateEvent(UUID.create(), conversationID: UUID.create())

        // when
        let contentType = LocalNotificationContentType.typeForMessage(event, conversation: groupConversation, in: self.syncMOC)

        // then
        XCTAssertEqual(contentType, LocalNotificationContentType.participantsRemoved)
    }
    
    func testThatItCreatesASystemMessageNotificationContentTypeForTheMessageTimerUpdateEvent() {
        // given
        let event = createMessageTimerUpdateEvent(UUID.create(), conversationID: UUID.create())

        // when
        let contentType = LocalNotificationContentType.typeForMessage(event, conversation: groupConversation, in: self.syncMOC)

        // then
        XCTAssertEqual(contentType, LocalNotificationContentType.messageTimerUpdate("1 year"))
    }


    private func createFileMetadata(filename: String? = nil) -> ZMFileMetadata {
        let fileURL: URL

        if let fileName = filename {
            fileURL = testURLWithFilename(fileName)
        } else {
            fileURL = testURLWithFilename("file.dat")
        }

        _ = createTestFile(at: fileURL)

        return ZMFileMetadata(fileURL: fileURL)
    }

    private func testURLWithFilename(_ filename: String) -> URL {
        let documents = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
        let documentsURL = URL(fileURLWithPath: documents)
        return documentsURL.appendingPathComponent(filename)
    }

    private func createTestFile(at url: URL) -> Data {
        let data: Data! = "Some other data".data(using: String.Encoding.utf8)
        try! data.write(to: url, options: [])
        return data
    }
    
    private func createUpdateEvent(_ nonce: UUID, conversationID: UUID, genericMessage: GenericMessage, senderID: UUID = UUID.create()) -> ZMUpdateEvent {
           let payload : [String : Any] = [
               "id": UUID.create().transportString(),
               "conversation": conversationID.transportString(),
               "from": senderID.transportString(),
               "time": Date().transportString(),
               "data": ["text": try? genericMessage.serializedData().base64String()],
               "type": "conversation.otr-message-add"
           ]
           
           return ZMUpdateEvent(fromEventStreamPayload: payload as ZMTransportData, uuid: nonce)!
       }
    
    private func createMemberJoinUpdateEvent(_ nonce: UUID, conversationID: UUID, senderID: UUID = UUID.create()) -> ZMUpdateEvent {
        
        let user2ID = UUID.create()
        
        let payload : [String : Any] = [
            "from": senderID.transportString(),
            "conversation": conversationID.transportString(),
            "time": NSDate().transportString(),
            "data": [
                "user_ids": [user2ID.transportString()],
                "users": [[
                    "id": user2ID.transportString(),
                    "conversation_role": "wire_admin"
                    ]]
            ],
            "type": "conversation.member-join"
            ]
        return ZMUpdateEvent(fromEventStreamPayload: payload as ZMTransportData, uuid: nonce)!
    }
    
    private func createMemberLeaveUpdateEvent(_ nonce: UUID, conversationID: UUID, senderID: UUID = UUID.create()) -> ZMUpdateEvent {
        
        let user2ID = UUID.create()
        
        let payload : [String : Any] = [
            "from": senderID.transportString(),
            "conversation": conversationID.transportString(),
            "time": NSDate().transportString(),
            "data": [
                "user_ids": [user2ID.transportString()],
            ],
            "type": "conversation.member-leave"
            ]
        return ZMUpdateEvent(fromEventStreamPayload: payload as ZMTransportData, uuid: nonce)!
    }
    
    private func createMessageTimerUpdateEvent(_ nonce: UUID, conversationID: UUID, senderID: UUID = UUID.create()) -> ZMUpdateEvent {
                      
          let payload: [String: Any] = [
           "from": senderID.transportString(),
           "conversation": conversationID.transportString(),
           "time": NSDate().transportString(),
           "data": ["message_timer": 31536000000],
           "type": "conversation.message-timer-update"
           ]
           return ZMUpdateEvent(fromEventStreamPayload: payload as ZMTransportData, uuid: nonce)!
       }

}
