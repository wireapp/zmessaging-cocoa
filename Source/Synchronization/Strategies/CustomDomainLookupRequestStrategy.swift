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

import Foundation

private let customDomainEndpoint = "/custom-instance/by-domain"
private let customDomainKey = "customDomain"
private let customDomainResultKey = "customSomainLookupResult"
private let customDomainNotFoundResponseLabel = "custom-instance-not-found"

private extension NSNotification.Name {
    static let verifyCustomDomain = NSNotification.Name(rawValue: "VerifyCustomDomainNotification")
    static let customDomainVerified = NSNotification.Name(rawValue: "CustomDomainVerified")
}

public enum DomainLookupResult: Equatable {
    case notFound
    case parsingError
    case error(httpCode: Int, label: String?)
    case found(CustomDomainInformation)
}

public final class CustomDomainLookupRequestStrategy: AbstractRequestStrategy {
    
    /// Request sync
    private var requestSync: ZMSingleRequestSync!
    private var domainToLookup: String?
    private let moc: NSManagedObjectContext
    private var observerToken: Any?

    @objc public override init(withManagedObjectContext moc: NSManagedObjectContext, applicationStatus: ApplicationStatus) {
        self.moc = moc
        super.init(withManagedObjectContext: moc, applicationStatus: applicationStatus)
        self.requestSync = ZMSingleRequestSync(singleRequestTranscoder: self, groupQueue: moc)
        
        observerToken = NotificationInContext.addObserver(
            name: .verifyCustomDomain,
            context: moc.notificationContext,
            using: { [weak self] notification in
                self?.prepareDomainLookup(notification)
            })
    }
    
    private func prepareDomainLookup(_ notification: NotificationInContext) {
        self.domainToLookup = notification.userInfo[customDomainKey] as? String
        self.requestSync.readyForNextRequestIfNotBusy()
        RequestAvailableNotification.notifyNewRequestsAvailable(self)
    }
    
    public override func nextRequestIfAllowed() -> ZMTransportRequest? {
        guard domainToLookup != nil else {
            return nil
        }
        return self.requestSync.nextRequest()
    }
    
    static func triggerDomainLookup(domain: String, completion: @escaping (DomainLookupResult?) -> Void, context moc: NSManagedObjectContext) {
        var observerToken: Any?
        observerToken = NotificationInContext.addObserver(
            name: .customDomainVerified,
            context: moc.notificationContext,
            queue: .main,
            using: { notification in
                let result = notification.userInfo[customDomainResultKey] as? DomainLookupResult
                completion(result)
                _ = observerToken
                observerToken = nil
            })
        NotificationInContext(name: .verifyCustomDomain, context: moc.notificationContext, userInfo: [customDomainKey: domain]).post()
    }
    
    private static func notifyDomainLookupResponse(with result: DomainLookupResult, context moc: NSManagedObjectContext) {
        NotificationInContext(name: .customDomainVerified, context: moc.notificationContext, userInfo: [customDomainResultKey: result]).post()
    }
}

// MARK: - Request generation logic
extension CustomDomainLookupRequestStrategy: ZMSingleRequestTranscoder {
    
    public func request(for sync: ZMSingleRequestSync) -> ZMTransportRequest? {
        guard sync == self.requestSync, let domain = self.domainToLookup else {
            return nil
        }
        
        let path = customDomainEndpoint + "/" + domain.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)!
        let request = ZMTransportRequest(path: path, method: .methodGET, payload: nil)
        return request
    }
    
    public func didReceive(_ response: ZMTransportResponse, forSingleRequest sync: ZMSingleRequestSync) {
        let result: DomainLookupResult
        switch response.httpStatus {
        case 200..<300: // OK
            guard
                let data = response.rawData,
                let info = try? JSONDecoder().decode(CustomDomainInformation.self, from: data) else {
                result = .parsingError
                break
            }
            result = .found(info)
        case 404 where response.payload?.errorLabel == customDomainNotFoundResponseLabel:
            result = .notFound
        default:
            result = .error(httpCode: response.httpStatus, label: response.payload?.errorLabel)
        }
        CustomDomainLookupRequestStrategy.notifyDomainLookupResponse(with: result, context: moc)
        self.requestSync.resetCompletionState()
    }
}

public struct CustomDomainInformation: Codable, Equatable {
    let configJson: URL
    
    enum CodingKeys: String, CodingKey {
        case configJson = "config_json"
    }
}

private extension ZMTransportData {
    
    var errorLabel: String? {
        guard let payload = self as? [String: Any] else { return nil }
        return payload["label"] as? String
    }
}
