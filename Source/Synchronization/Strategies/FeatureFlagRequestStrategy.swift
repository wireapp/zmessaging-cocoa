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
    private var signatureFeatureFlagResponse: SignatureFeatureFlagResponse?
    
    // MARK: - Public Property
    var digitalSignatureFlagSync: ZMSingleRequestSync?

    // MARK: - AbstractRequestStrategy
    @objc
    public override init(withManagedObjectContext managedObjectContext: NSManagedObjectContext,
                         applicationStatus: ApplicationStatus) {
        
        syncContext = managedObjectContext
        super.init(withManagedObjectContext: managedObjectContext,
                   applicationStatus: applicationStatus)
        self.digitalSignatureFlagSync = ZMSingleRequestSync(singleRequestTranscoder: self,
                                                            groupQueue: syncContext)
    }
    
    @objc
    public override func nextRequestIfAllowed() -> ZMTransportRequest? {
        guard let featureFlagStatus = syncContext.featureFlagStatus else {
            return nil
        }
        
        switch featureFlagStatus.state {
        case .none:
            break
         case .digitalSignature:
            guard let requestSync = digitalSignatureFlagSync else {
                return nil
            }
            requestSync.readyForNextRequestIfNotBusy()
            return requestSync.nextRequest()
        case .digitalSignatureFail,
             .digitalSignatureSuccess:
            break
        }
        return nil
    }
}

// MARK: - ZMSingleRequestTranscoder
extension FeatureFlagRequestStrategy: ZMSingleRequestTranscoder {
    public func request(for sync: ZMSingleRequestSync) -> ZMTransportRequest? {
        switch sync {
        case digitalSignatureFlagSync:
            return makeDigitalSignatureFlagRequest()
        default:
            return nil
        }
    }
    
    public func didReceive(_ response: ZMTransportResponse,
                           forSingleRequest sync: ZMSingleRequestSync) {
        guard let featureFlagStatus = syncContext.featureFlagStatus else {
            return
        }
        
        switch (response.result) {
        case .success:
            switch sync {
            case digitalSignatureFlagSync:
                processDigitalSignatureFlagSuccess(with: response.rawData)
            default:
                break
            }
        case .temporaryError,
             .tryAgainLater,
             .expired:
            break
        case .permanentError:
            switch sync {
            case digitalSignatureFlagSync:
                featureFlagStatus.didReceiveSignatureFeatureFlagError()
            default:
                break
            }
        default:
            switch sync {
            case digitalSignatureFlagSync:
                featureFlagStatus.didReceiveSignatureFeatureFlagError()
            default:
                break
            }
        }
    }
    
    // MARK: - Helpers
    private func makeDigitalSignatureFlagRequest() -> ZMTransportRequest? {
        guard
            let featureFlagStatus = syncContext.featureFlagStatus,
            let teamId = featureFlagStatus.teamId
        else {
            return nil
        }
        
        return ZMTransportRequest(path: "/teams/\(teamId)/features/digital-signatures",
                                  method: .methodGET,
                                  payload: nil)
    }
    
    private func processDigitalSignatureFlagSuccess(with data: Data?) {
        guard
            let responseData = data,
            let featureFlagStatus = syncContext.featureFlagStatus
        else {
            return
        }
        
        do {
            let decodedResponse = try JSONDecoder().decode(SignatureFeatureFlagResponse.self,
                                                           from: responseData)
            signatureFeatureFlagResponse = decodedResponse
            featureFlagStatus.didReceiveSignatureFeatureFlag(decodedResponse.status)
        } catch {
            Logging.network.debug("Failed to decode SignatureResponse with \(error)")
        }
    }
}

// MARK: - SignatureFeatureFlagResponse
private struct SignatureFeatureFlagResponse: Codable, Equatable {
    let status: Bool
    
    private enum CodingKeys: String, CodingKey {
        case status = "status"
    }
    
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
