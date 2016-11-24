//
//  RandomHandleGenerator.swift
//  zmessaging-cocoa
//
//  Created by Marco Conti on 24/11/16.
//  Copyright © 2016 Zeta Project Gmbh. All rights reserved.
//

import Foundation

struct RandomHandleGenerator {
    
    /// Generate somes random handles for the given display name
    static func generateRandomHandles(displayName: String) -> [String] {
        let base = displayName.normalizedForUserHandle
        return [base]
    }
    
}

let maximumUserHandleLength = 21

extension String {
    
    /// Normalized user handle form
    public var normalizedForUserHandle : String {
        let stripped = self.translitteratedToLatin
            .spacesAndPuctationToUnderscore
            .onlyAlphanumeric
        return stripped.substring(to: stripped.index(stripped.startIndex, offsetBy: maximumUserHandleLength))
    }
    
    
    /// Removes punctation and spaces from self and collapses them into a single "_"
    fileprivate var spacesAndPuctationToUnderscore : String {
        let charactersToRemove = CharacterSet.punctuationCharacters
            .union(CharacterSet.whitespacesAndNewlines)
            .union(CharacterSet.controlCharacters)
        return self.components(separatedBy: charactersToRemove).joined(separator: "_")
    }
    
    /// Returns self transliterated to latin base
    fileprivate var translitteratedToLatin : String {
        let mutableString = NSMutableString(string: self) as CFMutableString
        for transform in [kCFStringTransformToLatin, kCFStringTransformStripDiacritics, kCFStringTransformStripCombiningMarks] {
            CFStringTransform(mutableString, nil, transform, false)
        }
        return String(mutableString)
    }
    
    /// returns self only with alphanumeric and underscore
    fileprivate var onlyAlphanumeric : String {
        let charactersToKeep = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        return self.components(separatedBy: charactersToKeep.inverted).joined(separator: "")
    }
}
