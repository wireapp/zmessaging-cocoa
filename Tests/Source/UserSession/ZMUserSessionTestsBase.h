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


#import <CoreData/CoreData.h>
#import <ZMTransport/ZMTransport.h>
#import <ZMCDataModel/ZMCDataModel.h>

#import "MessagingTest.h"
#import "ZMUserSession+Internal.h"
# import "ZMUserSession+Background.h"
# import "ZMUserSession+UserNotificationCategories.h"
# import "ZMUserSession+Authentication.h"
# import "ZMUserSession+Registration.h"
# import "ZMUserSessionAuthenticationNotification.h"
# import "ZMUserSessionRegistrationNotification.h"

#import "ZMOperationLoop+Background.h"
#import "ZMLocalNotification.h"
#import "NSError+ZMUserSessionInternal.h"
#import "ZMCredentials.h"
#import "ZMSyncStrategy.h"
#import "ZMOperationLoop.h"
#import "ZMFlowSync.h"
#import "ZMPushToken.h"
#import "ZMCommonContactsSearch.h"

#import "ZMCredentials.h"
#import "NSURL+LaunchOptions.h"

#import <zmessaging/ZMAuthenticationStatus.h>

@interface ThirdPartyServices : NSObject <ZMThirdPartyServicesDelegate>

@property (nonatomic) NSUInteger uploadCount;

@end



@interface ZMUserSessionTestsBase : MessagingTest <ZMAuthenticationStatusObserver>

@property (nonatomic) id transportSession;
@property (nonatomic) ZMPersistentCookieStorage *cookieStorage;
@property (nonatomic) NSData *validCookie;
@property (nonatomic, copy) ZMCompletionHandlerBlock authFailHandler;
@property (nonatomic, copy) ZMAccessTokenHandlerBlock tokenSuccessHandler;
@property (nonatomic) NSURL *baseURL;
@property (nonatomic) ZMUserSession *sut;
@property (nonatomic) ZMSyncStrategy *syncStrategy;
@property (nonatomic) id mediaManager;
@property (nonatomic) NSUInteger dataChangeNotificationsCount;
@property (nonatomic) ThirdPartyServices *thirdPartyServices;
@property (nonatomic) id operationLoop;
@property (nonatomic) id application;
@property (nonatomic) id apnsEnvironment;
@property (nonatomic) NSTimeInterval backgroundFetchInterval;

@property (nonatomic) id<ZMAuthenticationObserver> authenticationObserver;
@property (nonatomic) id<ZMRegistrationObserver> registrationObserver;

@end
