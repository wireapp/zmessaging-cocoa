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


#import <Foundation/Foundation.h>

#import "AVSMediaManager.h"
#import "AVSFlowManager.h"
#import "ZMObjectSyncStrategy.h"
@class ZMConversation;
@class ZMUser;
@class ZMOnDemandFlowManager;
@protocol ZMApplication;

typedef NS_ENUM(int16_t, ZMFlowManagerCategory) {
    ZMFlowManagerCategoryIdle = 0,
    ZMFlowManagerCategoryCallInProgress,
};

extern id ZMFlowSyncInternalFlowManagerOverride;
extern id ZMFlowSyncInternalDeploymentEnvironmentOverride;

@interface ZMFlowSync : ZMObjectSyncStrategy <ZMObjectStrategy>

- (instancetype)initWithMediaManager:(id)mediaManager
                 onDemandFlowManager:(ZMOnDemandFlowManager *)onDemandFlowManager
            syncManagedObjectContext:(NSManagedObjectContext *)syncManagedObjectContext
              uiManagedObjectContext:(NSManagedObjectContext *)uiManagedObjectContext
                         application:(id<ZMApplication>)application;


- (void)acquireFlowsForConversation:(ZMConversation *)conversation;
- (void)releaseFlowsForConversation:(ZMConversation *)conversation;
- (void)setSessionIdentifier:(NSString *)sessionID forConversationIdentifier:(NSUUID *)conversationID;
- (void)appendLogForConversationID:(NSUUID *)conversationID message:(NSString *)message;
- (void)addJoinedCallParticipant:(ZMUser *)user inConversation:(ZMConversation *)conversation;
- (void)accessTokenDidChangeWithToken:(NSString *)token ofType:(NSString *)type;
- (void)updateFlowsForConversation:(ZMConversation *)conversation;

@end
