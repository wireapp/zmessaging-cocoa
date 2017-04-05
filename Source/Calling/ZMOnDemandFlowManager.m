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


#import "ZMOnDemandFlowManager.h"
#import "ZMAVSBridge.h"
#import <avs/AVSMediaManager.h>
#import <avs/AVSFlowManager.h>

NSString *ZMOnDemandFlowManagerDidBecomeAvailableNotification = @"ZMOnDemandFlowManagerDidBecomeAvailableNotification";

@import WireSystem;

@interface ZMOnDemandFlowManager ()
@property (nonatomic) id mediaManager;
@property (nonatomic) AVSFlowManager *flowManager;
@end

@implementation ZMOnDemandFlowManager

- (instancetype)initWithMediaManager:(id)mediaManager
{
    self = [super init];
    if (self) {
        (void)[[self class] flowManagerClass];
        self.mediaManager = mediaManager;
    }
    return self;
}

+ (Class)flowManagerClass
{
    Class flowManagerClass = NSClassFromString(@"AVSFlowManager");
    RequireString(flowManagerClass != nil, "No AVS library linked? Missing FlowManager class");
    return flowManagerClass;
}

- (void)initializeFlowManagerWithDelegate:(id<AVSFlowManagerDelegate>)delegate
{
    if (self.flowManager == nil && ![[NSUserDefaults standardUserDefaults] boolForKey:@"ZMDisableAVS"]) {
        if ([ZMAVSBridge overrideFlowManager] != nil) {
            // We need this to interpose for our integration tests:
            self.flowManager = [ZMAVSBridge overrideFlowManager];
            [self.flowManager setValue:delegate forKey:@"delegate"];
        }
        else {
            Class flowManagerClass = [[self class] flowManagerClass];
            self.flowManager = [[flowManagerClass alloc] initWithDelegate:delegate mediaManager:self.mediaManager];
        }
        
        [[NSNotificationCenter defaultCenter] postNotificationName:ZMOnDemandFlowManagerDidBecomeAvailableNotification object:self.flowManager];
    }
}

@end
