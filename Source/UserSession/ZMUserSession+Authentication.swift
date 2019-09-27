//
// Wire
// Copyright (C) 2019 Wire Swiss GmbH
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

extension ZMUserSession {
    
    public func logout(credentials: ZMEmailCredentials, _ completion: @escaping (VoidResult) -> Void) {
        guard let selfClientIdentifier = ZMUser.selfUser(inUserSession: self).selfClient()?.remoteIdentifier else { return }
        
        let payload: [String: Any]
        if let password = credentials.password, !password.isEmpty {
            payload = ["password": password]
        } else {
            payload = [:]
        }
        
        let request = ZMTransportRequest(path: "/clients/\(selfClientIdentifier)", method: .methodDELETE, payload: payload as ZMTransportData)
        
        request.add(ZMCompletionHandler(on: managedObjectContext, block: {[weak self] (response) in
            guard let strongSelf = self else { return }
            
            if response.httpStatus == 200 {
                PostLoginAuthenticationNotification.notifyUserDidLogout(context: strongSelf.managedObjectContext)
                completion(.success)
            } else {
                completion(.failure(strongSelf.errorFromFailedDeleteResponse(response)))
            }
        }))
        
        transportSession.enqueueOneTime(request)
    }
    
    func errorFromFailedDeleteResponse(_ response: ZMTransportResponse!) -> NSError {
        
        var errorCode: ZMUserSessionErrorCode
        switch response.result {
        case .permanentError:
                switch response.payload?.asDictionary()?["label"] as? String {
                case "client-not-found":
                    errorCode = .clientDeletedRemotely
                    break
                case "invalid-credentials",
                     "missing-auth",
                     "bad-request": // in case the password not matching password format requirement
                    errorCode = .invalidCredentials
                    break
                default:
                    errorCode = .unknownError
                    break
                }
        case .temporaryError, .tryAgainLater, .expired:
            errorCode = .networkError
        default:
            errorCode = .unknownError
        }
        
        var userInfo: [String: Any]? = nil
        if let transportSessionError = response.transportSessionError {
            userInfo = [NSUnderlyingErrorKey: transportSessionError]
        }
        
        return NSError(code: errorCode, userInfo: userInfo)
    }   
    
}
