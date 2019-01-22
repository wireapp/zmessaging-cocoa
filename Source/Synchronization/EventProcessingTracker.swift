//
// Wire
// Copyright (C) 2019 Wire Swiss GmbH
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
import WireDataModel

@objc public protocol EventProcessingTrackerProtocol: class {
    func registerStartedProcessing()
    func registerEventProcessed()
    
    @objc(registerCoreDataChangedBy:)
    func registerCoreDataChanged(by amount: Double)
    func registerSavePerformed()
    var debugDescription: String { get }
}

@objc public class EventProcessingTracker: NSObject, EventProcessingTrackerProtocol {

    var eventAttributes = [String : [String : NSObject]]()
    let eventName = "event.processing"
    
    enum Attributes: String {
        case startedProcessing
        case processedEvents
        case coreDataChanges
        case savesPerformed
        
        var identifier: String {
            return "event_" + rawValue
        }
    }
    
    private let isolationQueue = DispatchQueue(label: "EventProcessing")
    
    public override init() {
        super.init()
    }
    
    @objc public func registerStartedProcessing() {
        save(attribute: .startedProcessing, value: Date().timeIntervalSince1970)
    }
    
    @objc public func registerEventProcessed() {
        increment(attribute: .processedEvents)
    }
    
    @objc public func registerCoreDataChanged(by amount: Double = 1) {
        increment(attribute: .coreDataChanges, by: amount)
    }
    
    @objc public func registerSavePerformed() {
        increment(attribute: .savesPerformed)
    }
    
    private func increment(attribute: Attributes, by amount: Double = 1) {
        isolationQueue.sync {
            var currentAttributes = persistedAttributes(for: eventName) ?? [:]
            var value = (currentAttributes[attribute.identifier] as? Double) ?? 0
            value += amount
            currentAttributes[attribute.identifier] = value as NSObject
            setPersistedAttributes(currentAttributes, for: eventName)
        }
    }
    
    private func save(attribute: Attributes, value: Double) {
        isolationQueue.sync {
            var currentAttributes = persistedAttributes(for: eventName) ?? [:]
            var currentValue = (currentAttributes[attribute.identifier] as? Double) ?? 0
            currentValue = value
            currentAttributes[attribute.identifier] = currentValue as NSObject
            setPersistedAttributes(currentAttributes, for: eventName)
        }
    }
    
    public func dispatchEvent() {
        isolationQueue.sync {
            if let attributes = persistedAttributes(for: eventName), !attributes.isEmpty {
                setPersistedAttributes(nil, for: eventName)
            }
        }
    }
    
    private func setPersistedAttributes(_ attributes: [String : NSObject]?, for event: String) {
        if let attributes = attributes {
            eventAttributes[event] = attributes
        } else {
            eventAttributes.removeValue(forKey: event)
        }
        print(Date(), "EventProcessing", #function, event, eventAttributes[event] ?? [:])
    }
    
    private func persistedAttributes(for event: String) -> [String : NSObject]? {
        let value = eventAttributes[event] ?? [:]
        print(Date(), "EventProcessing", #function, event, value)
        return value
    }
    
    override public var debugDescription: String {
        return "Events performed current values: \(persistedAttributes(for: eventName) ?? [:])"
    }
}
