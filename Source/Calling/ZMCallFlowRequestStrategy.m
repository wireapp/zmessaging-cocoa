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


@import WireSystem;
@import WireUtilities;
@import WireDataModel;

#import "ZMCallFlowRequestStrategy.h"
#import <WireSyncEngine/WireSyncEngine-Swift.h>

static NSString *ZMLogTag ZM_UNUSED = @"Calling";

@interface ZMCallFlowRequestStrategy ()

@property (nonatomic) id<FlowManagerType> flowManager;
@property (nonatomic, readonly, weak) id mediaManager;
@property (nonatomic) NSNotificationQueue *voiceGainNotificationQueue;
@property (nonatomic) BOOL pushChannelIsOpen;
@property (nonatomic, readonly, weak) NSManagedObjectContext *uiManagedObjectContext;
@property (nonatomic, readonly, weak) id<ZMApplication> application;
@property (nonatomic) id pushChannelObserverToken;

@end

@interface ZMCallFlowRequestStrategy (FlowManagerDelegate) <FlowManagerDelegate>
@end

@implementation ZMCallFlowRequestStrategy

- (instancetype)initWithMediaManager:(id)mediaManager
                         flowManager:(id<FlowManagerType>)flowManager
                managedObjectContext:(NSManagedObjectContext *)managedObjectContext
                   applicationStatus:(id<ZMApplicationStatus>)applicationStatus
                         application:(id<ZMApplication>)application
{
    self = [super initWithManagedObjectContext:managedObjectContext applicationStatus:applicationStatus];
    if(self != nil) {
        _uiManagedObjectContext = managedObjectContext.zm_userInterfaceContext;
        _mediaManager = mediaManager;
        _application = application;

        self.voiceGainNotificationQueue = [[NSNotificationQueue alloc] initWithNotificationCenter:[NSNotificationCenter defaultCenter]];
        self.flowManager = flowManager;
        self.flowManager.delegate = self;
        
        ZM_WEAK(self);
        self.pushChannelObserverToken = [NotificationInContext addObserverWithName:ZMOperationLoop.pushChannelStateChangeNotificationName
                                           context:self.managedObjectContext.notificationContext
                                            object:nil
                                             queue:nil
                                             using:^(NotificationInContext * note) {
                                                 ZM_STRONG(self);
                                                 [self pushChannelDidChange:note];
                                             }];
        self.pushChannelIsOpen = NO;
    }
    return self;
}

- (ZMStrategyConfigurationOption)configuration
{
    return ZMStrategyConfigurationOptionAllowsRequestsDuringEventProcessing
         | ZMStrategyConfigurationOptionAllowsRequestsDuringSync
         | ZMStrategyConfigurationOptionAllowsRequestsWhileInBackground
         | ZMStrategyConfigurationOptionAllowsRequestsDuringNotificationStreamFetch;
}

- (void)tearDown;
{
    self.flowManager = nil;
    self.pushChannelObserverToken = nil;
    [self.application unregisterObserverForStateChange:self];
}

- (ZMTransportRequest *)nextRequestIfAllowed
{
    return nil;
}

- (void)pushChannelDidChange:(NotificationInContext *)note
{
    BOOL newValue = [note.userInfo[ZMPushChannelIsOpenKey] boolValue];
    self.pushChannelIsOpen = newValue;
    
    if (self.pushChannelIsOpen) {
        [self.flowManager reportNetworkChanged];
    }
}

@end

@implementation ZMCallFlowRequestStrategy (FlowManagerDelegate)

- (void)flowManagerDidUpdateVolume:(double)volume for:(NSString *)participantId in:(NSUUID *)conversationId
{
    [self.managedObjectContext performGroupedBlock:^{
        ZMConversation *conversation = [ZMConversation conversationWithRemoteID:conversationId createIfNeeded:NO inContext:self.managedObjectContext];
        if (conversation == nil) {
            return;
        }
        ZMUser *user;
        if ([participantId isEqualToString:FlowManagerSelfUserParticipantIdentifier]) {
            user = [ZMUser selfUserInContext:self.managedObjectContext];
        }
        else if ([participantId isEqualToString:FlowManagerOtherUserParticipantIdentifier]) {
            user = conversation.connectedUser;
        }
        
        else {
            NSUUID *participantUUID = [participantId UUID];
            user = [ZMUser userWithRemoteID:participantUUID createIfNeeded:NO inContext:self.managedObjectContext];
        }
        if (user == nil) {
            return;
        }
        
        NSUUID *conversationID = conversation.remoteIdentifier;
        NSUUID *userID = user.remoteIdentifier;
        
        VoiceGainNotification *voiceGainNotification = [[VoiceGainNotification alloc] initWithVolume:(float)volume conversationId:conversationID userId:userID];
        
        [self.uiManagedObjectContext performGroupedBlock:^{
            [voiceGainNotification postIn:self.uiManagedObjectContext.notificationContext queue:self.voiceGainNotificationQueue];
        }];
    }];
}

@end
