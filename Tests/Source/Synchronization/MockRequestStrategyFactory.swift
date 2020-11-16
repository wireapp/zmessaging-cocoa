//
//  MockRequestStrategyFactory.swift
//  WireSyncEngine-iOS-Tests
//
//  Created by Jacob Persson on 13.11.20.
//  Copyright © 2020 Zeta Project Gmbh. All rights reserved.
//

import Foundation

@objcMembers
public class MockRequestStrategyFactory: NSObject, RequestStrategyFactoryProtocol {
    
    let strategies: [Any]
    
    public init(strategies: [Any]) {
        self.strategies = strategies
    }
    
    public func buildStrategies() -> [Any] {
        return strategies
    }
    
}
