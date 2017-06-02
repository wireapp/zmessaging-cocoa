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


#import "ZMBareUser+UserSession.h"
#import "ZMUserSession+Internal.h"

@implementation ZMUser (UserSession)

- (void)requestMediumProfileImageInUserSession:(ZMUserSession *)userSession;
{
    NOT_USED(userSession);
    
    if (self.imageMediumData != nil) {
        return;
    }
    
    [self requestCompleteAsset];
    
    if (self.localMediumRemoteIdentifier != nil) {
        self.localMediumRemoteIdentifier = nil;
        ZMSDispatchGroup *group = [ZMSDispatchGroup groupWithLabel:@"ZMUser"];
        [self.managedObjectContext enqueueDelayedSaveWithGroup:group];
        
        [group notifyOnQueue:dispatch_get_main_queue() block:^{
            [UserImageStrategy requestAssetForUserWith:self.objectID];
            [ZMRequestAvailableNotification notifyNewRequestsAvailable:self];
        }];
    } else {
        [UserImageStrategy requestAssetForUserWith:self.objectID];
        [ZMRequestAvailableNotification notifyNewRequestsAvailable:self];
    }
}

- (void)requestSmallProfileImageInUserSession:(ZMUserSession *)userSession;
{
    NOT_USED(userSession);
    
    if (self.imageSmallProfileData != nil) {
        return;
    }
    
    [self requestPreviewAsset];

    if (self.localSmallProfileRemoteIdentifier != nil) {
        self.localSmallProfileRemoteIdentifier = nil;
        ZMSDispatchGroup *group = [ZMSDispatchGroup groupWithLabel:@"ZMUser"];
        [self.managedObjectContext enqueueDelayedSaveWithGroup:group];
        
        [group notifyOnQueue:dispatch_get_main_queue() block:^{
            [UserImageStrategy requestSmallAssetForUserWith:self.objectID];
            [ZMRequestAvailableNotification notifyNewRequestsAvailable:self];
        }];
    } else {
        [UserImageStrategy requestSmallAssetForUserWith:self.objectID];
        [ZMRequestAvailableNotification notifyNewRequestsAvailable:self];
    }
}

@end
