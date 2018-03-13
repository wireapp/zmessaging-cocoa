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


typedef NS_ENUM(NSUInteger, ZMPushNotficationType) {
    ZMPushNotficationTypeAlert = 0,
    ZMPushNotficationTypeVoIP
};

typedef NS_ENUM(int8_t, ZMPushPayloadResult) {
    ZMPushPayloadResultFailure = 0,
    ZMPushPayloadResultSuccess = 1,
    ZMPushPayloadResultNoData = 2,
};

typedef void (^ZMPushResultHandler)(ZMPushPayloadResult);



extern void ZMLogPushKit(NSString *format, ...) NS_FORMAT_FUNCTION(1,2);
extern void ZMLogPushKit_s(NSString *text);
extern BOOL ZMLogPushKit_enabled(void);
