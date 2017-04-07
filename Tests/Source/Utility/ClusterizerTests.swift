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


import Foundation
import XCTest
@testable import WireSyncEngine

class ClusterizerTests: XCTestCase {
    
    var sut: IntegerClusterizer!
    
    override func setUp() {
        super.setUp()
        sut = IntegerClusterizer(ranges: [
            ClusterRange(10, 15),
            ClusterRange(15, 25),
            ClusterRange(25, 50),
            ClusterRange(50, 100)
            ])
    }

    func testThatAClusterRangeReturnsTheCorrectStringValue() {
        let range = ClusterRange(50, 100)
        XCTAssertEqual(range.stringValue, "50-100")
    }
    
    func testThatItClustersIntValueBelowFirstRange() {
        XCTAssertEqual(sut.clusterize(7), "7")
    }
    
    func testThatItClustersIntValueStartOfRange() {
        XCTAssertEqual(sut.clusterize(10), "10-15")
    }
    
    func testThatItClustersIntValueInsideRange() {
        XCTAssertEqual(sut.clusterize(17), "15-25")
    }
    
    func testThatItClustersIntValueEndOfRange() {
        XCTAssertEqual(sut.clusterize(25), "15-25")
    }
    
    func testThatItClustersIntValueEndOfLastRange() {
        XCTAssertEqual(sut.clusterize(100), "50-100")
    }
    
    func testThatItClustersIntValueAfterLastRange() {
        XCTAssertEqual(sut.clusterize(101), "100+")
        XCTAssertEqual(sut.clusterize(1000), "100+")
    }
    
}
