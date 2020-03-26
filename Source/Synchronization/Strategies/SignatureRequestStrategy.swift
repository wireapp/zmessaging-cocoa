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

// Sign a PDF document
@objc public final class SignatureRequestStrategy: AbstractRequestStrategy {
    
   weak var signatureStatus: SignatureStatus?
    
//   private var requestSync: ZMSingleRequestSync!
//   private let moc: NSManagedObjectContext

    public init(withManagedObjectContext managedObjectContext: NSManagedObjectContext,
                         applicationStatus: ApplicationStatus,
                         signatureStatus: SignatureStatus) {
        
        super.init(withManagedObjectContext: managedObjectContext,
                   applicationStatus: applicationStatus)
        
        self.signatureStatus = signatureStatus
//        self.moc = moc
//        self.requestSync = ZMSingleRequestSync(singleRequestTranscoder: self, groupQueue: moc)
    }
    
    @objc public override func nextRequestIfAllowed() -> ZMTransportRequest? {
        guard let status = self.signatureStatus else { return nil }
        
        switch status.state {
        case .initial:
            break
         case .waitingForURL:
            // TO DO: post request (to get URL)
            break
        case .waitingForSignature:
            // TO DO: get request (to get Signature)
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

//extension SignatureRequestStrategy : ZMUpstreamTranscoder {
//}




@objc(ZMSignatureObserver)
public protocol SignatureObserver: NSObjectProtocol {
    func urlAvailable(_ url: URL)
    func signatureAvailable(_ signature: Data) //FIX ME: type of the file
    func signatureInvalid(_ error: Error)
}
