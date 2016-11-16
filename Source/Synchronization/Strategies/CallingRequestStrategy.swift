//
//  CallingRequestStrategy.swift
//  zmessaging-cocoa
//
//  Created by Jacob on 06/11/16.
//  Copyright © 2016 Zeta Project Gmbh. All rights reserved.
//

import Foundation
import WireMessageStrategy

extension ZMConversation {
    @objc (appendCallingMessageWithContent:)
    public func appendCallingMessage(content: String) -> ZMClientMessage {
        let genericMessage = ZMGenericMessage(callingContent: content, nonce: NSUUID().transportString())
        return self.append(genericMessage, expires: false, hidden: true)
    }
}


@objc public final class CallingRequestStrategy : NSObject {
    
    let callCenter              : WireCallCenter
    let managedObjectContext    : NSManagedObjectContext
    
    public init(callCenter: WireCallCenter, managedObjectContext: NSManagedObjectContext) {
        self.callCenter = callCenter
        self.managedObjectContext = managedObjectContext
        super.init()
    }
}

extension CallingRequestStrategy : WireCallCenterTransport {
    
    public func send(data: Data, conversationId: NSUUID, userId: NSUUID) {
        
        let dataString = String(data:data, encoding:.utf8)
        
        
        if let conversation = ZMConversation(remoteID: UUID(uuidString: conversationId.uuidString)!, createIfNeeded: false, in: self.managedObjectContext),
            let string = dataString {
            _ = conversation.appendCallingMessage(content: string)
        }
    }
}

extension CallingRequestStrategy : CallingMessageReceptionDelegate {
    
    public func didReceiveMessage(withContent content: String, atServerTimestamp serverTimeStamp: Date, in conversation: ZMConversation, userID: UUID, clientID: UUID) {
        
        guard let data = Data(base64Encoded:content, options: []),
              let conversationID = NSUUID(uuidString:conversation.remoteIdentifier!.uuidString),
            let userID = NSUUID(uuidString: userID.uuidString),
            let clientID = NSUUID(uuidString: clientID.uuidString)
            else {
            fatal("NOOOO")
        }
        
        self.callCenter.received(data:data, currentTimestamp:Date(), serverTimestamp: serverTimeStamp, conversationId: conversationID, userId: userID, clientId: clientID)
    }

}
