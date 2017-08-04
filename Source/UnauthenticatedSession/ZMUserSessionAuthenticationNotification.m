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


#import <WireDataModel/ZMNotifications+Internal.h>
#import "ZMUserSessionAuthenticationNotification.h"
#import "ZMUserSession+Registration.h"

static NSString *const UserSessionAuthenticationNotificationName =  @"ZMUserSessionAuthenticationNotificationName";


@implementation ZMUserSessionAuthenticationNotification

- (instancetype)init
{
    return [super initWithName:UserSessionAuthenticationNotificationName object:nil];
}


+ (void)notifyAuthenticationDidFail:(NSError *)error
{
    NSCParameterAssert(error);
    ZMUserSessionAuthenticationNotification *note = [ZMUserSessionAuthenticationNotification new];
    note.error = error;
    note.type = ZMAuthenticationNotificationAuthenticationDidFail;
    [[NSNotificationCenter defaultCenter] postNotification:note];
}

+ (void)notifyAuthenticationDidSucceed
{
    ZMUserSessionAuthenticationNotification *note = [ZMUserSessionAuthenticationNotification new];
    note.type = ZMAuthenticationNotificationAuthenticationDidSuceeded;
    [[NSNotificationCenter defaultCenter] postNotification:note];
}

+ (void)notifyLoginCodeRequestDidFail:(NSError *)error
{
    NSCParameterAssert(error);
    ZMUserSessionAuthenticationNotification *note = [ZMUserSessionAuthenticationNotification new];
    note.error = error;
    note.type = ZMAuthenticationNotificationLoginCodeRequestDidFail;
    [[NSNotificationCenter defaultCenter] postNotification:note];
}

+ (void)notifyLoginCodeRequestDidSucceed
{
    ZMUserSessionAuthenticationNotification *note = [ZMUserSessionAuthenticationNotification new];
    note.type = ZMAuthenticationNotificationLoginCodeRequestDidSucceed;
    [[NSNotificationCenter defaultCenter] postNotification:note];
}

+ (void)notifyDidRegisterClient
{
    ZMUserSessionAuthenticationNotification *note = [ZMUserSessionAuthenticationNotification new];
    note.type = ZMAuthenticationNotificationDidRegisterClient;
    [[NSNotificationCenter defaultCenter] postNotification:note];
}

+ (void)notifyDidDetectSelfClientDeletion
{
    ZMUserSessionAuthenticationNotification *note = [ZMUserSessionAuthenticationNotification new];
    note.type = ZMAuthenticationNotificationDidDetectSelfClientDeletion;
    [[NSNotificationCenter defaultCenter] postNotification:note];
}

+ (id<ZMAuthenticationObserverToken>)addObserverWithBlock:(void (^)(ZMUserSessionAuthenticationNotification *))block
{
    NSCParameterAssert(block);
    return (id<ZMAuthenticationObserverToken>)[[NSNotificationCenter defaultCenter] addObserverForName:UserSessionAuthenticationNotificationName object:nil queue:[NSOperationQueue currentQueue] usingBlock:^(NSNotification *note) {
        block((ZMUserSessionAuthenticationNotification *)note);
    }];
}

+ (void)removeObserverForToken:(id<ZMAuthenticationObserverToken>)token
{
    [[NSNotificationCenter defaultCenter] removeObserver:token name:UserSessionAuthenticationNotificationName object:nil];
}

@end
