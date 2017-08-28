//
// Wire
// Copyright (C) 2017 Wire Swiss GmbH
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
import avs

@objc
public protocol FlowManagerDelegate : class {
    
    func flowManagerDidRequestCallConfig(context: UnsafeRawPointer)
    func flowManagerDidUpdateVolume(_ volume: Double, for participantId: String, in conversationId : UUID)
    
}

@objc
public protocol FlowManagerType {
    
    var delegate : FlowManagerDelegate? { get set }
    
    @objc(reportCallConfig:httpStatus:context:)
    func report(callConfig: Data?, httpStatus: Int, context : UnsafeRawPointer)
    func setVideoCaptureDevice(_ device : CaptureDevice, for conversationId: UUID)
    func reportNetworkChanged()
    func appendLog(for conversationId : UUID, message : String)
}

@objc
public class FlowManager : NSObject, FlowManagerType {
    
    public weak var delegate: FlowManagerDelegate? {
        didSet {
            guard avsFlowManager == nil else { return }
            avsFlowManager = AVSFlowManager(delegate: self, mediaManager: mediaManager)
            NotificationCenter.default.post(name: Notification.Name.ZMFlowManagerDidBecomeAvailable, object: self)
        }
    }
    fileprivate var mediaManager : AVSMediaManager?
    fileprivate var avsFlowManager : AVSFlowManager?

    init(mediaManager: AVSMediaManager) {
        super.init()
        
        self.mediaManager = mediaManager
    }
    
    @objc(reportCallConfig:httpStatus:context:)
    public func report(callConfig: Data?, httpStatus: Int, context : UnsafeRawPointer) {
        avsFlowManager?.processResponse(withStatus: Int32(httpStatus), reason: "", mediaType: "application/json", content: callConfig, context: context)
    }
    
    public func reportNetworkChanged() {
        avsFlowManager?.networkChanged()
    }
    
    public func setVideoCaptureDevice(_ device : CaptureDevice, for conversationId: UUID) {
        avsFlowManager?.setVideoCaptureDevice(device.deviceIdentifier, forConversation: conversationId.transportString())
    }
    
    public func appendLog(for conversationId : UUID, message : String) {
        avsFlowManager?.appendLog(forConversation: conversationId.transportString(), message: message)
    }

}

extension FlowManager : AVSFlowManagerDelegate {
    
    
    public static func logMessage(_ msg: String!) {
        
    }
    
    public func request(withPath path: String!, method: String!, mediaType mtype: String!, content: Data!, context ctx: UnsafeRawPointer!) -> Bool {
        if let delegate = delegate {
            delegate.flowManagerDidRequestCallConfig(context: ctx)
            return true
        } else {
            return false
        }
    }
    
    public func didEstablishMedia(inConversation convid: String!) {
        
    }
    
    public func didEstablishMedia(inConversation convid: String!, forUser userid: String!) {
        
    }
    
    public func setFlowManagerActivityState(_ activityState: AVSFlowActivityState) {
        
    }
    
    public func networkQuality(_ q: Float, conversation convid: String!) {
        
    }
    
    public func mediaWarning(onConversation convId: String!) {
        
    }
    
    public func errorHandler(_ err: Int32, conversationId convid: String!, context ctx: UnsafeRawPointer!) {
        
    }
    
    public func didUpdateVolume(_ volume: Double, conversationId convid: String!, participantId: String!) {
        guard let conversationId = UUID(uuidString: convid)  else { return }
        delegate?.flowManagerDidUpdateVolume(volume, for: participantId, in: conversationId)
    }
    
}
