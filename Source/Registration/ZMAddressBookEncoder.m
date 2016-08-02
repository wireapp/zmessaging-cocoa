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


@import ZMUtilities;
@import ZMCDataModel;

#import "ZMAddressBookEncoder.h"
#import "ZMAddressBook.h"
#import <CommonCrypto/CommonDigest.h>

static dispatch_queue_t ZMAddressBookIsolationQueue;

@interface NSString (ZMAddressBook)

- (NSString *)addressBookEncoderHash;

@end



@interface ZMAddressBookEncoder ()

@property (nonatomic) NSManagedObjectContext *managedObjectContext;
@property (nonatomic) ZMAddressBook *addressBook;

@end



@interface ZMEncodedAddressBook ()

@property (nonatomic) NSUInteger addressBookSize;
@property (nonatomic, copy) id<ZMTransportData> localData;
@property (nonatomic, copy) id<ZMTransportData> otherData;
@property (nonatomic, copy) NSData *digest;

@end



static void updateDigest(CC_SHA512_CTX *ctx, NSString *string)
{
    VerifyReturn(string != nil);
    NSData *input = [string dataUsingEncoding:NSUTF8StringEncoding];
    CC_SHA512_Update(ctx, input.bytes, (CC_LONG) input.length);
}


@implementation ZMAddressBookEncoder

ZM_EMPTY_ASSERTING_INIT()

- (instancetype)initWithManagedObjectContext:(NSManagedObjectContext *)moc addressBook:(ZMAddressBook *)addressBook;
{
    VerifyReturnNil(moc != nil);
    self = [super init];
    if (self) {
        self.managedObjectContext = moc;
        self.addressBook = addressBook;
        
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            ZMAddressBookIsolationQueue = dispatch_queue_create("ZMAddressBookEncoder", NULL);
        });
    }
    return self;
}

- (NSString *)validatedEmailFromEmail:(NSString *)email;
{
    if (0 < email.length) {
        NSString *validatedEmail = email;
        NSError *error;
        if ([ZMEmailAddressValidator validateValue:&validatedEmail error:&error]) {
            return validatedEmail;
        }
    }
    return nil;
}

- (NSString *)validatedPhoneNumberFromPhoneNumber:(NSString *)phone;
{
    if (0 < phone.length) {
        NSString *validatedPhone = phone;
        NSError *error;
        if ([ZMPhoneNumberValidator validateValue:&validatedPhone error:&error]) {
            return validatedPhone;
        }
    }
    return nil;
}

- (void)createPayloadWithCompletionHandler:(void(^)(ZMEncodedAddressBook *encoded))completionHandler;
{
    [self.managedObjectContext performGroupedBlock:^{
        ZMUser *selfUser = [ZMUser selfUserInContext:self.managedObjectContext];
        NSString *selfEmail = [selfUser.emailAddress copy];
        NSString *selfPhone = [selfUser.phoneNumber copy];
        ZMAddressBook *addressBook = self.addressBook;
        [self.managedObjectContext.dispatchGroup asyncOnQueue:ZMAddressBookIsolationQueue block:^{
            ZMEncodedAddressBook *result = [[ZMEncodedAddressBook alloc] init];
            CC_SHA512_CTX digestContext = {};
            CC_SHA512_Init(&digestContext);
            {
                NSMutableSet *selfHashes = [NSMutableSet set];
                NSString *validatedEmail = [self validatedEmailFromEmail:selfEmail];
                if (validatedEmail != nil) {
                    [selfHashes addObject:validatedEmail.addressBookEncoderHash];
                }
                NSString *validatedPhone = [self validatedPhoneNumberFromPhoneNumber:selfPhone];
                if (validatedPhone != nil) {
                    [selfHashes addObject:validatedPhone.addressBookEncoderHash];
                }
                result.localData = selfHashes.allObjects;
            }
            {
                NSMutableArray *otherHashesCards = [NSMutableArray array];
                NSUInteger index = 0;
                for (ZMAddressBookContact *contact in addressBook.contacts) {
                    if (index > 1000) { // FIXME: right now we upload only top 1000 contacts due to memory / perfor-
                                        // mance limits
                        break;
                    }
                    
                    NSMutableOrderedSet *otherHashes = [NSMutableOrderedSet orderedSet];
                    for (NSString *email in contact.emailAddresses) {
                        NSString *validatedEmail = [self validatedEmailFromEmail:email];
                        if (validatedEmail != nil) {
                            [otherHashes addObject:validatedEmail.addressBookEncoderHash];
                            updateDigest(&digestContext, validatedEmail);
                        }
                    }
                    for (NSString *phone in contact.phoneNumbers) {
                        if ((7 < phone.length) && [phone hasPrefix:@"+"]) {
                            [otherHashes addObject:phone.addressBookEncoderHash];
                            updateDigest(&digestContext, phone);
                        }
                    }
                    if(otherHashes.count > 0) {
                        
                        NSDictionary *payload = @{
                                                  @"card_id" : [NSString stringWithFormat:@"%lu", (unsigned long) otherHashesCards.count],
                                                  @"contact" : otherHashes.array
                                                  };
                        
                        [otherHashesCards addObject:payload];
                        int32_t numberOfHashes = (int32_t) otherHashes.count;
                        // add number of digests in contact to hash
                        CC_SHA512_Update(&digestContext, &numberOfHashes, sizeof(numberOfHashes));
                    }
                    
                    index++;
                }
                result.otherData = (otherHashesCards.count < 1) ? nil : otherHashesCards;
                result.addressBookSize = addressBook.numberOfContacts;
            }
            {
                NSMutableData *digest = [NSMutableData dataWithLength:CC_SHA512_DIGEST_LENGTH];
                CC_SHA512_Final((unsigned char *) digest.mutableBytes, &digestContext);
                result.digest = digest;
            }
            completionHandler(result);
        }];
    }];
    
}

@end



@implementation NSString (ZMAddressBook)

- (NSString *)addressBookEncoderHash;
{
    NSMutableData *digest = [NSMutableData dataWithLength:CC_SHA256_DIGEST_LENGTH];
    NSData *input = [self dataUsingEncoding:NSUTF8StringEncoding];
    CC_SHA256(input.bytes, (CC_LONG) input.length, (unsigned char *) digest.mutableBytes);
    return [digest base64EncodedStringWithOptions:0];
}

@end



@implementation ZMEncodedAddressBook

- (NSString *)description;
{
    return [NSString stringWithFormat:@"<%@: %p> %u local entries, %u other entries, digest: %@",
            self.class, self,
            (unsigned) ((NSArray *) self.localData).count,
            (unsigned) ((NSArray *) self.otherData).count,
            self.digest];
}

@end
