// 
// Wire
// Copyright (C) 2016 Wire Swiss GmbH
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


@import Cryptobox;

@class ZMUpdateEvent;
@class UserClient;



@interface EncryptionSessionsDirectory (UpdateEvent)

/// Decrypts an event (if needed) and return a decrypted copy (or the original if no
/// decryption was needed) and information about the decryption result.
///
- (ZMUpdateEvent * __nullable)decryptUpdateEventAndAddClient:(ZMUpdateEvent * __nullable)event managedObjectContext:(NSManagedObjectContext * __nonnull)moc;

@end
