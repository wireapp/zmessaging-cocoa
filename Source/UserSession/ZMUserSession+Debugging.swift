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
    
    fileprivate static let debugCommands = [
        DebugCommand(
            "-logCryptoForClient",
            description: "Disable extended logging for encryption",
            execution: enableLogEncryption
        ),
        DebugCommand(
            "+logCryptoForClient",
            description: "Enable extended logging for encryption",
            execution: disableLogEncryption
        ),
        DebugCommand(
            "showIdentifier",
            description: "Return the user and client identifier",
            execution: showIdentifier
        ),
        DebugCommand(
            "help",
            description: "List all commands",
            execution: listCommands
        )
    ].dictionary { (key: $0.keyword, value: $0) }
    
    /// Parses and execute a debug command, which is expected to be
    /// tokenized already (e.g. "print", "foobar")
    public func executeDebugCommand(
        _ command: [String],
        completionHandler: (DebugCommandResult) -> ()
    ) {
                
        guard let keyword = command.first else {
            completionHandler(DebugCommandResult.UnknownCommand)
            return
        }
        
        let arguments = Array(command.dropFirst())
        
        guard let command = ZMUserSession.debugCommands[keyword] else {
            completionHandler(DebugCommandResult.UnknownCommand)
            return
        }
        
        command.closure(arguments, self, completionHandler)
    }
    
    
}

/// A debug command with an explaination
private struct DebugCommand {
    
    typealias DebugCommandExecution = (
        _ arguments: [String],
        _ userSession: ZMUserSession,
        _ completionHandler: ((DebugCommandResult) -> ())
    ) -> ()
    
    let keyword: String
    let description: String
    let closure: DebugCommandExecution
    
    init(
        _ keyword: String,
        description: String,
        execution: @escaping DebugCommandExecution
    ) {
        self.keyword = keyword
        self.description = description
        self.closure = execution
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

// MARK: - Commands

private func enableLogEncryption(
arguments: [String],
userSession: ZMUserSession,
completionHandler: (DebugCommandResult) -> ()
) {
    setLogEncryption(
        true,
        arguments: arguments,
        userSession: userSession,
        completionHandler: completionHandler)
}

private func disableLogEncryption(
arguments: [String],
userSession: ZMUserSession,
completionHandler: (DebugCommandResult) -> ()
) {
    setLogEncryption(
        true,
        arguments: arguments,
        userSession: userSession,
        completionHandler: completionHandler)
}

/// Enable or disables encryption logs for a given user and session
private func setLogEncryption(
    _ enabled: Bool,
    arguments: [String],
    userSession: ZMUserSession,
    completionHandler: (DebugCommandResult) -> ()
    )
{
    guard let context = userSession.selfUserClient?.keysStore.encryptionContext
        else {
            completionHandler(.Failure(error: "No session"))
            return
    }
    
    // if there is no argument to the disabling, then disable all
    if (!enabled && arguments.isEmpty) {
        context.disableExtendedLoggingOnAllSessions()
        completionHandler(.Success(info: "Logging disabled for all sessions"))
        return
    }
    
    guard arguments.count == 2 else {
        completionHandler(.Failure(error: "Expected arguments: <userId> <clientId>"))
        return
    }
    
    let user = arguments[0]
    let client = arguments[1]
    let identifier = EncryptionSessionIdentifier(
        userId: user, clientId: client
    )
    context.setExtendedLogging(identifier: identifier, enabled: enabled)
    completionHandler(.Success(info: "Logging " +
        (enabled ? "enabled" : "disabled") +
        " for session \(identifier.rawValue)")
    )
}

/// Show the user and client identifier
private func showIdentifier(
    arguments: [String],
    userSession: ZMUserSession,
    completionHandler: (DebugCommandResult) -> ()
    ) {
    
    guard let client = userSession.selfUserClient,
        let user = userSession.selfUser as? ZMUser
    else {
        completionHandler(.Failure(error: "No user"))
        return
    }
    
    completionHandler(.Success(info:
        "User: \(user.remoteIdentifier.uuidString)\n" +
        "Client: \(client.remoteIdentifier ?? "-")\n" +
        "Session: \(client.sessionIdentifier?.rawValue ?? "-")"
    ))
}

/// List all available commands
private func listCommands(
    arguments: [String],
    userSession: ZMUserSession,
    completionHandler: (DebugCommandResult) -> ()
    ) {
    
    let output = ZMUserSession.debugCommands.keys.sorted().map {
        "\($0) -> \(ZMUserSession.debugCommands[$0]!.description)"
    }.joined(separator: "\n")
    completionHandler(.Success(info: output))
}
