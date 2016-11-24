//
//  RandomHandleGeneratorTests.swift
//  zmessaging-cocoa
//
//  Created by Marco Conti on 24/11/16.
//  Copyright © 2016 Zeta Project Gmbh. All rights reserved.
//

import Foundation
import XCTest
@testable import zmessaging

class RandomHandleGeneratorTests : XCTestCase {
    
    func testNormalizationOfString() {
        XCTAssertEqual("Maria LaRochelle".normalizedForUserHandle, "marie_larochelle")
    }
    
}
