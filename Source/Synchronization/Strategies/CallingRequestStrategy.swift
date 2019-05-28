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

import Foundation
import WireRequestStrategy
import WireDataModel

@objcMembers
public final class CallingRequestStrategy : NSObject, RequestStrategy {
    
    fileprivate let zmLog = ZMSLog(tag: "calling")
    
    fileprivate var callCenter              : WireCallCenterV3?
    fileprivate let managedObjectContext    : NSManagedObjectContext
    fileprivate let genericMessageStrategy  : GenericMessageRequestStrategy
    fileprivate let flowManager             : FlowManagerType
    fileprivate var callConfigRequestSync   : ZMSingleRequestSync! = nil
    fileprivate var callConfigCompletion    : CallConfigRequestCompletion? = nil
    fileprivate let callEventStatus         : CallEventStatus
    
    public init(managedObjectContext: NSManagedObjectContext, clientRegistrationDelegate: ClientRegistrationDelegate, flowManager: FlowManagerType, callEventStatus: CallEventStatus) {
        self.managedObjectContext = managedObjectContext
        self.genericMessageStrategy = GenericMessageRequestStrategy(context: managedObjectContext, clientRegistrationDelegate: clientRegistrationDelegate)
        self.flowManager = flowManager
        self.callEventStatus = callEventStatus
        
        super.init()
        
        let selfUser = ZMUser.selfUser(in: managedObjectContext)
        self.callConfigRequestSync = ZMSingleRequestSync(singleRequestTranscoder: self, groupQueue: self.managedObjectContext)
        
        if let userId = selfUser.remoteIdentifier, let clientId = selfUser.selfClient()?.remoteIdentifier {
            zmLog.debug("Creating callCenter from init")
            callCenter = WireCallCenterV3Factory.callCenter(withUserId: userId, clientId: clientId, uiMOC: managedObjectContext.zm_userInterface, flowManager: flowManager, analytics: managedObjectContext.analytics, transport: self)
        }
    }
    
    public func nextRequest() -> ZMTransportRequest? {
        let request = self.callConfigRequestSync.nextRequest() ?? genericMessageStrategy.nextRequest()
        
        request?.forceToVoipSession()
       
        return request
    }
    
    public func dropPendingCallMessages(for conversation: ZMConversation) {
        genericMessageStrategy.expireEntities(withDependency: conversation)
    }
    
}


extension CallingRequestStrategy : ZMSingleRequestTranscoder {
    public func request(for sync: ZMSingleRequestSync) -> ZMTransportRequest? {
        zmLog.debug("Scheduling request to '/calls/config/v2'")
        return ZMTransportRequest(path: "/calls/config/v2", method: .methodGET, binaryData: nil, type: "application/json", contentDisposition: nil, shouldCompress: true)
    }
    
    public func didReceive(_ response: ZMTransportResponse, forSingleRequest sync: ZMSingleRequestSync) {
        
        zmLog.debug("Received response for \(self): \(response)")
        if response.httpStatus == 200 {
            var payloadAsString : String? = nil
            if let payload = response.payload, let data = try? JSONSerialization.data(withJSONObject: payload, options: []) {
                payloadAsString = String(data: data, encoding: .utf8)
            }
            zmLog.debug("Callback: \(String(describing: self.callConfigCompletion))")
            self.callConfigCompletion?(payloadAsString, response.httpStatus)
            self.callConfigCompletion = nil
        }
    }
}


extension CallingRequestStrategy : ZMContextChangeTracker, ZMContextChangeTrackerSource {
    
    public var contextChangeTrackers: [ZMContextChangeTracker] {
        return [self, self.genericMessageStrategy]
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
            if let userClient = object as? UserClient, userClient.isSelfClient(), let clientId = userClient.remoteIdentifier, let userId = userClient.user?.remoteIdentifier {
                zmLog.debug("Creating callCenter")
                let uiContext = managedObjectContext.zm_userInterface!
                let analytics = managedObjectContext.analytics
                uiContext.performGroupedBlock {
                    self.callCenter = WireCallCenterV3Factory.callCenter(withUserId: userId, clientId: clientId, uiMOC: uiContext.zm_userInterface, flowManager: self.flowManager, analytics: analytics, transport: self)
                }
                break
            }
        }
    }
    
}

extension CallingRequestStrategy : ZMEventConsumer {
    
    public func processEvents(_ events: [ZMUpdateEvent], liveEvents: Bool, prefetchResult: ZMFetchRequestBatchResult?) {
        
        let serverTimeDelta = managedObjectContext.serverTimeDelta
        
        for event in events {
            guard event.type == .conversationOtrMessageAdd else { continue }
            
            if let genericMessage = ZMGenericMessage(from: event), genericMessage.hasCalling() {
                
                guard
                    let payload = genericMessage.calling.content.data(using: .utf8, allowLossyConversion: false),
                    let senderUUID = event.senderUUID(),
                    let conversationUUID = event.conversationUUID(),
                    let clientId = event.senderClientID(),
                    let eventTimestamp = event.timeStamp()
                else {
                    zmLog.error("ignoring calling message: \(genericMessage.debugDescription)")
                    continue
                }
                
                self.zmLog.debug("received calling message, timestamp \(eventTimestamp), serverTimeDelta \(serverTimeDelta)")
                
                let callEvent = CallEvent(data: payload,
                                          currentTimestamp: Date().addingTimeInterval(serverTimeDelta),
                                          serverTimestamp: eventTimestamp,
                                          conversationId: conversationUUID,
                                          userId: senderUUID,
                                          clientId: clientId)
                
                callEventStatus.scheduledCallEventForProcessing()
                
                callCenter?.processCallEvent(callEvent, completionHandler: { [weak self] in
                    self?.zmLog.debug("processed calling message")
                    self?.callEventStatus.finishedProcessingCallEvent()
                })
            }
        }
    }
    
}

extension CallingRequestStrategy : WireCallCenterTransport {
    
    public func send(data: Data, conversationId: UUID, userId: UUID, completionHandler: @escaping ((Int) -> Void)) {
        
        guard let dataString = String(data: data, encoding: .utf8) else {
            zmLog.error("Not sending calling messsage since it's not UTF-8")
            completionHandler(500)
            return
        }
        
        managedObjectContext.performGroupedBlock {
            guard let conversation = ZMConversation(remoteID: conversationId, createIfNeeded: false, in: self.managedObjectContext) else {
                self.zmLog.error("Not sending calling messsage since conversation doesn't exist")
                completionHandler(500)
                return
            }
            
            self.zmLog.debug("sending calling message")
            
            let genericMessage = ZMGenericMessage.message(content: ZMCalling.calling(message: dataString))
            
            self.genericMessageStrategy.schedule(message: genericMessage, inConversation: conversation) { (response) in
                if response.httpStatus == 201 {
                    completionHandler(response.httpStatus)
                }
            }
        }
    }
    
    public func requestCallConfig(completionHandler: @escaping CallConfigRequestCompletion) {
        self.zmLog.debug("requestCallConfig() called, moc = \(managedObjectContext)")
        managedObjectContext.performGroupedBlock { [unowned self] in
            self.zmLog.debug("requestCallConfig() on the moc queue")
            self.callConfigCompletion = completionHandler
            
            self.callConfigRequestSync.readyForNextRequestIfNotBusy()
            RequestAvailableNotification.notifyNewRequestsAvailable(nil)
        }
    }
    
}
