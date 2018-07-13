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


@import WireTransport;
@import WireUtilities;
@import WireDataModel;

#import "ZMBareUser+UserSession.h"
#import "ZMUserSession+Internal.h"


@interface ZMSearchUser (MediumImage_Private)

- (void)privateRequestMediumProfileImageInUserSession:(ZMUserSession *)userSession;

@end



@implementation ZMSearchUser (UserSession)

- (void)requestMediumProfileImageInUserSession:(ZMUserSession *)userSession
{
    if (self.user) {
        [self.user requestMediumProfileImageInUserSession:userSession];
    } else {
        [self privateRequestMediumProfileImageInUserSession:userSession];
    }
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
    if (self.imageSmallProfileData != nil && self.mediumLegacyId == nil && self.completeAssetKey == nil) {
        request = [self requestUserInfoInUserSession:userSession];
    } else if (self.completeAssetKey != nil || self.mediumLegacyId != nil) {
        request = [self requestMediumProfileImageWithExistingAssetKeysInUserSession:userSession];
    }

    if (request == nil) {
        return;
    }
    
    ZMTransportSession *session = userSession.transportSession;
    Require(session != nil);
    [session enqueueOneTimeRequest:request];
}

- (ZMTransportRequest *)requestUserInfoInUserSession:(ZMUserSession *)userSession
{
    NSUUID *remoteIdentifier = self.remoteIdentifier;
    ZMCompletionHandler *completionHandler = [ZMCompletionHandler handlerOnGroupQueue:userSession.syncManagedObjectContext block:^(ZMTransportResponse *response) {
        [SearchUserImageStrategy processSingleUserProfileWithResponse:response
                                                                  for:remoteIdentifier
                                                   mediumAssetIDCache:ZMSearchUser.searchUserToMediumAssetIDCache];
        [userSession.managedObjectContext performGroupedBlock:^{
            if (self.mediumLegacyId != nil || self.completeAssetKey != nil) {
                [self privateRequestMediumProfileImageInUserSession:userSession];
            }
        }];
    }];
    ZMTransportRequest *request = [SearchUserImageStrategy requestForFetchingAssetsFor:[NSSet setWithObject:self.remoteIdentifier] completionHandler:completionHandler];
    
    return request;
}

- (ZMTransportRequest *)requestMediumProfileImageWithExistingAssetKeysInUserSession:(ZMUserSession *)userSession
{
    ZMTransportRequest *request;
    if (self.completeAssetKey != nil) { // V3
        request = [UserImageStrategy requestForFetchingV3AssetWith:self.completeAssetKey];
    } else if (self.mediumLegacyId != nil) { // Legacy
        request = [UserImageStrategy requestForFetchingAssetWith:self.mediumLegacyId forUserWith:self.remoteIdentifier];
    }

    ZM_WEAK(self);
    NSUUID *remoteIdentifier = self.remoteIdentifier;
    [request addCompletionHandler:[ZMCompletionHandler handlerOnGroupQueue:userSession.syncManagedObjectContext block:^(ZMTransportResponse *response) {
        ZM_STRONG(self);
        [self processMediumAssetResponse:response inUserSession:userSession remoteIdentifier:remoteIdentifier];
    }]];

    return request;

}

- (void)processMediumAssetResponse:(ZMTransportResponse *)response inUserSession:(ZMUserSession *)userSession remoteIdentifier:(NSUUID *)remoteIdentifier
{
    if(response.result == ZMTransportResponseStatusSuccess) {
        NSData *imageData = response.imageData ?: response.rawData;
        if (imageData != 0) {
            [[ZMSearchUser searchUserToMediumImageCache] setObject:imageData forKey:remoteIdentifier];
            [userSession.managedObjectContext performGroupedBlock:^{
                [self setAndNotifyNewMediumImageData:imageData searchUserObserverCenter:userSession.managedObjectContext.searchUserObserverCenter];
            }];
        }
    }
}

@end
