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


extension ZMUserSession {

    @objc(likeMessageForNotification:WithCompletionHandler:)
    public func likeMessage(for note: UILocalNotification, completion: (() -> Void)?) {
        let activity = BackgroundActivityFactory.sharedInstance().backgroundActivity(withName: "Like Message Activiy");
        guard let conversation = note.conversation(in: managedObjectContext) else { return }
        guard let message = note.message(in: conversation, in: managedObjectContext) else { return }

        managedObjectContext.performGroupedBlock { [weak managedObjectContext] in
            ZMMessage.addReaction(.like, toMessage: message)
            managedObjectContext?.saveOrRollback()
            activity?.end()
            completion?()
        }

    }

}
