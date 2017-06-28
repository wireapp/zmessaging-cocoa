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

#import <WireSyncEngine/ZMUserSession.h>

@class ZMCompleteRegistrationUser;
@protocol ZMRegistrationObserverToken;
@protocol ZMRegistrationObserver;

@interface ZMUserSession (Registration)

/// Whether the user completed the registration on this device
@property (nonatomic, readonly) BOOL registeredOnThisDevice;

@end



@protocol ZMRegistrationObserver <NSObject>
@optional

/// Invoked when the registration failed
- (void)registrationDidFail:(NSError *)error;

/// Requesting the phone verification code failed (e.g. invalid number?) even before sending SMS
- (void)phoneVerificationCodeRequestDidFail:(NSError *)error;

/// Requesting the phone verification code succeded
- (void)phoneVerificationCodeRequestDidSucceed;

/// Invoked when any kind of phone verification was completed with the right code
- (void)phoneVerificationDidSucceed;

/// Invoked when any kind of phone verification failed because of wrong code/phone combination
- (void)phoneVerificationDidFail:(NSError *)error;

/// Email was correctly registered and validated
- (void)emailVerificationDidSucceed;

/// Email was already registered to another user
- (void)emailVerificationDidFail:(NSError *)error;

@end
