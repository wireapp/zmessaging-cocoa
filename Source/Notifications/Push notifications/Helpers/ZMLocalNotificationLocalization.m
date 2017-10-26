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

@import WireDataModel;
#import "ZMLocalNotificationLocalization.h"
#import "ZMUserSession.h"
#import "WireSyncEngine/WireSyncEngine-Swift.h"

static NSString *localizedStringWithKeyAndArguments(NSString *key, NSArray *arguments);
static NSString * ZMPushLocalizedString(NSString *key);

static NSString *const OneOnOneKey = @"oneonone";
static NSString *const GroupKey = @"group";

static NSString *const SelfKey = @"self";
static NSString *const NoConversationNameKey = @"noconversationname";
static NSString *const NoUserNameKey = @"nousername";
static NSString *const NoOtherUserNameKey = @"nootherusername";
static NSString *const NoTeamNameKey = @"noteamname";



@implementation NSString (ZMLocalNotificationLocalization)

- (NSString *)localizedStringWithUser:(ZMUser *)user conversation:(ZMConversation *)conversation otherUser:(ZMUser *)otherUser;
{
    NSString *userName = user.name;
    NSString *conversationName = conversation.userDefinedName;
    NSString *otherUserName = otherUser.name;
    
    NSMutableArray *keyComponents = [NSMutableArray array];
    NSMutableArray *arguments = [NSMutableArray array];
    
    if (otherUser.isSelfUser) {
        [keyComponents addObject:SelfKey];
    }
    else if (otherUserName == nil) {
        [keyComponents addObject:NoOtherUserNameKey];
    }
    
    if (userName == nil)
    {
        [keyComponents addObject:NoUserNameKey];
    } else {
        [arguments addObject:userName];
    }
    
    if (conversationName == nil) {
        [keyComponents addObject:NoConversationNameKey];
    }
    
    NSString *key = self;
    for (NSString *component in keyComponents) {
        key = [key stringByAppendingPathExtension:component];
    }
    
    return localizedStringWithKeyAndArguments(ZMPushLocalizedString(key), arguments);
}

- (NSString *)localizedStringWithUser:(ZMUser *)user conversation:(ZMConversation *)conversation count:(NSNumber *)count formattedCount:(NSString *)formattedCount;
{
    return [self localizedStringWithUser:user conversation:conversation count:count formattedCountOrText:formattedCount];
}

- (NSString *)localizedStringWithUser:(ZMUser *)user conversation:(ZMConversation *)conversation text:(NSString *)text;
{
    return [self localizedStringWithUser:user conversation:conversation count:nil formattedCountOrText:text];
}

- (NSString *)localizedStringWithUser:(ZMUser *)user conversation:(ZMConversation *)conversation count:(NSNumber *)count formattedCountOrText:(NSString *)text;
{
    LocalizationInfo *localizationInfo = [self localizationInfoForUser:user conversation:conversation];
    
    NSString *key = localizationInfo.localizationString;
    NSMutableArray *arguments = [localizationInfo.arguments mutableCopy];
    if (count != nil) {
        [arguments addObject:count];
    }
    if (text != nil) {
        [arguments addObject:text];
    }
    return localizedStringWithKeyAndArguments(ZMPushLocalizedString(key), arguments);
}

- (NSString *)localizedStringWithUser:(ZMUser *)user conversation:(ZMConversation *)conversation count:(NSNumber *)count;
{
    LocalizationInfo *localizationInfo = [self localizationInfoForUser:user conversation:conversation];
    NSString *key = localizationInfo.localizationString;
    NSMutableArray *arguments = [localizationInfo.arguments mutableCopy];
    if (count != nil) {
        [arguments addObject:count];
    }
    return localizedStringWithKeyAndArguments(ZMPushLocalizedString(key), arguments);
}

- (NSString *)localizedStringWithUser:(ZMUser *)user conversation:(ZMConversation *)conversation;
{
    return [self localizedStringWithUser:user conversation:conversation text:nil];
}

- (NSString *)localizedStringWithUser:(ZMUser *)user count:(NSNumber *)count text:(NSString *)text;
{
    NSString *userName = user.name;
    NSMutableArray *arguments = [NSMutableArray array];
    
    NSString *key = self;
    if (userName == nil) {
        key = [key stringByAppendingPathExtension:NoUserNameKey];
    } else {
        [arguments addObject:userName];
    }
    
    if (count != nil) {
        [arguments addObject:count];
    }
    
    if (text != nil) {
        [arguments addObject:text];
    }
    
    return localizedStringWithKeyAndArguments(ZMPushLocalizedString(key), arguments);
}

