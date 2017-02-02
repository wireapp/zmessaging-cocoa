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


@import ZMTransport;
@import ZMUtilities;
@import ZMCDataModel;

#import "ZMBareUser+UserSession.h"
#import "ZMUserSession+Internal.h"


@interface ZMSearchUser (MediumImage_Private)

- (void)privateRequestMediumProfileImageInUserSession:(ZMUserSession *)userSession;

@end



@implementation ZMSearchUser (UserSession)

- (id<ZMCommonContactsSearchToken>)searchCommonContactsInUserSession:(id)session withDelegate:(id<ZMCommonContactsSearchDelegate>)delegate
{
    return [session searchCommonContactsWithUserID:self.remoteIdentifier searchDelegate:delegate];
}

- (void)requestMediumProfileImageInUserSession:(ZMUserSession *)userSession
{
    [self privateRequestMediumProfileImageInUserSession:userSession];
}

- (void)requestSmallProfileImageInUserSession:(ZMUserSession *)userSession
{
    if(self.user) {
        [self.user requestSmallProfileImageInUserSession:userSession];
    }
}

@end



@implementation ZMSearchUser (MediumImage_Private)

- (void)privateRequestMediumProfileImageInUserSession:(ZMUserSession *)userSession;
{
    if (self.imageMediumData != nil) {
        [self setAndNotifyNewMediumImageData:self.imageMediumData searchUserObserverCenter:userSession.managedObjectContext.searchUserObserverCenter];
        return;
    }
    
    ZMTransportRequest *request;
    if (self.imageSmallProfileData != nil && self.mediumAssetID == nil) {
        request = [self requestUserInfoInUserSession:userSession];
    } else if (self.mediumAssetID != nil) {
        request = [self requestMediumProfileImageWithExistingMediumAssetIDInUserSession:userSession];
    }
    
    if (request == nil) {
        return;
    }
    
    ZMTransportSession *session = userSession.transportSession;
    Require(session != nil);
    [session enqueueSearchRequest:request];
}

- (ZMTransportRequest *)requestUserInfoInUserSession:(ZMUserSession *)userSession
{
    ZMCompletionHandler *completionHandler = [ZMCompletionHandler handlerOnGroupQueue:userSession.syncManagedObjectContext block:^(ZMTransportResponse *response) {
        [SearchUserImageStrategy processSingleUserProfileWithResponse:response for:self.remoteIdentifier mediumAssetIDCache:[ZMSearchUser searchUserToMediumAssetIDCache]];
        if (self.mediumAssetID != nil) {
            [self privateRequestMediumProfileImageInUserSession:userSession];
        }
    }];
    ZMTransportRequest *request = [SearchUserImageStrategy requestForFetchingAssetsFor:[NSSet setWithObject:self.remoteIdentifier] completionHandler:completionHandler];
    
    return request;
}

- (ZMTransportRequest *)requestMediumProfileImageWithExistingMediumAssetIDInUserSession:(ZMUserSession *)userSession
{
    ZMTransportRequest *request = [UserImageStrategy requestForFetchingAssetWith:self.mediumAssetID forUserWith:self.remoteIdentifier];
    ZM_WEAK(self);
    [request addCompletionHandler:[ZMCompletionHandler handlerOnGroupQueue:userSession.syncManagedObjectContext block:^(ZMTransportResponse *response) {
        ZM_STRONG(self);
        [self processMediumAssetResponse:response inUserSession:userSession];
    }]];
    
    return request;
}

- (void)processMediumAssetResponse:(ZMTransportResponse *)response inUserSession:(ZMUserSession *)userSession
{
    if(response.result == ZMTransportResponseStatusSuccess) {
        if(response.imageData != 0) {
            [[ZMSearchUser searchUserToMediumImageCache] setObject:response.imageData forKey:self.remoteIdentifier];
            [userSession.managedObjectContext performGroupedBlock:^{
                [self setAndNotifyNewMediumImageData:response.imageData searchUserObserverCenter:userSession.managedObjectContext.searchUserObserverCenter];
            }];
        }
    }
}

@end
