////
// Wire
// Copyright (C) 2018 Wire Swiss GmbH
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
import WireDataModel
import ZipArchive

extension SessionManager {
    enum BackupError: Error {
        case noActiveAccount
        case compressionError
    }

    public func backupActiveAccount(completion: @escaping ((Result<URL>) -> ())) {
        guard let userId = accountManager.selectedAccount?.userIdentifier,
              let context = activeUserSession?.managedObjectContext,
              let clientId = ZMUser(remoteID: userId, createIfNeeded: false, in: context)?.selfClient()?.remoteIdentifier
        else { return completion(.failure(BackupError.noActiveAccount)) }
        
        StorageStack.backupLocalStorage(
            accountIdentifier: userId,
            clientIdentifier: clientId,
            applicationContainer: sharedContainerURL,
            completion: { completion($0.map(SessionManager.compress)) }
        )
    }
    
    private static func compress(backup: StorageStack.BackupInfo) throws -> URL {
        let targetURL = compressedBackupURL(for: backup)
        guard backup.url.zipDirectory(to: targetURL) else { throw BackupError.compressionError }
        return targetURL
    }
    
    private static func compressedBackupURL(for backup: StorageStack.BackupInfo) -> URL {
        return backup.url.deletingLastPathComponent().appendingPathComponent(backup.metadata.backupFilename)
    }
}

// MARK: - Compressed Filename

fileprivate extension BackupMetadata {
    
    private static let fileExtension = "wirebackup"
    
    private static let formatter: DateFormatter = {
       let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd-HH:mm"
        return formatter
    }()
    
    var backupFilename: String {
        return "\(BackupMetadata.formatter.string(from: creationTime)).\(BackupMetadata.fileExtension)"
    }
}

// MARK: - Zip Helper

fileprivate extension URL {
    func zipDirectory(to url: URL) -> Bool {
        return SSZipArchive.createZipFile(atPath: url.path, withContentsOfDirectory: path)
    }
    
    func unzip(to url: URL) -> Bool {
        return SSZipArchive.unzipFile(atPath: path, toDestination: url.path)
    }
}
