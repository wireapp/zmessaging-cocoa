//
//  RegistrationStatusTests.swift
//  WireSyncEngine-ios
//
//  Created by Bill Chan on 08.11.17.
//  Copyright © 2017 Zeta Project Gmbh. All rights reserved.
//

import Foundation
@testable import WireSyncEngine

class RegistrationStatusTests : MessagingTest{
    var sut : WireSyncEngine.RegistrationStatus!

    override func setUp() {
        super.setUp()
        sut = WireSyncEngine.RegistrationStatus()
    }

    override func tearDown() {
        sut = nil

        super.tearDown()
    }

    func testStartWithPhaseNone(){

    }
}

