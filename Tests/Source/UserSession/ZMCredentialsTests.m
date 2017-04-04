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

@import WireUtilities;

#import "MessagingTest.h"
#import "ZMCredentials.h"

@interface ZMCredentialsTests : MessagingTest

@end

@implementation ZMCredentialsTests

- (void)testThatItStoresPhoneCredentials
{
    NSString *phoneNumber = @"+4912345678";
    NSString *code = @"aabbcc";
    
    ZMPhoneCredentials *sut = [ZMPhoneCredentials credentialsWithPhoneNumber:phoneNumber verificationCode:code];
    
    XCTAssertEqualObjects(sut.phoneNumber, phoneNumber);
    XCTAssertEqualObjects(sut.phoneNumberVerificationCode, code);
}

- (void)testThatItNormalizesThePhoneNumber {
    NSString *phoneNumber = @"+49(123)45.6-78";
    NSString *normalizedPhoneNumber = [phoneNumber copy];
    [ZMPhoneNumberValidator validateValue:&normalizedPhoneNumber error:nil];
    
    NSString *code = @"aabbcc";
    
    ZMPhoneCredentials *sut = [ZMPhoneCredentials credentialsWithPhoneNumber:phoneNumber verificationCode:code];
    
    XCTAssertEqualObjects(sut.phoneNumber, normalizedPhoneNumber);
    XCTAssertEqualObjects(sut.phoneNumberVerificationCode, code);
    XCTAssertNotEqualObjects(normalizedPhoneNumber, phoneNumber, @"Should not have modified original");
}

@end
