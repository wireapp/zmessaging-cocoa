//
//  ZMUserSession+Debugging.swift
//  WireSyncEngine-ios
//
//  Created by Marco Conti on 03/09/2020.
//  Copyright © 2020 Zeta Project Gmbh. All rights reserved.
//

import Foundation
import WireCryptobox

extension ZMUserSession {
    
    /// Parses and execute a debug command, which is expected to be
    /// tokenized already (e.g. "print", "foobar")
    public func executeDebugCommand(
        _ command: [String],
        onComplete: @escaping (DebugCommandResult) -> ()
    ) {
        guard let keyword = command.first else {
            onComplete(.UnknownCommand)
            return
        }
        
        let arguments = Array(command.dropFirst())
        
        guard let command = debugCommands[keyword] else {
            onComplete(.UnknownCommand)
            return
        }
        
        command.execute(
            arguments: arguments,
            onComplete: onComplete
        )
    }
    
    public func restoreDebugCommandsState() {
        debugCommands.values.forEach {
            $0.restoreFromState()
        }
    }

    fileprivate var debugStateUserDefaultsKey: String? {
        get {
            guard
                let identifier = (self.selfUser as! ZMUser).remoteIdentifier
            else { return nil }
            return "Wire-debugCommandsState-\(identifier)"
        }

    }
    
    /// The debug state persisted for this user
    fileprivate var savedDebugState: [String: [String: Any]] {
        get {
            guard let key = debugStateUserDefaultsKey else { return [:] }
            return UserDefaults.shared()?
                .dictionary(forKey: key) as? [String: [String: Any]] ?? [:]
        }
        set {
            guard let key = debugStateUserDefaultsKey else { return }
            UserDefaults.shared()?.set(newValue, forKey: key)
        }
    }
}

/// A debug command that can be invoked with arguments
private protocol DebugCommand {
    
    /// This is the keyword used to invoke the command
    var keyword: String { get }
    /// The user session context in which this command is executed
    var userSession: ZMUserSession { get }
        
    /// This will be called to execute the command
    func execute(
        arguments: [String],
        onComplete: @escaping ((DebugCommandResult) -> ())
    )
    
    /// This will be called with any previous persisted state
    /// when the user session is initialized
    func restoreFromState()
}

extension DebugCommand {
    
    /// Save any "state" that needs to be persisted. The state should
    /// only contain types can serialized in user defaults.
    func saveState(state: [String: Any]) {
        self.userSession.savedDebugState[self.keyword] = state
    }
    
    var savedState: [String: Any]? {
        get { return self.userSession.savedDebugState[self.keyword] }
    }
    
}

/// This is a mixin (implementation of a protocol that can be
/// inherited to avoid having to rewrite all protocol methods and vars)
private class DebugCommandMixin: DebugCommand {
    
    let keyword: String
    let userSession: ZMUserSession
    
    init(
        keyword: String,
        userSession: ZMUserSession
    ) {
        self.keyword = keyword
        self.userSession = userSession
    }
    
    func execute(arguments: [String],
                onComplete: @escaping ((DebugCommandResult) -> ())
    ) {
        onComplete(.Failure(error: "Not implemented"))
    }
    
    func restoreFromState() {
        return
    }
}

/// The result of a debug command
public enum DebugCommandResult {
    /// The command was a success. There is a string to show to the user
    case Success(info: String?)
    /// The command was a success. There is a file to show to the user
    case SuccessWithFile(file: NSURL)
    /// The command failed
    case Failure(error: String?)
    /// The command was not recognized
    case UnknownCommand
}


// MARK: - Commands List

extension ZMUserSession {

    fileprivate var debugCommands: [String: DebugCommand] {
        get {
            return [
                DebugCommandLogEncryption(userSession: self),
                DebugCommandShowIdentifiers(userSession: self),
                DebugCommandHelp(userSession: self),
                DebugCommandVariables(userSession: self)
            ].dictionary { (key: $0.keyword, value: $0) }
        }
    }
}

// MARK: - Command execution

extension EncryptionSessionIdentifier {
    
    fileprivate init?(string: String) {
        let split = string.split(separator: "_")
        guard split.count == 2 else { return nil }
        let user = String(split[0])
        let client = String(split[1])
        self.init(userId: user, clientId: client)
    }
}

private class DebugCommandLogEncryption: DebugCommandMixin {
    
    var currentlyEnabledLogs: Set<EncryptionSessionIdentifier> = Set()
    
    private var usage: String {
        get { "\(self.keyword) <add|remove|list> <sessionId|all>"}
    }
    
    init(userSession: ZMUserSession) {
        super.init(
            keyword: "logEncryption",
            userSession: userSession
        )
    }
    
