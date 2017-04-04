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


#import "MockLinkPreviewDetector.h"
@import WireLinkPreview;

NSString * const ZMTestURLArticleWithoutPictureString   = @"http://someurl.com/nopicture";
NSString * const ZMTestURLArticleWithPictureString      = @"http://someurl.com/magicpicture";
NSString * const ZMTestURLRegularTweetString            = @"http://twitter.com/jcvd/status/averybigtweetid";
NSString * const ZMTestURLTweetWithPictureString        = @"http://twitter.com/jcvd/status/fullsplitbetweentruckspic";
NSString * const ZMTestURLFoursquareLinkString          = @"http://somefoursquarething.com";
NSString * const ZMTestURLInstagramLinkString           = @"http://instagram.com/jcvd/isonicboomlikeguile";

static NSString * const TestFakePictureURL = @"http://reallifepic.com/s0m3cHucKN0rR1sp1C.jpg";

typedef NS_ENUM(NSUInteger, ZMTestURL)
{
    ZMTestURLUnknown = 0,
    ZMTestURLArticleWithoutPicture,
    ZMTestURLArticleWithPicture,
    ZMTestURLRegularTweet,
    ZMTestURLTweetWithPicture,
    ZMTestURLFoursquareLink,
    ZMTestURLInstagramLink
};

static ZMTestURL
testURLFromString(NSString *string)
{
    if ([string isEqualToString:ZMTestURLArticleWithoutPictureString]) {
        
        return ZMTestURLArticleWithoutPicture;
        
    } else if ([string isEqualToString:ZMTestURLArticleWithPictureString]) {
        
        return ZMTestURLArticleWithPicture;
        
    } else if ([string isEqualToString:ZMTestURLRegularTweetString]) {
        
        return ZMTestURLRegularTweet;
        
    } else if ([string isEqualToString:ZMTestURLTweetWithPictureString]) {
        
        return ZMTestURLTweetWithPicture;
        
    } else if ([string isEqualToString:ZMTestURLFoursquareLinkString]) {
        
        return ZMTestURLFoursquareLink;
        
    } else if ([string isEqualToString:ZMTestURLInstagramLinkString]) {
        
        return ZMTestURLInstagramLink;
        
    }
    
    return ZMTestURLUnknown;
}

@implementation MockLinkPreviewDetector

- (instancetype)initWithTestImageData:(NSData *)testImageData;
{
    self = [super init];
    if (self) {
        _testImageData = testImageData;
    }
    return self;
}

- (void)downloadLinkPreviewsInText:(NSString *)text
                        completion:(void (^ _Nonnull)(NSArray<LinkPreview *> * _Nonnull))completion
{
    NSArray <LinkPreview *> *result = nil;
    
    ZMTestURL testUrl = testURLFromString(text);
    ZMLinkPreview *linkPreview = [self linkPreviewFromURLString:text includeAsset: [[self class] urlIncludesImage:text] includingTweet:[[self class] urlIncludeTweet:text]];
    
    switch (testUrl) {
        case ZMTestURLArticleWithoutPicture:
        {
            Article *article = [[Article alloc] initWithProtocolBuffer:linkPreview];
            result = @[article];
        }
            break;
            
        case ZMTestURLArticleWithPicture:
        {
            Article *article = [[Article alloc] initWithProtocolBuffer:linkPreview];
            article.imageData = @[self.testImageData];
            article.imageURLs = @[[NSURL URLWithString:TestFakePictureURL]];
            result = @[article];

        }
            break;
            
        case ZMTestURLRegularTweet:
        {
            TwitterStatus *status = [[TwitterStatus alloc] initWithProtocolBuffer:linkPreview];
            result = @[status];
        }
            break;
            
        case ZMTestURLTweetWithPicture:
        {
            TwitterStatus *status = [[TwitterStatus alloc] initWithProtocolBuffer:linkPreview];
            status.imageData = @[self.testImageData];
            status.imageURLs = @[[NSURL URLWithString:TestFakePictureURL]];
            result = @[status];
        }
            break;
            
        case ZMTestURLFoursquareLink:            
        case ZMTestURLInstagramLink:
        case ZMTestURLUnknown:
        {
            completion(@[]);
        }
            break;
    }
    
    completion(result);
}

+ (ZMAsset *)createRandomAsset;
{
    ZMAssetRemoteDataBuilder *remoteDataBuilder = [ZMAssetRemoteDataBuilder new];
    remoteDataBuilder.otrKey = [NSData randomEncryptionKey];
    remoteDataBuilder.sha256 = [NSData zmRandomSHA256Key];
    
    ZMAssetBuilder *assetBuilder = [ZMAssetBuilder new];
    assetBuilder.uploaded = [remoteDataBuilder build];
    
    return [assetBuilder build];
}

+ (ZMTweet *)tweet;
{
    return [ZMTweet tweetWithAuthor:@"Jean-Claude Van Damme" username:@"JCVDG05U"];
}

- (ZMLinkPreview *)linkPreviewFromURLString:(NSString *)urlString includeAsset:(BOOL)includingAsset includingTweet:(BOOL)includeTweet;
{
    ZMAsset *localAsset = nil;
    ZMTweet *tweet = nil;
    if (includingAsset) {
        localAsset = [[self class] createRandomAsset];
    }
    if (includeTweet) {
        tweet = [[self class] tweet];
    }
    
    return [self linkPreviewFromURLString:urlString asset:localAsset tweet:tweet];
}

- (ZMLinkPreview *)linkPreviewFromURLString:(NSString *)urlString asset:(ZMAsset *)asset tweet:(ZMTweet *)tweet;
{
    ZMTestURL testURL = testURLFromString(urlString);
    switch (testURL) {
            
            // Generic article build
        case ZMTestURLArticleWithPicture:
        case ZMTestURLInstagramLink:
        case ZMTestURLFoursquareLink:
        case ZMTestURLArticleWithoutPicture:
        {
            return [ZMLinkPreview linkPreviewWithOriginalURL:urlString permanentURL:urlString offset:0
                                                       title:@"ClickHole: You won't believe what THIS CAT can do!"
                                                     summary:@"Wasting your time"
                                                  imageAsset:asset];
        }
            
            // Twitter build
        case ZMTestURLTweetWithPicture:
        case ZMTestURLRegularTweet:
        {
            return [ZMLinkPreview linkPreviewWithOriginalURL:urlString permanentURL:urlString offset:0
                                                       title:@"1 + 1 = 1, or 11, a that's beautiful."
                                                     summary:nil
                                                  imageAsset:asset
                                                       tweet:tweet];
        }
            
        case ZMTestURLUnknown:
            return nil;
    }

}

+ (BOOL)urlIncludeTweet:(NSString *)urlString;
{
    ZMTestURL testURL = testURLFromString(urlString);
    switch (testURL) {
        case ZMTestURLRegularTweet:
        case ZMTestURLTweetWithPicture:
            return YES;
        default:
            return NO;
    }

}

+ (BOOL)urlIncludesImage:(NSString *)urlString;
{
    ZMTestURL testURL = testURLFromString(urlString);
    switch (testURL) {
        case ZMTestURLArticleWithPicture:
        case ZMTestURLInstagramLink:
        case ZMTestURLFoursquareLink:
        case ZMTestURLTweetWithPicture:
            return YES;
        default:
            return NO;
    }
}

@end
