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


#import "ZMUserSession+UserNotificationCategories.h"


NSString *const ZMConversationCategory = @"conversationCategory";
NSString *const ZMConversationCategoryIncludingLike = @"conversationCategoryWithLike";
NSString *const ZMConversationOpenAction = @"conversationOpenAction";
NSString *const ZMConversationDirectReplyAction = @"conversationDirectReplyAction";
NSString *const ZMConversationMuteAction = @"conversationMuteAction";

NSString *const ZMMessageLikeAction = @"messageLikeAction";

NSString *const ZMIncomingCallCategory = @"incomingCallCategory";
NSString *const ZMMissedCallCategory = @"missedCallCategory";

NSString *const ZMCallIgnoreAction = @"ignoreCallAction";
NSString *const ZMCallAcceptAction = @"acceptCallAction";

NSString *const ZMConnectCategory = @"connectCategory";
NSString *const ZMConnectAcceptAction = @"acceptConnectAction";


static NSString * ZMPushActionLocalizedString(NSString *key)
{
    return [[NSBundle bundleForClass:ZMUserSession.class] localizedStringForKey:[@"push.notification.action." stringByAppendingString:key] value:@"" table:@"Push"];
}

@implementation ZMUserSession (UserNotificationCategories)


- (UIMutableUserNotificationAction *)mutableAction:(NSString *)actionIdentifier
                                    activationMode:(UIUserNotificationActivationMode)activationMode
                                 localizedTitleKey:(NSString *)localizedTitleKey
{
    UIMutableUserNotificationAction *action = [[UIMutableUserNotificationAction alloc] init];
    action.identifier = actionIdentifier;
    action.title = [NSString localizedStringWithFormat:ZMPushActionLocalizedString(localizedTitleKey), nil];;
    action.destructive = NO;
    action.activationMode = activationMode;
    action.authenticationRequired = false;
    return action;
}

- (UIMutableUserNotificationAction *)mutableBackgroundAction:(NSString *)actionIdentifier localizedTitleKey:(NSString *)localizedTitleKey
{
    return [self mutableAction:actionIdentifier activationMode:UIUserNotificationActivationModeBackground localizedTitleKey:localizedTitleKey];
}


- (UIMutableUserNotificationAction *)mutableForegroundAction:(NSString *)actionIdentifier localizedTitleKey:(NSString *)localizedTitleKey
{
    return [self mutableAction:actionIdentifier activationMode:UIUserNotificationActivationModeForeground localizedTitleKey:localizedTitleKey];
}


- (UIUserNotificationCategory *)replyCategory
{
    return [self replyCategoryInlcudingLike:NO];
}

- (UIUserNotificationCategory *)replyCategoryIncludingLike
{
    return [self replyCategoryInlcudingLike:YES];
}

- (UIUserNotificationCategory *)replyCategoryInlcudingLike:(BOOL)includingLike
{
    UIMutableUserNotificationCategory *category = [[UIMutableUserNotificationCategory alloc] init];
    category.identifier = includingLike ? ZMConversationCategoryIncludingLike : ZMConversationCategory;
    NSMutableArray *actions = @[[self replyActionDirectMessage: NO], [self muteConversationBackgroundAction]].mutableCopy;

    if (includingLike) {
        [actions insertObject:self.likeMessageAction atIndex:1];
    }

    [category setActions:actions forContext:UIUserNotificationActionContextDefault];
    [category setActions:actions forContext:UIUserNotificationActionContextMinimal];
    return category;
}

- (UIUserNotificationCategory *)incomingCallCategory
{
    UIMutableUserNotificationCategory *category = [[UIMutableUserNotificationCategory alloc] init];
    category.identifier = ZMIncomingCallCategory;
    NSArray *actions = @[[self ignoreCallBackgroundAction], [self replyActionDirectMessage:YES]];
    [category setActions:actions forContext:UIUserNotificationActionContextDefault];
    [category setActions:actions forContext:UIUserNotificationActionContextMinimal];
    return category;
}

- (UIUserNotificationCategory *)missedCallCategory
{
    UIMutableUserNotificationCategory *category = [[UIMutableUserNotificationCategory alloc] init];
    category.identifier = ZMMissedCallCategory;
    NSArray *actions = @[[self callBackAction], [self replyActionDirectMessage:YES]];
    [category setActions:actions forContext:UIUserNotificationActionContextDefault];
    [category setActions:actions forContext:UIUserNotificationActionContextMinimal];
    return category;
}

- (UIUserNotificationCategory *)connectCategory
{
    UIMutableUserNotificationCategory *category = [[UIMutableUserNotificationCategory alloc] init];
    category.identifier = ZMConnectCategory;
    [category setActions:@[[self acceptConnectionAction]] forContext:UIUserNotificationActionContextDefault];
    [category setActions:@[[self acceptConnectionAction]] forContext:UIUserNotificationActionContextMinimal];
    return category;
}


- (UIUserNotificationAction *)openAction
{
    UIMutableUserNotificationAction *action = [self mutableForegroundAction:ZMConversationOpenAction localizedTitleKey:@"message.open"];
    return action;
}

- (UIUserNotificationAction *)replyActionDirectMessage:(BOOL)isCallContext
{
    NSString *localizedTitleKey = isCallContext ? @"call.message" : @"message.reply";
    UIMutableUserNotificationAction *action = [self mutableBackgroundAction:ZMConversationDirectReplyAction localizedTitleKey:localizedTitleKey];
    if ([action respondsToSelector:@selector(setBehavior:)]) { // This is only available in iOS9
        action.behavior = UIUserNotificationActionBehaviorTextInput;
        NSString *sendButtonTitle = [NSString localizedStringWithFormat:ZMPushActionLocalizedString(@"message.reply.button.title"), nil];
        action.parameters = @{UIUserNotificationTextInputActionButtonTitleKey: sendButtonTitle};
    }
    return action;
}

- (UIUserNotificationAction *)likeMessageAction
{
    return [self mutableBackgroundAction:ZMMessageLikeAction localizedTitleKey:@"message.like"];
}

- (UIUserNotificationAction *)acceptCallAction
{
    UIMutableUserNotificationAction *action = [self mutableForegroundAction:ZMCallAcceptAction localizedTitleKey:@"call.accept"];
    return action;
}

- (UIUserNotificationAction *)callBackAction
{
    UIMutableUserNotificationAction *action = [self mutableForegroundAction:ZMCallAcceptAction localizedTitleKey:@"call.callback"];
    return action;
}


- (UIUserNotificationAction *)ignoreCallBackgroundAction
{
    UIMutableUserNotificationAction *action = [self mutableBackgroundAction:ZMCallIgnoreAction
                                                          localizedTitleKey:@"call.ignore"];
    action.destructive = YES;
    return action;
}

- (UIUserNotificationAction *)muteConversationBackgroundAction
{
    UIMutableUserNotificationAction *action = [self mutableBackgroundAction:ZMConversationMuteAction localizedTitleKey:@"conversation.mute"];
    return action;
}

- (UIUserNotificationAction *)acceptConnectionAction
{
    UIMutableUserNotificationAction *action = [self mutableForegroundAction:ZMConnectAcceptAction localizedTitleKey:@"connection.accept"];
    return action;
}

@end
