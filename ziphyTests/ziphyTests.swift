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


import XCTest
import ziphy




class ziphyTests: ZiphyTestCase {
    
    var ziphyClient:ZiphyClient!
    
    override func setUp() {
        super.setUp()
        
        ZiphyClient.logLevel = ZiphyLogLevel.verbose
        self.ziphyClient = ZiphyClient(host:"api.giphy.com", requester:self.defaultRequester)
    }
    
    func testThatSeachReturnsResults() {
        
        //Set up
        

        let expectation = self.expectation(description: "did return some results")
        
        _ = self.ziphyClient.search(term:"cat", resultsLimit: 10, offset: 0) { (success, gifs, error) -> () in
            
            XCTAssert(success)
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 20) { (error) in

        }
    }
    
    func testThatTrendingReturnsResults() {
        
        //Set up
        
        
        let expectation = self.expectation(description: "did return some results")
        
        _ = self.ziphyClient.trending(resultsLimit: 10, offset: 0) { (success, gifs, error) -> () in
            XCTAssert(success)
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 20) { (error) in
            
        }
    }
    
    
    func testThatFunkyCharsWork() {
        
        let expectation = self.expectation(description: "did return some results")
        
        _ = self.ziphyClient.search(term:"cat\"=\"#%/<>?@\\^`{|}&:#[]@$'+;", resultsLimit: 10, offset: 0) { (success, gifs, error) -> () in
            
            XCTAssert(success)
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 20) { (error) in
            
        }
        
        
    }
    
    func testThatAnImageIsFetched() {
        
        let expectation = self.expectation(description: "did download an image")
        
        let imageFetcher = ZiphyImageFetcher(term: "cat", sizeLimit: 1024*1024, imageType:ZiphyImageType.downsized, requester:self.defaultRequester)
        
        imageFetcher.nextImage { (image, ziph, error) -> () in
            
            if image != nil && ziph != nil {
                
                expectation.fulfill()
            }
        }
        
        waitForExpectations(timeout: 20) { (error) in
            
        }
    }
    
    func testThatNoImageIsFetchedWhenSizeLimitIsZero() {
        
        let expectation = self.expectation(description: "did not download an image")
        let imageFetcher = ZiphyImageFetcher(term:"cat", sizeLimit: 0, imageType:ZiphyImageType.downsized, requester:self.defaultRequester)
        
        imageFetcher.nextImage { (image, ziph,  error) -> () in
            
            XCTAssertNil(image, "Returned image should be nill")
            
            if image == nil && ziph == nil {
                expectation.fulfill()
            }
        }
        
        waitForExpectations(timeout: 20) { (error) in
            
        }
    }
    
    func testThatNoImageIsFecthedIfSearchReturnsNoResults() {
        
        let expectation = self.expectation(description: "did not download an image")
        let imageFetcher = ZiphyImageFetcher(term: "29581298512h0nsawaowi 82251 1wjhfa wa9tru2jas fw9a29h12n2nsaf 0242145",
            sizeLimit: 1024*1024,
            imageType:ZiphyImageType.downsized,
            requester:self.defaultRequester)
        
        imageFetcher.nextImage { (image, ziph, error) -> () in
            
            XCTAssertNil(image, "Returned image should be nill")
            
            if image == nil && ziph == nil {
                expectation.fulfill()
            }
        }
        
        waitForExpectations(timeout: 20) { (error) in
        
        }
    }
    
    func testThatSearchTemsWithSpacesReturnResults() {
        
        _ = GiphyRequester(apiKey:"")
        let expectation = self.expectation(description: "did download an image")
        let imageFetcher = ZiphyImageFetcher(term:"Silent Bob",
            sizeLimit: 1024*1024*3,
            resultslimit:50,
            imageType:ZiphyImageType.downsized,
            requester:self.defaultRequester)
        
        imageFetcher.nextImage { (image, ziph, error) -> () in
            
            if image != nil && ziph != nil {
                
                expectation.fulfill()
            }
        }
        
        waitForExpectations(timeout: 20) { (error) in
            
        }
        
    }
    
