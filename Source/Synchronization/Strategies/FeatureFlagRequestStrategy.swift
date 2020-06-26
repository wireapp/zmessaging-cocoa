//
// Wire
// Copyright (C) 2020 Wire Swiss GmbH
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

// Get FeatureFlags
@objc
public final class FeatureFlagRequestStrategy: AbstractRequestStrategy {
    
    // MARK: - Private Property
    private let syncContext: NSManagedObjectContext
    private let syncStatus: SyncStatus
    
    // MARK: - Public Property
    var singleRequestSync: ZMSingleRequestSync?

    // MARK: - AbstractRequestStrategy
    @objc
    public init(withManagedObjectContext managedObjectContext: NSManagedObjectContext,
                applicationStatus: ApplicationStatus,
                syncStatus: SyncStatus) {
        syncContext = managedObjectContext
        self.syncStatus = syncStatus
        
        super.init(withManagedObjectContext: managedObjectContext,
                   applicationStatus: applicationStatus)
        
        self.configuration = [.allowsRequestsDuringSync]
        self.singleRequestSync = ZMSingleRequestSync(singleRequestTranscoder: self,
                                                     groupQueue: managedObjectContext)
    }
    
    @objc
    public override func nextRequestIfAllowed() -> ZMTransportRequest? {
        guard
            syncStatus.currentSyncPhase == .fetchingFeatureFlags,
            let singleRequestSync = singleRequestSync
        else {
            return nil
        }
        
        singleRequestSync.readyForNextRequestIfNotBusy()
        return singleRequestSync.nextRequest()
    }
}

// MARK: - ZMSingleRequestTranscoder
extension FeatureFlagRequestStrategy: ZMSingleRequestTranscoder {
    public func request(for sync: ZMSingleRequestSync) -> ZMTransportRequest? {
        switch sync {
        case singleRequestSync:
            return makeDigitalSignatureFlagRequest()
        default:
            return nil
        }
    }
    
    public func didReceive(_ response: ZMTransportResponse,
                           forSingleRequest sync: ZMSingleRequestSync) {
        
        guard response.result == .permanentError || response.result == .success else {
            return
        }
        
        if response.result == .success, let rawData = response.rawData {
            processDigitalSignatureFlagSuccess(with: rawData)
        }
        
        if syncStatus.currentSyncPhase == .fetchingFeatureFlags {
            syncStatus.finishCurrentSyncPhase(phase: .fetchingFeatureFlags)
        }
    }
    
    // MARK: - Helpers
    private func makeDigitalSignatureFlagRequest() -> ZMTransportRequest? {
        guard let teamId = ZMUser.selfUser(in: syncContext).teamIdentifier?.uuidString else {
            return nil
        }
        
        return ZMTransportRequest(path: "/teams/\(teamId)/features/digital-signatures",
                                  method: .methodGET,
                                  payload: nil)
    }
    
    private func processDigitalSignatureFlagSuccess(with data: Data?) {
        guard let responseData = data else {
            return
        }
        
        do {
            let decodedResponse = try JSONDecoder().decode(SignatureFeatureFlagResponse.self,
                                                           from: responseData)
            update(with: decodedResponse)
        } catch {
            Logging.network.debug("Failed to decode SignatureResponse with \(error)")
        }
    }
    
    private func update(with response: SignatureFeatureFlagResponse) {
        guard let team = ZMUser.selfUser(in: syncContext).team else {
            return
        }
        
        FeatureFlag.fetchOrCreate(with: .digitalSignature,
                                  value: response.status,
                                  team: team,
                                  context: syncContext)
        syncContext.saveOrRollback()
    }
}

// MARK: - SignatureFeatureFlagResponse
private struct SignatureFeatureFlagResponse: Codable, Equatable {
    let status: Bool
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let statusStr = try container.decodeIfPresent(String.self, forKey: .status)
        switch statusStr {
        case "enabled":
            status = true
        default:
            status = false
        }
    }
}
