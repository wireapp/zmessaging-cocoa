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
    
    private weak var signatureStatus: SignatureStatus?
    private var requestSync: ZMSingleRequestSync?
    private let moc: NSManagedObjectContext
    private var consentURL: String?
    private var responseId: String?

    @objc
    public override init(withManagedObjectContext managedObjectContext: NSManagedObjectContext,
                         applicationStatus: ApplicationStatus
                         /*, signatureStatus: SignatureStatus*/) {
        
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
            signatureStatusPublic?.state = .pendingURL
            requestSync.readyForNextRequestIfNotBusy()
            return requestSync.nextRequest()
        case .pendingURL:
            // TODO:
            break
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

    func processResponse(_ response : ZMTransportResponse) {
        
    }
}

extension SignatureRequestStrategy: ZMSingleRequestTranscoder {
    public func request(for sync: ZMSingleRequestSync) -> ZMTransportRequest? {
        guard
            let encodedHash = signatureStatus?.encodedHash,
            let documentID = signatureStatus?.documentID,
            let fileName = signatureStatus?.fileName
        else {
            return nil
        }
        
        let payload: [String: String] = [
            "documentId": documentID,
            "name": fileName,
            "hash": encodedHash
        ]

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
                    guard let responseDictionary = response.payload?.asDictionary() else {
                        return
                    }
                    signatureStatusPublic?.state = .waitingForSignature
                    consentURL = responseDictionary["consentURL"] as? String
                    responseId = responseDictionary["responseId"] as? String
                case .permanentError,
                     .tryAgainLater,
                     .expired,
                     .temporaryError:
                    signatureStatusPublic?.state = .signatureInvalid
                default:
                    signatureStatusPublic?.state = .signatureInvalid
            }
        default:
            break
        }
    }
}

//@objc(ZMSignatureObserver)
//public protocol SignatureObserver: NSObjectProtocol {
//    func urlAvailable(_ url: URL)
//    func signatureAvailable(_ signature: Data) //FIX ME: type of the file
//    func signatureInvalid(_ error: Error)
//}
