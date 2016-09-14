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


@import UIKit;
#import "ZMBadge.h"
#import <zmessaging/zmessaging-Swift.h>

@interface ZMBadge ()

@property (nonatomic) id<ZMApplication> application;

@end



@implementation ZMBadge

- (instancetype)initWithApplication:(id<ZMApplication>)application {
    self = [super init];
    if (self) {
        self.application = application;
    }
    return self;
}

- (void)setBadgeCount:(NSUInteger)count;
{
    self.application.applicationIconBadgeNumber = (NSInteger)count;
}

@end

