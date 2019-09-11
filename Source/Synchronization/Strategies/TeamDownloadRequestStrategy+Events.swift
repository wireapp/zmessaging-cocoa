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


fileprivate  enum TeamEventPayloadKey: String {
    case team
    case data
    case user
    case conversation = "conv"

}

fileprivate extension ZMUpdateEvent {

    var teamId: UUID? {
        return(payload[TeamEventPayloadKey.team.rawValue] as? String).flatMap(UUID.init)
    }

    var dataPayload: [String: Any]? {
        return payload[TeamEventPayloadKey.data.rawValue] as? [String: Any]
    }
}


private let log = ZMSLog(tag: "Teams")


extension TeamDownloadRequestStrategy: ZMEventConsumer {
    
    public func processEvents(_ events: [ZMUpdateEvent], liveEvents: Bool, prefetchResult: ZMFetchRequestBatchResult?) {
        events.forEach(process)
    }

    private func process(_ event: ZMUpdateEvent) {
        switch event.type {
        case .teamCreate: createTeam(with: event)
        case .teamDelete: deleteTeam(with: event)
        case .teamUpdate: updateTeam(with : event)
        case .teamMemberJoin: processAddedMember(with: event)
        case .teamMemberLeave: processRemovedMember(with: event)
        case .teamMemberUpdate: processUpdatedMember(with: event)
        default: break
        }
    }

    private func createTeam(with event: ZMUpdateEvent) {
        // With the new multi-account model this event should not be sent anymore,
        // and if it is we should not act on it.
        // An account will either have a team since registration or not, 
        // currently there is no way to get added to a team after registering.
    }

    private func deleteTeam(with event: ZMUpdateEvent) {
        deleteAccount()
    }

    private func updateTeam(with event: ZMUpdateEvent) {
        guard let identifier = event.teamId, let data = event.dataPayload else { return }
        guard let existingTeam = Team.fetchOrCreate(with: identifier, create: false, in: managedObjectContext, created: nil) else { return }
        existingTeam.update(with: data)
    }

    private func processAddedMember(with event: ZMUpdateEvent) {
        guard let identifier = event.teamId, let data = event.dataPayload else { return }
        guard let team = Team.fetchOrCreate(with: identifier, create: false, in: managedObjectContext, created: nil) else { return }
        guard let addedUserId = (data[TeamEventPayloadKey.user.rawValue] as? String).flatMap(UUID.init) else { return }
        guard let user = ZMUser(remoteID: addedUserId, createIfNeeded: true, in: managedObjectContext) else { return }
        user.needsToBeUpdatedFromBackend = true
        let member = Member.getOrCreateMember(for: user, in: team, context: managedObjectContext)

        // cf. https://github.com/wireapp/architecture/issues/13
        // We want to refetch the members in case we didn't just create the team as the payload does not include permissions.
        member.needsToBeUpdatedFromBackend = true
    }

    private func processRemovedMember(with event: ZMUpdateEvent) {
        guard let identifier = event.teamId, let data = event.dataPayload else { return }
        guard let team = Team.fetchOrCreate(with: identifier, create: false, in: managedObjectContext, created: nil) else { return }
        guard let removedUserId = (data[TeamEventPayloadKey.user.rawValue] as? String).flatMap(UUID.init) else { return }
        guard let user = ZMUser(remoteID: removedUserId, createIfNeeded: false, in: managedObjectContext) else { return }
        if let member = user.membership {
            if user.isSelfUser {
                deleteAccount()
            } else {
                user.markAccountAsDeleted(at: event.timeStamp() ?? Date())
            }
            managedObjectContext.delete(member)
        } else {
            log.error("Trying to delete non existent membership of \(user) in \(team)")
        }
    }

    private func processUpdatedMember(with event: ZMUpdateEvent) {
        guard nil != event.teamId, let data = event.dataPayload else { return }
        guard let userId = (data[TeamEventPayloadKey.user.rawValue] as? String).flatMap(UUID.init) else { return }
        guard let member = Member.fetch(withRemoteIdentifier: userId, in: managedObjectContext) else { return }
        member.needsToBeUpdatedFromBackend = true
    }
    
    private func deleteTeamAndConversations(_ team: Team) {
        team.conversations.forEach(managedObjectContext.delete)
        managedObjectContext.delete(team)
    }
    
    private func deleteAccount() {
        PostLoginAuthenticationNotification.notifyAccountDeleted(context: managedObjectContext)
    }

}
