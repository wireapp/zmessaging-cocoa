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

#import "VoiceChannelV2+Internal.h"
#import <WireSyncEngine/WireSyncEngine-Swift.h>


@implementation VoiceChannelV2ParticipantState

- (BOOL)isEqual:(id)object;
{
    if (! [object isKindOfClass:[VoiceChannelV2ParticipantState class]]) {
        return NO;
    }
    VoiceChannelV2ParticipantState *other = object;
    return ((other.connectionState == self.connectionState) &&
            (other.muted == self.muted));
}

- (NSString *)description;
{
    NSString *d;
    switch (self.connectionState) {
        default:
        case VoiceChannelV2ConnectionStateInvalid:
            d = @"Invalid";
            break;
        case VoiceChannelV2ConnectionStateNotConnected:
            d = @"NotConnected";
            break;
        case VoiceChannelV2ConnectionStateConnecting:
            d = @"Connecting";
            break;
        case VoiceChannelV2ConnectionStateConnected:
            d = @"Connected";
            break;
    }
    return [NSString stringWithFormat:@"<%@: %p> %@%@", self.class, self,
            d,
            self.muted ? @" muted" : @""];
}

@end
