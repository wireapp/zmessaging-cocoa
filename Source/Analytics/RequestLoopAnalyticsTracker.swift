//
//  RequestLoopAnalyticsTracker.swift
//  zmessaging-cocoa
//
//  Created by Florian Morel on 10/19/16.
//  Copyright © 2016 Zeta Project Gmbh. All rights reserved.
//

import Foundation

@objc public class RequestLoopAnalyticsTracker : NSObject {
    
    weak var analytic : AnalyticsType?
    
    @objc(initWithAnalytics:)
    public init(with : AnalyticsType) {
        analytic = with
    }

    @objc(tagWithPath:)
    public func tag(with: String) -> Void {
        if let analytic = analytic {
            analytic.tagEvent("request.loop", attributes: ["path": with as NSObject])
        }
    }
}
