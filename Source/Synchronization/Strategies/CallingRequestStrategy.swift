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


@objc public final class CallingRequestStrategy : NSObject, RequestStrategy {
    
    fileprivate let zmLog = ZMSLog(tag: "calling")
    fileprivate var callCenter              : WireCallCenter?
    fileprivate let managedObjectContext    : NSManagedObjectContext
    
    public init(managedObjectContext: NSManagedObjectContext) {
        self.managedObjectContext = managedObjectContext
        
        super.init()
        
        let selfUser = ZMUser.selfUser(in: managedObjectContext)
        
        if let userId = selfUser.remoteIdentifier?.transportString(), let clientId = selfUser.selfClient()?.remoteIdentifier {
            callCenter = WireCallCenter(userId: userId, clientId: clientId)
            callCenter?.transport = self
        }
    }
    
    deinit {
        print("JCVDay: deinitialisation CallingRequestStrategy")
    }
    
    public func nextRequest() -> ZMTransportRequest? {
        return nil
    }
}

extension CallingRequestStrategy : ZMContextChangeTracker, ZMContextChangeTrackerSource {
    
    public var contextChangeTrackers: [ZMContextChangeTracker] {
        return [self]
    }
    
    public func fetchRequestForTrackedObjects() -> NSFetchRequest<NSFetchRequestResult>? {
        return nil
    }
    
    public func addTrackedObjects(_ objects: Set<NSManagedObject>) {
        // nop
    }
    
    public func objectsDidChange(_ objects: Set<NSManagedObject>) {
        guard callCenter == nil else { return }
        
        for object in objects {
            if let  userClient = object as? UserClient, userClient.isSelfClient(), let clientId = userClient.remoteIdentifier, let userId = userClient.user?.remoteIdentifier {
                callCenter = WireCallCenter(userId: userId.transportString(), clientId: clientId)
                callCenter?.transport = self
                break
            }
        }
    }
    
}

extension CallingRequestStrategy : ZMEventConsumer {
    
    public func processEvents(_ events: [ZMUpdateEvent], liveEvents: Bool, prefetchResult: ZMFetchRequestBatchResult?) {
        for event in events {
            guard event.type == .conversationOtrMessageAdd else { continue }
            
            if let genericMessage = ZMGenericMessage(from: event) {
            
                guard
                    let callingPayload = genericMessage.calling.content,
                    let encodedPayload = Data(base64Encoded: callingPayload),
                    let senderUUID = event.senderUUID(),
                    let conversationUUID = event.conversationUUID(),
                    let clientId = event.senderClientID(),
                    let eventTimestamp = event.timeStamp()
                else {
                    zmLog.error("Ignoring calling message: \(genericMessage.debugDescription)")
                    continue
                }
                
                callCenter?.received(data: encodedPayload, currentTimestamp: Date(), serverTimestamp: eventTimestamp, conversationId: conversationUUID, userId: senderUUID, clientId: clientId)
            }
        }
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
