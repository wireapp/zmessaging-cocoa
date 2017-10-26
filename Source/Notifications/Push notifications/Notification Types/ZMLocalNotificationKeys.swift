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

public let ZMLocalNotificationConversationObjectURLKey: NSString = "conversationObjectURLString"
public let ZMLocalNotificationUserInfoSenderKey: NSString = "senderUUID"
public let ZMLocalNotificationUserInfoNonceKey: NSString = "nonce"

public let FailedMessageInGroupConversationText: NSString = "failed.message.group"
public let FailedMessageInOneOnOneConversationText: NSString = "failed.message.oneonone"


// These are the "base" keys for messages. We append to these for the specific case.
//
public let ZMPushStringDefault             = "default"
public let ZMPushStringEphemeral           = "ephemeral"

// Title with team name
public let ZMPushStringTitle               = "title"          // "[conversationName] in [teamName]

// 1 user, 1 conversation, 1 string
// %1$@    %2$@            %3$@
//
public let ZMPushStringMessageAdd          = "add.message"         // "[senderName]: [messageText]"
public let ZMPushStringImageAdd            = "add.image"           // "[senderName] shared a picture"
public let ZMPushStringVideoAdd            = "add.video"           // "[senderName] shared a video"
public let ZMPushStringAudioAdd            = "add.audio"           // "[senderName] shared an audio message"
public let ZMPushStringFileAdd             = "add.file"            // "[senderName] shared a file"
public let ZMPushStringLocationAdd         = "add.location"        // "[senderName] shared a location"
public let ZMPushStringUnknownAdd          = "add.unknown"         // "[senderName] sent a message"

// currently disabled
//public let ZMPushStringMessageAddMany      = "add.message.many"    // "x new messages in [conversationName] / from [senderName]"

public let ZMPushStringMemberJoin          = "member.join"         // "[senderName] added you"
public let ZMPushStringMemberLeave         = "member.leave"        // "[senderName] removed you"

public let ZMPushStringKnock               = "knock"               // "pinged"
public let ZMPushStringReaction            = "reaction"            // "[emoji] your message"

public let ZMPushStringVideoCallStarts     = "call.started.video"  // "is video calling"
public let ZMPushStringCallStarts          = "call.started"        // "is calling"
public let ZMPushStringCallMissed          = "call.missed"         // "called"

// currently disabled
//public let ZMPushStringCallMissedMany      = "call.missed.many"    // "You have x missed calls in a conversation"

public let ZMPushStringConnectionRequest   = "connection.request"  // "[senderName] wants to connect"
public let ZMPushStringConnectionAccepted  = "connection.accepted" // "You and [senderName] are now connected"

public let ZMPushStringConversationCreate  = "conversation.create" // "[senderName] created a group conversation with you"
public let ZMPushStringNewConnection       = "new_user"            // "[senderName] just joined Wire"

