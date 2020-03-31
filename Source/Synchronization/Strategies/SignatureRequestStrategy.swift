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

// Sign a PDF document
@objc
public final class SignatureRequestStrategy: AbstractRequestStrategy {
    
    // MARK: - Private Property
    private weak var signatureStatus: SignatureStatus?
    private var requestSync: ZMSingleRequestSync?
    private let moc: NSManagedObjectContext
    private var signatureResponse: SignatureResponse?

    // MARK: - AbstractRequestStrategy
    @objc
    public override init(withManagedObjectContext managedObjectContext: NSManagedObjectContext,
                         applicationStatus: ApplicationStatus) {
        
        self.moc = managedObjectContext
        super.init(withManagedObjectContext: managedObjectContext,
                   applicationStatus: applicationStatus)
        self.requestSync = ZMSingleRequestSync(singleRequestTranscoder: self,
                                               groupQueue: moc)
    }
    
    @objc
    public override func nextRequestIfAllowed() -> ZMTransportRequest? {
        signatureStatus = signatureStatusPublic
        guard let status = signatureStatus else { return nil }
        
        switch status.state {
        case .initial:
            break
         case .waitingForURL:
            guard let requestSync = requestSync else {
                return nil
            }
            requestSync.readyForNextRequestIfNotBusy()
            return requestSync.nextRequest()
        case .waitingForSignature:
            // TODO: get request (to get Signature)
            break
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
        
        let path = "/signature/request"

        return ZMTransportRequest(path: path,
                                  method: .methodPOST,
                                  payload: payload as ZMTransportData)
    }
    
    public func didReceive(_ response: ZMTransportResponse,
                           forSingleRequest sync: ZMSingleRequestSync) {
        switch sync {
        case requestSync:
            switch (response.result) {
                case .success:
                    processSuccess(with: response.rawData)
                case .temporaryError,
                     .tryAgainLater,
                     .expired:
                    break
                case .permanentError:
                    signatureStatusPublic?.state = .signatureInvalid
                default:
                    signatureStatusPublic?.state = .signatureInvalid
            }
        default:
            break
        }
    }
    
    // MARK: - Helpers
    private func processSuccess(with data: Data?) {
        guard let responseData = data else {
            return
        }
        
        do {
            let decodedResponse = try JSONDecoder().decode(SignatureResponse.self, from: responseData)
            signatureResponse = decodedResponse
            guard let consentURL = signatureResponse?.consentURL else {
                return
            }
            signatureStatus?.didReceiveURL(consentURL)
        } catch {
            print(error)
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
