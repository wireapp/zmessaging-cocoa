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
        let message = GenericMessage(content: Location())
       
        // when
         let contentType = LocalNotificationContentType.typeForMessage(message, conversation: groupConversation, in: self.syncMOC)
        
        // then
        XCTAssertEqual(contentType, LocalNotificationContentType.location)
    }
    
    func testThatItCreatesACorrectLocalNotificationContentTypeForTheKnockMessage() {
        // given
        let message = GenericMessage(content: Knock())
        
        // when
        let contentType = LocalNotificationContentType.typeForMessage(message, conversation: groupConversation, in: self.syncMOC)
        
        // then
        XCTAssertEqual(contentType, LocalNotificationContentType.knock)
    }
    
//    func testThatItCreatesACorrectLocalNotificationContentTypeForTheEphemeralMessage() { //Failed ?
//        // given
//        let message = GenericMessage(content: Text(content: "Ephemeral Message"), nonce: UUID(), expiresAfter: 100)
//
//        // when
//        let contentType = LocalNotificationContentType.typeForMessage(message, conversation: groupConversation, in: self.syncMOC)
//
//        // then
//        XCTAssertEqual(contentType!, LocalNotificationContentType.ephemeral(isMention: false, isReply: false))
//    }
    
    func testThatItCreatesACorrectLocalNotificationContentTypeForTheTextMessage() {
           // given
           let message = GenericMessage(content: Text(content: "Text Message"))
           
           // when
           let contentType = LocalNotificationContentType.typeForMessage(message, conversation: groupConversation, in: self.syncMOC)
           
           // then
           XCTAssertEqual(contentType, LocalNotificationContentType.text("Text Message", isMention: false, isReply: false))
       }
    
    func testThatItCreatesACorrectLocalNotificationContentTypeForTheAudioMessage() {
           // given
           let url = Bundle(for: LocalNotificationDispatcherTests.self).url(forResource: "video", withExtension: "mp4")
           let audioMetadata = ZMAudioMetadata(fileURL: url!, duration: 100)
           let message = GenericMessage(content: WireProtos.Asset(audioMetadata))
           
           // when
           let contentType = LocalNotificationContentType.typeForMessage(message, conversation: groupConversation, in: self.syncMOC)
           
           // then
           XCTAssertEqual(contentType, LocalNotificationContentType.audio)
       }
    
    func testThatItCreatesACorrectLocalNotificationContentTypeForTheVideoMessage() {
        // given
        let videoMetadata = ZMVideoMetadata(fileURL: self.fileURL(forResource: "video", extension: "mp4"), thumbnail: self.verySmallJPEGData())
        let message = GenericMessage(content: WireProtos.Asset(videoMetadata))
        
        // when
        let contentType = LocalNotificationContentType.typeForMessage(message, conversation: groupConversation, in: self.syncMOC)
        
        // then
        XCTAssertEqual(contentType, LocalNotificationContentType.video)
    }
    
    func testThatItCreatesACorrectLocalNotificationContentTypeForTheFileMessage() {
        // given
        let fileMetaData = createFileMetadata()
        let message = GenericMessage(content: WireProtos.Asset(fileMetaData))
        
        // when
        let contentType = LocalNotificationContentType.typeForMessage(message, conversation: groupConversation, in: self.syncMOC)
        
        // then
        XCTAssertEqual(contentType!, LocalNotificationContentType.fileUpload)
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
    
}
