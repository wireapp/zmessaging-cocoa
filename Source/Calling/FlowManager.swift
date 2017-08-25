//
//  FlowManager.swift
//  WireSyncEngine
//
//  Created by Jacob on 25.08.17.
//  Copyright © 2017 Zeta Project Gmbh. All rights reserved.
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
    
    @objc(reportCallConfig:context:)
    func report(callConfig: Data, context : UnsafeRawPointer)
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
        }
    }
    fileprivate var mediaManager : AVSMediaManager?
    fileprivate var avsFlowManager : AVSFlowManager?

    init(mediaManager: AVSMediaManager) {
        super.init()
        
        self.mediaManager = mediaManager
    }
    
    @objc(reportCallConfig:context:)
    public func report(callConfig: Data, context : UnsafeRawPointer) {
        avsFlowManager?.processResponse(withStatus: 200, reason: "", mediaType: "application/json", content: callConfig, context: context)
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
