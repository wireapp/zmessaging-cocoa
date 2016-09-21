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
import AudioToolbox

public enum ZMSound: String, CustomStringConvertible {
    case Bell       = "bell"
    case Calipso    = "calipso"
    case Chime      = "chime"
    case Circles    = "circles"
    case Glass      = "glass"
    case Hello      = "hello"
    case Input      = "input"
    case Keys       = "keys"
    case Note       = "note"
    case Popcorn    = "popcorn"
    case Synth      = "synth"
    case Telegraph  = "telegraph"
    case TriTone    = "tri-tone"
    
    case Harp       = "harp"
    case Marimba    = "marimba"
    case OldPhone   = "old-phone"
    case Opening    = "opening"
    
    public static let allValues = [
        Bell,
        Calipso,
        Chime,
        Circles,
        Glass,
        Hello,
        Input,
        Keys,
        Note,
        Popcorn,
        Synth,
        Telegraph,
        TriTone,
        Harp,
        Marimba,
        OldPhone,
        Opening]
    
    public static let ringtones = [
        Harp,
        Marimba,
        OldPhone,
        Opening]
    
    public func isRingtone() -> Bool {
        return type(of: self).ringtones.contains(self)
    }
    
    fileprivate static var playingPreviewID: SystemSoundID?
    fileprivate static var playingPreviewURL: URL?
    
    fileprivate static func stopPlayingPreview() {
        if let _ = self.playingPreviewURL,
            let soundId = self.playingPreviewID {
            AudioServicesDisposeSystemSoundID(soundId)
            self.playingPreviewID = .none
            self.playingPreviewURL = .none
        }
    }
    
    public static func playPreviewForURL(_ mediaURL: URL) {
        self.stopPlayingPreview()
        
        self.playingPreviewURL = mediaURL
        var soundId: SystemSoundID = 0
        
        if AudioServicesCreateSystemSoundID(mediaURL as CFURL, &soundId) == kAudioServicesNoError {
            self.playingPreviewID = soundId
        }
    
        AudioServicesPlaySystemSound(soundId)
        
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + Double(Int64(4 * NSEC_PER_SEC)) / Double(NSEC_PER_SEC)) {
            if self.playingPreviewID == soundId {
                self.stopPlayingPreview()
            }
        }
    }
    
    public func fileURL() -> URL {
        return URL(fileURLWithPath: Bundle.main.path(forResource: self.rawValue, ofType: type(of: self).fileExtension)!)
    }
    
    fileprivate static let fileExtension = "m4a"

    public func filename() -> String {
        return (self.rawValue as NSString).appendingPathExtension(type(of: self).fileExtension)!
    }
    
    public var description: String {
        get {
            return self.rawValue.capitalized
        }
    }
    
    public func playPreview() {
        type(of: self).playPreviewForURL(self.fileURL())
    }
}
