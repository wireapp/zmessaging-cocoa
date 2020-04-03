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

public var signatureStatusPublic: SignatureStatus?
private let zmLog = ZMSLog(tag: "EventDecoder")

// Sign a PDF document
@objc
public final class SignatureRequestStrategy: AbstractRequestStrategy {
    
    // MARK: - Private Property
    private weak var signatureStatus: SignatureStatus?
    private let moc: NSManagedObjectContext
    private var requestSync: ZMSingleRequestSync?
    private var retrieveSync: ZMSingleRequestSync?
    private var signatureResponse: SignatureResponse?
    private var retrieveResponse: SignatureRetrieveResponse?

    // MARK: - AbstractRequestStrategy
    @objc
    public override init(withManagedObjectContext managedObjectContext: NSManagedObjectContext,
                         applicationStatus: ApplicationStatus) {
        
        self.moc = managedObjectContext
        super.init(withManagedObjectContext: managedObjectContext,
                   applicationStatus: applicationStatus)
        self.requestSync = ZMSingleRequestSync(singleRequestTranscoder: self,
                                               groupQueue: moc)
        self.retrieveSync = ZMSingleRequestSync(singleRequestTranscoder: self,
                                                groupQueue: moc)
    }
    
    @objc
    public override func nextRequestIfAllowed() -> ZMTransportRequest? {
        signatureStatus = signatureStatusPublic
        guard let status = signatureStatus else { return nil }
        
        switch status.state {
        case .initial:
            break
         case .waitingForConsentURL:
            guard let requestSync = requestSync else {
                return nil
            }
            requestSync.readyForNextRequestIfNotBusy()
            return requestSync.nextRequest()
        case .waitingForCodeVerification:
            break
        case .waitingForSignature:
            guard let retrieveSync = retrieveSync else {
                return nil
            }
            retrieveSync.readyForNextRequestIfNotBusy()
            return retrieveSync.nextRequest()
        case .signatureInvalid:
            break
        case .finished:
            break
        }
        return nil
    }
}

// MARK: - ZMSingleRequestTranscoder
extension SignatureRequestStrategy: ZMSingleRequestTranscoder {
    public func request(for sync: ZMSingleRequestSync) -> ZMTransportRequest? {
        switch sync {
        case requestSync:
            return makeSignatureRequest()
        case retrieveSync:
            return makeRetrieveSignatureRequest()
        default:
            return nil
        }
    }
    
    public func didReceive(_ response: ZMTransportResponse,
                           forSingleRequest sync: ZMSingleRequestSync) {
        switch (response.result) {
        case .success:
            switch sync {
            case requestSync:
                processRequestSignatureSuccess(with: response.rawData)
            case retrieveSync:
                processRetrieveSignatureSuccess(with: response.rawData)
            default:
                break
            }
        case .temporaryError,
             .tryAgainLater,
             .expired:
            break
        case .permanentError:
            signatureStatusPublic?.didReceiveError()
        default:
            signatureStatusPublic?.didReceiveError()
        }
    }
    
    // MARK: - Helpers
    private func makeSignatureRequest() -> ZMTransportRequest? {
        guard
            let encodedHash = signatureStatus?.encodedHash,
            let documentID = signatureStatus?.documentID,
            let fileName = signatureStatus?.fileName,
            let payload = SignaturePayload(documentID: documentID,
                                           fileName: fileName,
                                           hash: encodedHash).jsonDictionary as NSDictionary?
        else {
            return nil
        }
        
        return ZMTransportRequest(path: "/signature/request",
                                  method: .methodPOST,
                                  payload: payload as ZMTransportData)
    }
    
    private func makeRetrieveSignatureRequest() -> ZMTransportRequest? {
        guard let responseId = signatureResponse?.responseId else {
            return nil
        }
        
        return ZMTransportRequest(path: "/signature/pending/\(responseId)",
                                  method: .methodGET,
                                  payload: nil)
    }
    
    private func processRequestSignatureSuccess(with data: Data?) {
        guard let responseData = data else {
            return
        }
        
        do {
            let decodedResponse = try JSONDecoder().decode(SignatureResponse.self,
                                                           from: responseData)
            signatureResponse = decodedResponse
            guard let consentURL = signatureResponse?.consentURL else {
                return
            }
            signatureStatus?.didReceiveConsentURL(consentURL)
        } catch {
            Logging.network.debug("Failed to decode SignatureResponse with \(error)")
        }
    }
    
    private func processRetrieveSignatureSuccess(with data: Data?) {
        guard let responseData = data else {
            return
        }
        
        do {
            let decodedResponse = try JSONDecoder().decode(SignatureRetrieveResponse.self,
                                                           from: responseData)
            retrieveResponse = decodedResponse
            signatureStatus?.didReceiveSignature(data: decodedResponse.cms?.data(using: .utf8))
        } catch {
            Logging.network.debug("Failed to decode SignatureRetrieveResponse with \(error)")
        }
    }
}

// MARK: - SignaturePayload
private struct SignaturePayload: Codable, Equatable {
    let documentID: String?
    let fileName: String?
    let hash: String?
    var jsonDictionary: [String : String]? {
        return makeJSONDictionary()
    }
    
    private enum CodingKeys: String, CodingKey {
        case documentID = "documentId"
        case fileName = "name"
        case hash = "hash"
    }
    
    private func makeJSONDictionary() -> [String : String]? {
        let signaturePayload = SignaturePayload(documentID: documentID,
                                                fileName: fileName,
                                                hash: hash)
        guard
            let jsonData = try? JSONEncoder().encode(signaturePayload),
            let payload = try? JSONDecoder().decode([String : String].self, from: jsonData)
        else {
            return nil
        }
        return payload
    }
}

// MARK: - SignatureResponse
private struct SignatureResponse: Codable, Equatable {
    let responseId: String?
    let consentURL: URL?
    
    private enum CodingKeys: String, CodingKey {
        case consentURL = "consentURL"
        case responseId = "responseId"
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        responseId = try container.decodeIfPresent(String.self, forKey: .responseId)
        guard
            let consentURLString = try container.decodeIfPresent(String.self, forKey: .consentURL),
            let url = URL(string: consentURLString)
        else {
            consentURL = nil
            return
        }
        
        consentURL = url
    }
}

// MARK: - SignatureRetrieveResponse
private struct SignatureRetrieveResponse: Codable, Equatable {
    let documentId: String?
    let cms: String?
}
