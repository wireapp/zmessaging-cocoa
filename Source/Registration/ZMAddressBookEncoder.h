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


@import Foundation;
@import ZMTransport;

@class ZMAddressBook;
@class ZMEncodedAddressBook;


NS_ASSUME_NONNULL_BEGIN

@interface ZMAddressBookEncoder : NSObject

- (instancetype)initWithManagedObjectContext:(NSManagedObjectContext *)moc addressBook:(ZMAddressBook * __nullable)addressBook NS_DESIGNATED_INITIALIZER;

- (void)createPayloadWithCompletionHandler:(void(^)(ZMEncodedAddressBook *encoded))completionHandler;

@end


@interface ZMEncodedAddressBook : NSObject

@property (nonatomic, readonly) NSUInteger addressBookSize; // The size of the complete address book (used for tracking)
@property (nonatomic, readonly, copy, nullable) id<ZMTransportData> localData;
@property (nonatomic, readonly, copy, nullable) id<ZMTransportData> otherData;
@property (nonatomic, readonly, copy, nullable) NSData *digest; ///< A digest of the entire address book

@end

NS_ASSUME_NONNULL_END
