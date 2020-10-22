//
//  PresentationDelegate.swift
//  WireSyncEngine-ios
//
//  Created by Marco Maddalena on 22/10/2020.
//  Copyright © 2020 Zeta Project Gmbh. All rights reserved.
//

import Foundation

public protocol PresentationDelegate: class {
    /// Called when a conversation at one particular message should be shown
    /// - parameter conversation: Conversation which will be performed.
    /// - parameter message: Message which the conversation will be opened at.
    func showConversation(_ conversation: ZMConversation, at message: ZMConversationMessage?)
    
    /// Called when the conversation list should be shown
    func showConversationList()
    
    /// Called when an user profile screen should be presented
    /// - parameter user: The user which the profile will belong to.
    func showUserProfile(user: UserType)
    
    /// Called when the connection screen for a centain user shold be presented
    /// - parameter userId: The userId which will be connected to.
    func showConnectionRequest(userId: UUID)
    
    /// Called when an attempt was made to process a URLAction but failed
    ///
    /// - parameter action: Action which failed to be performed.
    /// - parameter error: Error describing why the action failed.
    func failedToPerformAction(_ action: URLAction, error: Error)
    
    /// Called before attempt is made to process a URLAction, this is a opportunity for asking the user
    /// to confirm the action. The answer is provided via the decisionHandler.
    ///
    /// - parameter action: Action which will be performed.
    /// - parameter decisionHandler: Block which should be executed when the decision has been to perform the action or not.
    /// - parameter shouldPerformAction: **true**: perform the action, **false**: abort the action
    func shouldPerformAction(_ action: URLAction, decisionHandler: @escaping (_ shouldPerformAction: Bool) -> Void)
    
    /// Called when an URLAction was successfully performed.
    func completedURLAction(_ action: URLAction)
}