- (NSString *)localizedStringWithUser:(ZMUser *)user count:(NSNumber *)count
{
    NSString *userName = user.name;
    NSMutableArray *arguments = [NSMutableArray array];
    
    NSString *key = self;
    if (userName == nil) {
        key = [key stringByAppendingPathExtension:NoUserNameKey];
    } else {
        [arguments addObject:userName];
    }
    
    if (count != nil) {
        [arguments addObject:count];
    }
    return localizedStringWithKeyAndArguments(ZMPushLocalizedString(key), arguments);
}


- (NSString *)localizedStringWithConversation:(ZMConversation *)conversation count:(NSNumber *)count text:(NSString *)text;
{
    NSString *conversationName = conversation.userDefinedName;
    NSMutableArray *arguments = [NSMutableArray array];

    NSString *key = self;
    if (conversationName == nil) {
        key = [key stringByAppendingPathExtension:NoConversationNameKey];
    } else {
        [arguments addObject:conversationName];
    }
    
    if (count != nil) {
        [arguments addObject:count];
    }
    if (text != nil) {
        [arguments addObject:text];
    }
    
    return localizedStringWithKeyAndArguments(ZMPushLocalizedString(key), arguments);
}

- (NSString *)localizedStringWithConversation:(ZMConversation *)conversation count:(NSNumber *)count;
{
    NSString *conversationName = conversation.userDefinedName;
    NSMutableArray *arguments = [NSMutableArray array];
    
    NSString *key = self;
    if (conversationName == nil) {
        key = [key stringByAppendingPathExtension:NoConversationNameKey];
    } else {
        [arguments addObject:conversationName];
    }
    
    if (count != nil) {
        [arguments addObject:count];
    }
    
    return localizedStringWithKeyAndArguments(ZMPushLocalizedString(key), arguments);
}

- (NSString *)localizedStringWithUser:(ZMUser *)user conversation:(ZMConversation *)conversation emoji:(NSString *)emoji;
{
    LocalizationInfo *localizationInfo = [self localizationInfoForUser:user conversation:conversation];
    NSString *key = localizationInfo.localizationString;
    NSMutableArray *arguments = [localizationInfo.arguments mutableCopy];
    [arguments addObject:emoji];
        
    return localizedStringWithKeyAndArguments(ZMPushLocalizedString(key), arguments);
}


- (NSString *)localizedStringWithUserName:(NSString *)userName;
{
    NSMutableArray *arguments = [NSMutableArray array];
    NSString *key = self;

    if (userName == nil) {
        key = [key stringByAppendingPathExtension:NoUserNameKey];
    }
    else {
        [arguments addObject:userName];
    }
    return localizedStringWithKeyAndArguments(ZMPushLocalizedString(key), arguments);
}

- (NSString *)localizedStringForPushNotification;
{
    return localizedStringWithKeyAndArguments(ZMPushLocalizedString(self), nil);
}

- (NSString *)localizedStringWithConversationName:(NSString *)conversationName teamName:(NSString *)teamName
{
    NSMutableArray *arguments = [NSMutableArray array];
    NSString *key = self;
    
    if (conversationName == nil) {
        key = [key stringByAppendingPathExtension:NoConversationNameKey];
    }
    else {
        [arguments addObject:conversationName];
    }
    
    if (teamName == nil) {
        key = [key stringByAppendingPathExtension:NoTeamNameKey];
    }
    else {
        [arguments addObject:teamName];
    }
    
    if (arguments.count == 0) {
        return nil;
    }
    
    return localizedStringWithKeyAndArguments(ZMPushLocalizedString(key), arguments);
}


@end




static NSString * ZMPushLocalizedString(NSString *key)
{
    return [[NSBundle bundleForClass:[ZMUserSession class]] localizedStringForKey:[@"push.notification." stringByAppendingString:key] value:@"" table:@"Push"];
}

static NSString *localizedStringWithKeyAndArguments(NSString *key, NSArray *arguments)
{
    switch(arguments.count) {
        case 0:
            return [NSString localizedStringWithFormat:key, nil];
        case 1:
            return [NSString localizedStringWithFormat:key, arguments[0]];
        case 2:
            return [NSString localizedStringWithFormat:key, arguments[0], arguments[1]];
        case 3:
            return [NSString localizedStringWithFormat:key, arguments[0], arguments[1], arguments[2]];
        default:
            return [NSString localizedStringWithFormat:key, arguments[0], arguments[1], arguments[2], arguments[3]];
    }
}
