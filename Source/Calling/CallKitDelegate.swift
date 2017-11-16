/*
 * Wire
 * Copyright (C) 2017 Wire Swiss GmbH
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */

import Foundation
import CallKit
import Intents
import avs

private let zmLog = ZMSLog(tag: "calling")

private struct CallKitCall {
    let conversation : ZMConversation
    let observer : CallObserver
    
    init(conversation : ZMConversation) {
        self.conversation = conversation
        self.observer = CallObserver(conversation: conversation)
    }
}

@objc
@available(iOS 10.0, *)
public class CallKitDelegate : NSObject {
    
    fileprivate let provider : CXProvider
    fileprivate let callController : CXCallController
    fileprivate unowned let userSession : ZMUserSession
    fileprivate weak var flowManager : FlowManagerType?
    fileprivate weak var mediaManager: AVSMediaManager?
    fileprivate var callStateObserverToken : Any?
    fileprivate var missedCallObserverToken : Any?
    fileprivate var connectedCallConversation : ZMConversation?
    fileprivate var calls : [UUID : CallKitCall]
    
    public init(provider : CXProvider,
         callController: CXCallController,
         userSession: ZMUserSession,
         flowManager: FlowManagerType?,
         mediaManager: AVSMediaManager?) {
        
        self.provider = provider
        self.callController = callController
        self.userSession = userSession
        self.flowManager = flowManager
        self.mediaManager = mediaManager
        self.calls = [:]
        
        super.init()
        
        provider.setDelegate(self, queue: nil)
                
        callStateObserverToken = WireCallCenterV3.addCallStateObserver(observer: self, context: userSession.managedObjectContext)
        missedCallObserverToken = WireCallCenterV3.addMissedCallObserver(observer: self, context: userSession.managedObjectContext)
    }
    
    deinit {
        provider.invalidate()
    }
    
    public static var providerConfiguration : CXProviderConfiguration {
        
        let localizedName = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "Wire"
        let configuration = CXProviderConfiguration(localizedName: localizedName)
        
        configuration.supportsVideo = true
        configuration.maximumCallGroups = 1
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportedHandleTypes = [.generic]
        configuration.ringtoneSound = ZMCustomSound.notificationRingingSoundName()
        
        if let image = UIImage(named: "logo") {
            configuration.iconTemplateImageData = UIImagePNGRepresentation(image)
        }
        
        return configuration
    }
    
    fileprivate func log (for conversation: ZMConversation?, format: String, arguments: CVarArg..., file: String = #file, line: Int = #line) {
        let messageWithLineNumber = String(format: "%s:%ld: %@", file, line, String(format: format, arguments))
        
        if let conversationId = conversation?.remoteIdentifier {
            flowManager?.appendLog(for: conversationId, message: messageWithLineNumber)
        }
    }
    
    fileprivate func endAllOngoingCallKitCalls(exceptIn conversation: ZMConversation) {
        
        for call in calls where call.value.conversation != conversation {
            let endCallAction = CXEndCallAction(call: call.key)
            let transaction = CXTransaction(action: endCallAction)
            
            callController.request(transaction, completion: { (error) in
                if let error = error {
                    zmLog.error("Coudn't end all ongoing calls: \(error)")
                }
            })
        }
    }
    
    internal func callUUID(for conversation: ZMConversation) -> UUID? {
        return calls.first(where: { $0.value.conversation == conversation })?.key
    }
}

@available(iOS 10.0, *)
extension CallKitDelegate {
    
    func conversationAssociated(with contacts: [INPerson]) -> ZMConversation? {
        
        guard contacts.count == 1,
              let contact = contacts.first,
              let customIdentifier = contact.customIdentifier,
              let remoteIdentifier = UUID.init(uuidString: customIdentifier) else {
            return nil
        }
        
        return ZMConversation(remoteID: remoteIdentifier, createIfNeeded: false, in: userSession.managedObjectContext)
    }
    
    public func continueUserActivity(_ userActivity : NSUserActivity) -> Bool {
        guard let interaction = userActivity.interaction
        else { return false }
        
        let intent = interaction.intent
        var contacts : [INPerson]? = nil
        var video = false
        
        if let audioCallIntent = intent as? INStartAudioCallIntent {
            contacts = audioCallIntent.contacts
            video = false
        }
        else if let videoCallIntent = intent as? INStartVideoCallIntent {
            contacts = videoCallIntent.contacts
            video = true
        }
        
        if let contacts = contacts, contacts.count == 1, let conversation = conversationAssociated(with: contacts) {
            requestStartCall(in: conversation, video: video)
            return true
        }
        
        return false
    }
}

@available(iOS 10.0, *)
extension CallKitDelegate {
    
    func requestJoinCall(in conversation: ZMConversation, video: Bool) {
        
        let existingCallUUID = callUUID(for: conversation)
        let existingCall = callController.callObserver.calls.first(where: { $0.uuid == existingCallUUID })
        
        if let call = existingCall, !call.isOutgoing {
            requestAnswerCall(in: conversation, video: video)
        } else {
            requestStartCall(in: conversation, video: video)
        }
    }
    
