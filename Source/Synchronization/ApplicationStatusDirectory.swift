//
// Wire
// Copyright (C) 2017 Wire Swiss GmbH
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
import CoreData
import WireMessageStrategy

@objc(ZMApplicationStatusDirectory)
public final class ApplicationStatusDirectory : NSObject, ApplicationStatus {
    
    public let userProfileImageUpdateStatus : UserProfileImageUpdateStatus
    public let apnsConfirmationStatus : BackgroundAPNSConfirmationStatus
    public let authenticationStatus : ZMAuthenticationStatus
    public let userProfileUpdateStatus : UserProfileUpdateStatus
    public let clientRegistrationStatus : ZMClientRegistrationStatus
    public let clientUpdateStatus : ClientUpdateStatus
    public let pingBackStatus : BackgroundAPNSPingBackStatus
    public let accountStatus : ZMAccountStatus
    public let proxiedRequestStatus : ProxiedRequestsStatus
    public let syncStatus : SyncStatus
    public let operationStatus : OperationStatus
    public let requestCancellation: ZMRequestCancellation
    
    fileprivate var callInProgressObserverToken : NSObjectProtocol? = nil
    
    public init(withManagedObjectContext managedObjectContext : NSManagedObjectContext, cookie : ZMCookie, requestCancellation: ZMRequestCancellation, application : Application, syncStateDelegate: ZMSyncStateDelegate) {
        self.requestCancellation = requestCancellation
        self.apnsConfirmationStatus = BackgroundAPNSConfirmationStatus(application: application, managedObjectContext: managedObjectContext, backgroundActivityFactory: BackgroundActivityFactory.sharedInstance())
        self.operationStatus = OperationStatus()
        self.operationStatus.isInBackground = application.applicationState == .background;
        self.syncStatus = SyncStatus(managedObjectContext: managedObjectContext, syncStateDelegate: syncStateDelegate)
        self.authenticationStatus = ZMAuthenticationStatus(managedObjectContext: managedObjectContext, cookie: cookie)
        self.userProfileUpdateStatus = UserProfileUpdateStatus(managedObjectContext: managedObjectContext)
        self.clientUpdateStatus = ClientUpdateStatus(syncManagedObjectContext: managedObjectContext)
        self.clientRegistrationStatus = ZMClientRegistrationStatus(managedObjectContext: managedObjectContext,
                                                                   loginCredentialProvider: authenticationStatus,
                                                                   update: userProfileUpdateStatus,
                                                                   cookie: cookie,
                                                                   registrationStatusDelegate: syncStateDelegate)
        self.accountStatus = ZMAccountStatus(managedObjectContext: managedObjectContext, cookieStorage: cookie)
        self.pingBackStatus = BackgroundAPNSPingBackStatus(syncManagedObjectContext: managedObjectContext, authenticationProvider: authenticationStatus)
        self.proxiedRequestStatus = ProxiedRequestsStatus(requestCancellation: requestCancellation)
        self.userProfileImageUpdateStatus = UserProfileImageUpdateStatus(managedObjectContext: managedObjectContext)
        
        super.init()
        
        callInProgressObserverToken = NotificationCenter.default.addObserver(forName: CallStateObserver.CallInProgressNotification, object: nil, queue: .main) { [weak self] (notification) in
            managedObjectContext.performGroupedBlock {
                if let callInProgress = notification.userInfo?[CallStateObserver.CallInProgressKey] as? Bool {
                    self?.operationStatus.hasOngoingCall = callInProgress
                }
            }
        }
    }
    
    deinit {
        if let token = callInProgressObserverToken {
            NotificationCenter.default.removeObserver(token)
        }
        
        apnsConfirmationStatus.tearDown()
        clientRegistrationStatus.tearDown()
        clientUpdateStatus.tearDown()
    }
    
    public var deliveryConfirmation: DeliveryConfirmationDelegate {
        return apnsConfirmationStatus
    }
    
    public var clientRegistrationDelegate: ClientRegistrationDelegate {
        return clientRegistrationStatus
    }
    
    public var operationState: OperationState {
        switch operationStatus.operationState {
        case .foreground:
            return .foreground
        case .background, .backgroundCall, .backgroundFetch, .backgroundTask:
            return .background
        }
    }
    
    public var synchronizationState: SynchronizationState {
        if !clientRegistrationStatus.clientIsReadyForRequests() {
            return .unauthenticated
        } else if syncStatus.isSyncing {
            return .synchronizing
        } else {
            return .eventProcessing
        }
    }
    
}
