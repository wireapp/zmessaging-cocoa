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


@import ZMCSystem;
@import ZMUtilities;
@import ZMTransport;
@import ZMCDataModel;

#import "ZMAddressBookSync+Testing.h"

#import "ZMSingleRequestSync.h"
#import "ZMAddressBook.h"
#import "ZMAddressBookEncoder.h"
#import "ZMOperationLoop.h"
#import "zmessaging/zmessaging-Swift.h"

static NSString * const ZMAddressBookTranscoderNeedsToBeUploadedKey = @"ZMAddressBookTranscoderNeedsToBeUploaded";
static NSString * const ZMOnboardingEndpoint = @"/onboarding/v2";


@interface ZMAddressBookSync ()

@property (nonatomic) ZMSingleRequestSync *addressBookUpload;
@property (nonatomic) BOOL isGeneratingPayload;
@property (nonatomic) ZMEncodedAddressBook *encodedAddressBook;
@property (nonatomic) ZMAddressBook *addressBook;
@property (nonatomic) AddressBookTracker *addressBookTracker;

@end



@interface ZMAddressBookSync (NSManagedObjectContext)

@property (nonatomic, readonly) NSString *persistentStoreKey;
@property (nonatomic, readonly) NSString *persistentStoreDigestKey;

- (void)clearAddressBookAsNeedingToBeUploaded;

@property (nonatomic) NSData *uploadedAddressBookDigest;

@end



@interface ZMAddressBookSync (RequestTranscoder) <ZMSingleRequestTranscoder>
@end



@implementation ZMAddressBookSync

+ (NSString *)persistentStoreKey;
{
    return ZMAddressBookTranscoderNeedsToBeUploadedKey;
}

- (instancetype)initWithManagedObjectContext:(NSManagedObjectContext *)moc;
{
    return [self initWithManagedObjectContext:moc addressBook:nil addressBookUpload:nil];
}

- (instancetype)initWithManagedObjectContext:(NSManagedObjectContext *)moc addressBook:(ZMAddressBook *)addressBook addressBookUpload:(ZMSingleRequestSync *)addressBookUpload;
{
    self = [super initWithManagedObjectContext:moc];
    if (self != nil) {
        self.addressBook = addressBook;
        self.addressBookTracker = [[AddressBookTracker alloc] initWithAnalytics:self.managedObjectContext.zm_syncContext.analytics];
        self.addressBookUpload = addressBookUpload ?: [[ZMSingleRequestSync alloc] initWithSingleRequestTranscoder:self managedObjectContext:self.managedObjectContext];
    }
    return self;
}

@synthesize addressBook = _addressBook;

- (ZMAddressBook *)addressBook;
{
    if (_addressBook == nil) {
        _addressBook = [[ZMAddressBook alloc] init];
    }
    return _addressBook;
}

- (ZMTransportRequest *)nextRequest;
{
    if (! self.addressBookNeedsToBeUploaded) {
        return nil;
    }
    if (self.isGeneratingPayload) {
        return nil;
    }
    if (self.encodedAddressBook != nil) {
        return [self.addressBookUpload nextRequest];
    }
    if (self.addressBookUpload.status == ZMSingleRequestInProgress) {
        return nil;
    }
    
    self.isGeneratingPayload = YES;
    ZMAddressBook *addressBook = self.addressBook;
    ZMAddressBookEncoder *encoder = [[ZMAddressBookEncoder alloc] initWithManagedObjectContext:self.managedObjectContext addressBook:addressBook];
    
    [encoder createPayloadWithCompletionHandler:^(ZMEncodedAddressBook *encoded) {
        BOOL addressBookChanged = ![self.uploadedAddressBookDigest isEqual:encoded.digest];
        [self.addressBookTracker tagAddressBookUpload:addressBookChanged size:encoded.addressBookSize];
        if (addressBookChanged) {
            self.encodedAddressBook = encoded;
            [self.addressBookUpload readyForNextRequest];
            [ZMOperationLoop notifyNewRequestsAvailable:self];
        };
        self.isGeneratingPayload = NO;
    }];
    
    return nil;
}

@end



@implementation ZMAddressBookSync (RequestTranscoder)

- (ZMTransportRequest *)requestForSingleRequestSync:(ZMSingleRequestSync *)sync;
{
    VerifyReturnNil(sync == self.addressBookUpload);
    NSDictionary *payload = @{@"self": self.encodedAddressBook.localData ?: @[],
                              @"cards": self.encodedAddressBook.otherData ?: @[],};
    return [ZMTransportRequest requestWithPath:ZMOnboardingEndpoint method:ZMMethodPOST payload:payload shouldCompress:YES];
}

- (void)didReceiveResponse:(ZMTransportResponse *)response forSingleRequest:(ZMSingleRequestSync * __unused)sync
{
    if (response.result == ZMTransportResponseStatusSuccess) {
        NSArray *remoteIdentifiersAsStrings = [[response.payload asDictionary] arrayForKey:@"results"];
        NSArray *remoteIdentifiers = [remoteIdentifiersAsStrings mapWithBlock:^id(NSString *s) {
            return s.UUID;
        }];
        
        self.managedObjectContext.suggestedUsersForUser = [NSOrderedSet orderedSetWithArray:remoteIdentifiers];
        self.managedObjectContext.commonConnectionsForUsers = @{};
    }
    self.uploadedAddressBookDigest = self.encodedAddressBook.digest;
    self.encodedAddressBook = nil;
    [self clearAddressBookAsNeedingToBeUploaded];
}

@end



@implementation ZMAddressBookSync (Marking)

+ (void)markAddressBookAsNeedingToBeUploadedInContext:(NSManagedObjectContext *)moc;
{
    [moc setPersistentStoreMetadata:@YES forKey:[self persistentStoreKey]];
    NSError *error;
    if (! [moc save:&error]) {
        ZMLogWarn(@"Failed to set address book upload key: %@", error);
    }
}

+ (BOOL)addressBookNeedsToBeUploadedInContext:(NSManagedObjectContext *)moc;
{
    NSNumber *n = [moc persistentStoreMetadataForKey:self.persistentStoreKey];
    return [n isKindOfClass:[NSNumber class]] && [n boolValue];
}

- (BOOL)addressBookNeedsToBeUploaded
{
    return [self.class addressBookNeedsToBeUploadedInContext:self.managedObjectContext];
}

@end



@implementation ZMAddressBookSync (NSManagedObjectContext)


- (NSString *)persistentStoreKey;
{
    return [self.class persistentStoreKey];
}

- (NSString *)persistentStoreDigestKey;
{
    return [self.persistentStoreKey stringByAppendingString:@"Digest"];
}

- (void)clearAddressBookAsNeedingToBeUploaded;
{
    [self.managedObjectContext setPersistentStoreMetadata:nil forKey:self.persistentStoreKey];
    NSError *error;
    if (! [self.managedObjectContext save:&error]) {
        ZMLogWarn(@"Failed to clear address book upload key: %@", error);
    }
}

- (NSData *)uploadedAddressBookDigest;
{
    NSData *digest = [self.managedObjectContext persistentStoreMetadataForKey:self.persistentStoreDigestKey];
    return [digest isKindOfClass:NSData.class] ? digest : nil;
}

- (void)setUploadedAddressBookDigest:(NSData *)digest;
{
    [self.managedObjectContext setPersistentStoreMetadata:digest forKey:self.persistentStoreDigestKey];
}

@end