    func requestStartCall(in conversation: ZMConversation, video: Bool) {
        
        endAllOngoingCallKitCalls(exceptIn: conversation)
        
        guard
            let managedObjectContext = conversation.managedObjectContext,
            let handle = conversation.callKitHandle
        else {
            zmLog.warn("Ignore request to start call since remoteIdentifier or handle is nil")
            return
        }
        
        let callUUID = UUID()
        calls[callUUID] = CallKitCall(conversation: conversation)
        
        let action = CXStartCallAction(call: callUUID, handle: handle)
        action.isVideo = video
        action.contactIdentifier = conversation.localizedCallerName(with: ZMUser.selfUser(in: managedObjectContext))
        let transaction = CXTransaction(action: action)
        
        
        callController.request(transaction) { [weak self] (error) in
            if let error = error as? CXErrorCodeRequestTransactionError, error.code == .callUUIDAlreadyExists {
                self?.requestAnswerCall(in: conversation, video: video)
            } else if let error = error {
                self?.log(for: conversation, format: "Cannot start call: \(error)")
            }
        }
        
    }
    
    func requestAnswerCall(in conversation: ZMConversation, video: Bool) {
        
        endAllOngoingCallKitCalls(exceptIn: conversation)
        
        guard let callUUID = callUUID(for: conversation) else { return }
        
        let action = CXAnswerCallAction(call: callUUID)
        let transaction = CXTransaction(action: action)
        
        callController.request(transaction) { [weak self] (error) in
            if let error = error {
                self?.log(for: conversation, format: "Cannot answer call: \(error)")
            }
        }
    }
    
    func requestEndCall(in conversation: ZMConversation) {
        guard let callUUID = callUUID(for: conversation) else { return }
        
        let action = CXEndCallAction(call: callUUID)
        let transaction = CXTransaction(action: action)
        
        callController.request(transaction) { [weak self] (error) in
            if let error = error {
                self?.log(for: conversation, format: "Cannot end call: \(error)")
                conversation.voiceChannel?.endCall()
            }
        }
    }
    
    func reportIncomingCall(from user: ZMUser, in conversation: ZMConversation, video: Bool) {
        guard let handle = conversation.callKitHandle else {
            return log(for: conversation, format: "Cannot report incoming call: conversation is missing a handle")
        }
        
        let update = CXCallUpdate()
        update.supportsHolding = false
        update.supportsDTMF = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.localizedCallerName = conversation.localizedCallerName(with: user)
        update.remoteHandle = handle
        update.hasVideo = video
        
        let callUUID = UUID()
        calls[callUUID] = CallKitCall(conversation: conversation)
        
        provider.reportNewIncomingCall(with: callUUID, update: update) { [weak self] (error) in
            if let error = error {
                self?.log(for: conversation, format: "Cannot report incoming call: \(error)")
                self?.calls.removeValue(forKey: callUUID)
                conversation.voiceChannel?.leave()
            } else {
                self?.mediaManager?.setupAudioDevice()
            }
        }
    }
    
    func reportCall(in conversation: ZMConversation, endedAt timestamp: Date?, reason: CXCallEndedReason) {
        
        var associatedCallUUIDs : [UUID] = []
        for call in calls {
            if call.value.conversation == conversation {
                associatedCallUUIDs.append(call.key)
            }
        }
        
        associatedCallUUIDs.forEach { (callUUID) in
            calls.removeValue(forKey: callUUID)
            provider.reportCall(with: callUUID, endedAt: timestamp, reason: reason)
        }
    }
}

@available(iOS 10.0, *)
extension CallKitDelegate : CXProviderDelegate {
    
    public func providerDidBegin(_ provider: CXProvider) {
        log(for: nil, format: "providerDidBegin: \(provider)")
    }
    
    public func providerDidReset(_ provider: CXProvider) {
        log(for: nil, format: "providerDidReset: \(provider)")
        mediaManager?.resetAudioDevice()
        calls.removeAll()
        
        // leave all active calls
        for conversation in userSession.callCenter?.nonIdleCallConversations(in: userSession) ?? [] {
            conversation.voiceChannel?.leave()
        }
    }
    
    public func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        log(for: nil, format: "perform CXStartCallAction: \(action)")
        
        guard let call = calls[action.callUUID] else {
            log(for: nil, format: "fail CXStartCallAction because call did not exist")
            action.fail()
            return
        }
        
