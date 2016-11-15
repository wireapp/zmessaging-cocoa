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


@import ZMCDataModel;
#import "ZMUserSession+Internal.h"
#import "ZMUserSession+EditingVerification.h"
#import <zmessaging/zmessaging-Swift.h>

@implementation ZMUserSession (EditingVerification)

- (id<ZMUserEditingObserverToken>)addUserEditingObserver:(id<ZMUserEditingObserver> __unused)observer {
    // TODO MARCO
    /*
    return (id)[ZMUserProfileUpdateNotification addObserverWithBlock:^(ZMUserProfileUpdateNotification *note) {
        switch(note.type) {
            case ZMUserProfileNotificationEmailUpdateDidFail:
                [observer emailUpdateDidFail:note.error];
                break;
            case ZMUserProfileNotificationPhoneNumberVerificationCodeRequestDidFail:
                [observer phoneNumberVerificationCodeRequestDidFail:note.error];
                break;
            case ZMUserProfileNotificationPhoneNumberVerificationDidFail:
                [observer phoneNumberVerificationDidFail:note.error];
                break;
            case ZMUserProfileNotificationPasswordUpdateDidFail:
                [observer passwordUpdateRequestDidFail];
                break;
            case ZMUserProfileNotificationPhoneNumberVerificationCodeRequestDidSucceed:
                [observer phoneNumberVerificationCodeRequestDidSucceed];
                break;
            case ZMUserProfileNotificationEmailDidSendVerification:
                [observer didSentVerificationEmail];
                break;
        }
    }];
     */
    return nil;
}

- (void)removeUserEditingObserverForToken:(id<ZMUserEditingObserverToken> __unused)observerToken {
    // TODO MARCO
    // [ZMUserProfileUpdateNotification removeObserver:(id)observerToken];
}

@end
