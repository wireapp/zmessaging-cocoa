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

let ZMLocalNotificationConversationObjectURLKey: NSString = "conversationObjectURLString"
let ZMLocalNotificationUserInfoSenderKey: NSString = "senderUUID"
let ZMLocalNotificationUserInfoNonceKey: NSString = "nonce"

let FailedMessageInGroupConversationText: NSString = "failed.message.group"
let FailedMessageInOneOnOneConversationText: NSString = "failed.message.oneonone"


// These are the "base" keys for messages. We append to these for the specific case.
//
let ZMPushStringDefault             = "default"
let ZMPushStringEphemeral           = "ephemeral"

// 1 user, 1 conversation, 1 string
// %1$@    %2$@            %3$@
//
let ZMPushStringMessageAdd          = "add.message"         // "[senderName] in [conversationName] - [messageText]"
let ZMPushStringImageAdd            = "add.image"           // "[senderName] shared a picture in [conversationName]"
let ZMPushStringVideoAdd            = "add.video"           // "[senderName] shared a video in [conversationName]"
let ZMPushStringAudioAdd            = "add.audio"           // "[senderName] shared an audio message in [conversationName]"
let ZMPushStringFileAdd             = "add.file"            // "[senderName] shared a file in [conversationName]"
let ZMPushStringLocationAdd         = "add.location"        // "[senderName] shared a location in [conversationName]"
let ZMPushStringUnknownAdd          = "add.unknown"         // "[senderName] sent a message in [conversationName]"
let ZMPushStringMessageAddMany      = "add.message.many"    // "x new messages in [conversationName] / from [senderName]"

let ZMPushStringMemberJoin          = "member.join"         // "[senderName] added you / [userName] to [conversationName]"
let ZMPushStringMemberLeave         = "member.leave"        // "[senderName] removed you / [userName] from [conversationName]"

let ZMPushStringMemberJoinMany      = "member.join.many"    // "[senderName] added people to [conversationName]"
let ZMPushStringMemberLeaveMany     = "member.leave.many"   // "[senderName] removed people from [conversationName]"

let ZMPushStringKnock               = "knock"               // "[senderName] pinged you x times in [conversationName]" // "x pings in
let ZMPushStringReaction            = "reaction"            // "[senderName] [emoji] your message in [conversationName]"

let ZMPushStringVideoCallStarts     = "call.started.video"  // "[senderName] wants to talk"
let ZMPushStringCallStarts          = "call.started"        // "[senderName] wants to talk"
let ZMPushStringCallMissed          = "call.missed"         // "[senderName] called you x times"
let ZMPushStringCallMissedMany      = "call.missed.many"    // "You have x missed calls in a conversation"

let ZMPushStringConnectionRequest   = "connection.request"  // "[senderName] wants to connect: [messageText]"
let ZMPushStringConnectionAccepted  = "connection.accepted" // "[senderName] accepted your connection request"

let ZMPushStringConversationCreate  = "conversation.create"
let ZMPushStringNewConnection       = "new_user"
