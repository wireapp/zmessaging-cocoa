//
//  TypingChange.swift
//  WireSyncEngine
//
//  Created by Jacob on 20.09.17.
//  Copyright © 2017 Zeta Project Gmbh. All rights reserved.
//

import Foundation

@objc
public class TypingChange : NSObject {
    
    let conversation : ZMConversation
    let typingUsers : Set<ZMUser>
    
    init (conversation : ZMConversation, typingUsers : Set<ZMUser>) {
        self.conversation = conversation
        self.typingUsers = typingUsers
    }
}