        call.observer.onAnswered = {
            provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: Date())
        }
        
        call.observer.onEstablished = {
            provider.reportOutgoingCall(with: action.callUUID, connectedAt: Date())
        }
        
        mediaManager?.setupAudioDevice()
        
        if call.conversation.voiceChannel?.join(video: action.isVideo) == true {
            action.fulfill()
        } else {
            action.fail()
        }
        
        let update = CXCallUpdate()
        update.remoteHandle = call.conversation.callKitHandle
        update.localizedCallerName = call.conversation.localizedCallerName(with: ZMUser.selfUser(inUserSession: userSession))
        
        provider.reportCall(with: action.callUUID, updated: update)
    }
    
    public func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        log(for: nil, format: "perform CXAnswerCallAction: \(action)")
        
        guard let call = calls[action.callUUID] else {
            log(for: nil, format: "fail CXAnswerCallAction because call did not exist")
            action.fail()
            return
        }
        
        call.observer.onEstablished = {
            action.fulfill()
        }
        
        call.observer.onFailedToJoin = {
            action.fail()
        }
        
        if call.conversation.voiceChannel?.join(video: false) != true {
            action.fail()
        }
    }
    
    public func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        log(for: nil, format: "perform CXEndCallAction: \(action)")
        
        guard let call = calls[action.callUUID] else {
            log(for: nil, format: "fail CXEndCallAction because call did not exist")
            action.fail()
            return
        }
        
        calls.removeValue(forKey: action.callUUID)
        call.conversation.voiceChannel?.endCall()
        action.fulfill()
    }
    
    public func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
        log(for: nil, format: "perform CXSetHeldCallAction: \(action)")
        mediaManager?.isMicrophoneMuted = action.isOnHold
        action.fulfill()
    }
    
    public func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        log(for: nil, format: "perform CXSetMutedCallAction: \(action)")
        mediaManager?.isMicrophoneMuted = action.isMuted
        action.fulfill()
    }
    
    public func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        log(for: nil, format: "didActivate audioSession")
        mediaManager?.startAudio()
    }
    
    public func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        log(for: nil, format: "didDeactivate audioSession")
        mediaManager?.resetAudioDevice()
    }
}

@available(iOS 10.0, *)
extension CallKitDelegate : WireCallCenterCallStateObserver, WireCallCenterMissedCallObserver {
    
    public func callCenterDidChange(callState: CallState, conversation: ZMConversation, caller: ZMUser, timestamp: Date?) {
        
        switch callState {
        case .incoming(video: let video, shouldRing: let shouldRing, degraded: _):
            if shouldRing {
                if !conversation.isSilenced {
                    reportIncomingCall(from: caller, in: conversation, video: video)
                }
            } else {
                reportCall(in: conversation, endedAt: timestamp, reason: .unanswered)
            }
        case let .terminating(reason: reason):
            reportCall(in: conversation, endedAt: timestamp, reason: reason.CXCallEndedReason)
            
        default:
            break
        }
    }
    
    public func callCenterMissedCall(conversation: ZMConversation, caller: ZMUser, timestamp: Date, video: Bool) {
        // Since we missed the call we will not have an assigned callUUID and can just create a random one
        provider.reportCall(with: UUID(), endedAt: timestamp, reason: .unanswered)
    }
    
}

@available(iOS 10.0, *)
extension ZMConversation {
    
    var callKitHandle : CXHandle? {
        if let remoteIdentifier = remoteIdentifier {
            return CXHandle(type: .generic, value: remoteIdentifier.transportString())
        }
        
        return nil
    }
    
    func localizedCallerName(with user: ZMUser) -> String? {
        
        switch conversationType {
        case .group:
            return ("callkit.call.started.group" as NSString).localizedCallKitString(with: user, conversation: self)
        case .oneOnOne:
            return connectedUser?.displayName
        default:
            return nil
        }
    }
    
}

extension VoiceChannel {
    
    func endCall() {
        
        switch state {
        case .incoming(video: _, shouldRing: true, degraded: false):
            ignore()
        case .established, .answered(degraded: false), .outgoing(degraded: false):
            leave()
        default:
            break
        }
        
    }
}

@available(iOS 10.0, *)
extension CXCallAction {
    
    func conversation(in context : NSManagedObjectContext) -> ZMConversation? {
        return ZMConversation(remoteID: callUUID, createIfNeeded: false, in: context)
    }
    
}

extension CallClosedReason {
    
    @available(iOS 10.0, *)
    var CXCallEndedReason : CXCallEndedReason {
        switch self {
        case .timeout:
            return .unanswered
        case .normal, .canceled:
            return .remoteEnded
        case .anweredElsewhere:
            return .answeredElsewhere
        default:
            return .failed
        }
    }
    
}

class CallObserver : WireCallCenterCallStateObserver {
    
    private var token : Any?
    
    public var onAnswered : (() -> Void)?
    public var onEstablished : (() -> Void)?
    public var onFailedToJoin : (() -> Void)?
    
    public init(conversation: ZMConversation) {
        token = WireCallCenterV3.addCallStateObserver(observer: self, for: conversation, context: conversation.managedObjectContext!)
    }
    
    public func callCenterDidChange(callState: CallState, conversation: ZMConversation, caller: ZMUser, timestamp: Date?) {
        switch callState {
        case .answered(degraded: false):
            onAnswered?()
        case .establishedDataChannel:
            onEstablished?()
        case .terminating(reason: let reason):
            switch reason {
            case .inputOutputError, .internalError, .unknown, .lostMedia, .anweredElsewhere:
                onFailedToJoin?()
            default:
                break
            }
        default:
            break
        }
    }
    
}
