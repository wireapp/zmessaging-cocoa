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

public struct ClusterRange<T> {
    let start, end: T
    var stringValue: String { return "\(start)-\(end)" }
    
    init(_ start: T, _ end: T) {
        self.start = start
        self.end = end
    }
}

protocol ClusterizerType {
    associatedtype ClusterType: Comparable
    var ranges:  [ClusterRange<ClusterType>] { get }
    func clusterize(_ value: ClusterType) -> String
}

extension ClusterizerType {
    func clusterize(_ value: ClusterType) -> String {
        guard let range = ranges.first, value >= range.start else { return String(describing: value) }
        for range in ranges where range.start <= value && value <= range.end {
            return range.stringValue
        }
        
        return "\(ranges.last!.end)+"
    }
}

public struct IntegerClusterizer: ClusterizerType {
    typealias ClusterType = Int
    let ranges: [ClusterRange<ClusterType>]
}