    func testThatPaginationWorks() {
        
        let expectation = self.expectation(description: "did download an image")
        let imageFetcher = ZiphyImageFetcher(term: "cat",
            sizeLimit: 1024*1024,
            resultslimit:2,
            imageType:ZiphyImageType.downsized,
            requester:self.defaultRequester)
        
        imageFetcher.nextImage { (image, ziph, error) -> () in
            
            if image != nil {
                
                imageFetcher.nextImage { (otherImage, otherZiph, error) -> () in
                    
                    if otherImage != nil  && otherZiph != nil {
                        
                        imageFetcher.nextImage { (otherOtherImage, otherOtherZiph, error) -> () in
                            
                            if otherOtherImage != nil && otherOtherZiph != nil {
                                
                                expectation.fulfill()
                            }
                        }
                    }
                }
            }
        }
        
        waitForExpectations(timeout: 20) { (error) in
            
        }
    }
    
    func testThatAResultSetSmallerThanTheResultLimitDoesNotTriggerAdditionalPagination() {
        
        let expectation1 = expectation(description: "first download an image")
        let expectation2 = expectation(description: "did not download an image")
        var expectation1Fulfilled = false
        
        let imageFetcher = ZiphyImageFetcher(term: "mjh",
            sizeLimit: 1024*1024*3,
            resultslimit:50,
            imageType:ZiphyImageType.downsized,
            requester:self.defaultRequester)
        
        var fetchImage : (() -> ()) = {}
        
        fetchImage = {
            imageFetcher.nextImage { (image, ziph, error) -> () in
                
                if image != nil {
                    if !expectation1Fulfilled {
                        expectation1.fulfill()
                        expectation1Fulfilled = true
                    }
                    fetchImage()
                }
                else {
                    expectation2.fulfill()
                }
            }
        }
        
        fetchImage()
        
        waitForExpectations(timeout: 20) { (error) in
            
        }
    }
    
    func testThatRecursiveCalls() {
        
        let expectation = self.expectation(description: "did not download an image")
        let imageFetcher = ZiphyImageFetcher(term: "Silent Bob",
            sizeLimit: 1024*1024*3,
            resultslimit: 50,
            imageType:ZiphyImageType.downsized,
            requester:self.defaultRequester)
        
        var recurse:(_ stopAt:Int, _ currentCallIndex:Int, _ forceStop:Bool)->() = { (_, index, _) in  return }
        
        recurse = { (stop, index, forceStop) in
            
            if forceStop {
                return
            }
            
            if index >= stop {
                expectation.fulfill()
                return
            }
            
            imageFetcher.nextImage { (otherImage, otherZiph, error) -> () in
                
                if otherImage != nil && otherZiph != nil {
                    
                    recurse(stop, index+1, false)
                }
                else {
                    recurse(index+1, index+1, true)
                }
            }
        }
        
        imageFetcher.nextImage { (imageData, otherZiph, error) -> () in
            if imageData != nil && otherZiph != nil {
                recurse(10, 1, false)
            }
        }
        
        waitForExpectations(timeout: 60) { (error) in
            
        }
    }
    
    
    func testThatARandomGifIdIsReturned() {
        
        let ziphy = ZiphyClient(host:"api.giphy.com", requester:self.defaultRequester)
        let expectation = self.expectation(description: "did return a gifID")
        
        
        ziphy.randomGif { (success, gifId, error) -> () in
            
            if success && error == nil && gifId != "" {
                expectation.fulfill()
            }
        }
        
        waitForExpectations(timeout: 20) { (error) in

        }
        
    }
    
    func testThatGifsByIdReturnsAnArray() {
        
        let ziphy = ZiphyClient(host:"api.giphy.com", requester:self.defaultRequester)
        let expectation = self.expectation(description: "did return an array")
        
        ziphy.gifsById(ids:["feqkVgjJpYtjy", "7rzbxdu0ZEXLy"]) { (success, ziphs, error) -> () in
            
            if success && error == nil && ziphs.count == 2 {
                expectation.fulfill()
            }
        }
        
        waitForExpectations(timeout: 20) { (error) in
            
        }
    }
    
    func testThatARandomGifIsFetched() {
        
        let expectation = self.expectation(description: "did download an image")
        let imageFetcher = ZiphyImageFetcher(term: "", sizeLimit: 1024*1024*3, imageType:ZiphyImageType.downsized, requester:self.defaultRequester)
        
        imageFetcher.nextImage { (image, ziph, error) -> () in
            
            if image != nil && ziph != nil {
                expectation.fulfill()
            }
        }
        
        waitForExpectations(timeout: 20) { (error) in

        }
    }
    
}