    override func execute(
        arguments: [String],
        onComplete: @escaping ((DebugCommandResult) -> ()))
    {
        defer {
            self.saveEnabledLogs()
        }
        
        if (arguments.first == "list") {
            return onComplete(.Success(info:
                "Enabled:\n" +
                self.currentlyEnabledLogs
                    .map { $0.rawValue }
                    .joined(separator: "\n")
                ))
        }
        
        guard arguments.count == 2,
        arguments[0] == "add" || arguments[0] == "remove"
        else {
            return onComplete(.Failure(error: "usage: \(self.usage)"))
        }
        
        let isAdding = arguments[0] == "add"
        let subject = arguments[1]
        
        self.userSession.syncManagedObjectContext.perform {
            guard let context = self.userSession.selfUserClient?.keysStore.encryptionContext
                else {
                    return onComplete(.Failure(error: "No encryption context?"))
            }
            
            if !isAdding && subject == "all" {
                context.disableExtendedLoggingOnAllSessions()
                self.currentlyEnabledLogs = Set()
                return onComplete(.Success(info: "all removed"))
            }
            
            guard let identifier = EncryptionSessionIdentifier(string: subject) else {
                return onComplete(.Failure(error: "Invalid id \(subject)"))
            }
            
            if isAdding {
                self.currentlyEnabledLogs.insert(identifier)
            } else {
                self.currentlyEnabledLogs.remove(identifier)
            }
            context.setExtendedLogging(identifier: identifier, enabled: isAdding)
            return onComplete(.Success(info: nil))
        }
    }
    
    private let logsKey = "enabledLogs"
    
    private func saveEnabledLogs() {
        let idsToSave = self.currentlyEnabledLogs.map {
            $0.rawValue
        }
        self.saveState(state: [logsKey: idsToSave])
    }
    
    override func restoreFromState() {
        guard let state = savedState,
            let logs = state[logsKey] as? [String] else { return }
        self.currentlyEnabledLogs = Set(logs.compactMap {
            EncryptionSessionIdentifier(string: $0)
        })
        self.userSession.syncManagedObjectContext.performAndWait {
            guard let context = userSession.selfUserClient?.keysStore.encryptionContext
                else {
                    return
            }
            self.currentlyEnabledLogs.forEach {
                context.setExtendedLogging(identifier: $0, enabled: true)
            }
        }
    }
}

/// Show the user and client identifier
private class DebugCommandShowIdentifiers: DebugCommandMixin {

    init(userSession: ZMUserSession) {
        super.init(
            keyword: "showIdentifier",
            userSession: userSession
        )
    }
    
    override func execute(
        arguments: [String],
        onComplete: @escaping ((DebugCommandResult) -> ()))
    {
        guard let client = userSession.selfUserClient,
            let user = userSession.selfUser as? ZMUser
        else {
            onComplete(.Failure(error: "No user"))
            return
        }
        
        onComplete(.Success(info:
            "User: \(user.remoteIdentifier.uuidString)\n" +
            "Client: \(client.remoteIdentifier ?? "-")\n" +
            "Session: \(client.sessionIdentifier?.rawValue ?? "-")"
        ))
    }
}

/// Show commands
private class DebugCommandHelp: DebugCommandMixin {

    init(userSession: ZMUserSession) {
        super.init(
            keyword: "help",
            userSession: userSession
        )
    }
    
    override func execute(
        arguments: [String],
        onComplete: @escaping ((DebugCommandResult) -> ()))
    {
        let output = userSession.debugCommands.keys.sorted().joined(separator: "\n")
        onComplete(.Success(info: output))
    }
}

/// Debug variables
private class DebugCommandVariables: DebugCommandMixin {
    
    init(userSession: ZMUserSession) {
        super.init(
            keyword: "variables",
            userSession: userSession
        )
    }
        
    override func execute(
        arguments: [String],
        onComplete: @escaping ((DebugCommandResult) -> ()))
    {
        var state = self.savedState ?? [:]
        switch arguments.first {
        case "list":
            return onComplete(.Success(info: state.map { v in
                "\(v.key) => \(v.value)"
                }.joined(separator: "\n")
            ))
        case "set":
            guard arguments.count == 2 || arguments.count == 3 else {
                return onComplete(.Failure(error: "Usage: set <name> [<value>]"))
            }
            let key = arguments[1]
            let value = arguments.count == 3 ? arguments[2] : nil
            if let value = value {
                state[key] = value
            } else {
                state.removeValue(forKey: key)
            }
            self.saveState(state: state)
            return onComplete(.Success(info: nil))
        case "get":
            guard arguments.count == 2 else {
                return onComplete(.Failure(error: "Usage: get <name>"))
            }
            return onComplete(
                .Success(info: String(describing: state[arguments[1]]))
            )
        default:
            return onComplete(.UnknownCommand)
        }
    }
    
}
