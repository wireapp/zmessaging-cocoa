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
        managedObjectContext.userInfo["callingStrategy"] = self
    }
    
    deinit {
        print("JCVDay: deinitialisation CallingRequestStrategy")
    }
}

extension CallingRequestStrategy : WireCallCenterTransport {
    
    public func send(data: Data, conversationId: NSUUID, userId: NSUUID) {
        
        let dataString = data.base64String()
        
        self.managedObjectContext.performGroupedBlock { [unowned self] in
            if let conversation = ZMConversation(remoteID: UUID(uuidString: conversationId.uuidString)!, createIfNeeded: false, in: self.managedObjectContext) {
                _ = conversation.appendCallingMessage(content: dataString)
                
            }
            self.managedObjectContext.saveOrRollback()
        }
        
    }
}

extension CallingRequestStrategy : CallingMessageReceptionDelegate {
    
    public func didReceiveMessage(withContent content: String, atServerTimestamp serverTimeStamp: Date, in conversation: ZMConversation, userID: String, clientID: String) {
        
        guard let data = Data(base64Encoded: content),
              let conversationID = NSUUID(uuidString:conversation.remoteIdentifier!.uuidString)
            else {
            fatal("NOOOO")
        }
        
        self.callCenter.received(data:data, currentTimestamp:Date(), serverTimestamp: serverTimeStamp, conversationId: conversationID, userId: userID, clientId: clientID)
    }

}
