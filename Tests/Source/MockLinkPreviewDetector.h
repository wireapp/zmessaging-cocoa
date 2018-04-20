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


@import WireSyncEngine;
@import WireLinkPreview;

extern NSString * const ZMTestURLArticleWithoutPictureString;
extern NSString * const ZMTestURLArticleWithPictureString;
extern NSString * const ZMTestURLRegularTweetString;
extern NSString * const ZMTestURLTweetWithPictureString;
extern NSString * const ZMTestURLFoursquareLinkString;
extern NSString * const ZMTestURLInstagramLinkString;



@interface MockLinkPreviewDetector : NSObject <LinkPreviewDetectorType>

@property (nonatomic, weak) id<LinkPreviewDetectorDelegate> delegate;
@property (nonatomic) NSData *testImageData;

- (instancetype)initWithTestImageData:(NSData *)testImageData;

+ (ZMTweet *)tweet;

- (ZMLinkPreview *)linkPreviewFromURLString:(NSString *)urlString includeAsset:(BOOL)includingAsset includingTweet:(BOOL)includeTweet;
- (ZMLinkPreview *)linkPreviewFromURLString:(NSString *)urlString asset:(ZMAsset *)asset tweet:(ZMTweet *)tweet;

@end
