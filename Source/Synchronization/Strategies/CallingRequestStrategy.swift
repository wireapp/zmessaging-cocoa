//
//  CallingRequestStrategy.swift
//  zmessaging-cocoa
//
//  Created by Jacob on 06/11/16.
//  Copyright © 2016 Zeta Project Gmbh. All rights reserved.
//

import Foundation

@objc public final class CallingRequestStrategy : NSObject {
    
    let callCenter : WireCallCenter
    var messages : [ZMClientMessage] = []
    
    init(callCenter: WireCallCenter) {
        self.callCenter = callCenter
        
        super.init()
    }
}

//extension CallingRequestStrategy : RequestStrategy, ZMSingleRequestTranscoder, WireCallCenterTransport {
//    
//    func send(data: Data, conversation: NSUUID, userId: NSUUID) {
//        
//    
//        let bu = ZMClientMessage(
//        
//        
//        let builder = ZMCallingBuilder()
//        builder.setContent(String(data: data, encoding: .utf8))
//        builder.build()
//    }
//    
//    
//    
//}
