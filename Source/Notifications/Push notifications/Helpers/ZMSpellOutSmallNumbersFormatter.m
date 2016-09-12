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


#import "ZMSpellOutSmallNumbersFormatter.h"




@interface ZMSpellOutSmallNumbersFormatter ()

@property (nonatomic) NSNumberFormatter *spellOut;
@property (nonatomic) NSNumberFormatter *other;

@end



@implementation ZMSpellOutSmallNumbersFormatter

+ (instancetype)sharedFormatter;
{
    static ZMSpellOutSmallNumbersFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[self alloc] init];
    });
    return formatter;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.spellOut = [[NSNumberFormatter alloc] init];
        self.spellOut.numberStyle = NSNumberFormatterSpellOutStyle;
        self.spellOut.formattingContext = NSFormattingContextDynamic;
        
        self.other = [[NSNumberFormatter alloc] init];
        self.other.numberStyle = NSNumberFormatterDecimalStyle;
        self.other.formattingContext = NSFormattingContextDynamic;
    }
    return self;
}

- (NSString *)stringForObjectValue:(id)obj;
{
    return [obj isKindOfClass:NSNumber.class] ? [self stringFromNumber:obj] : @"";
}

- (NSString *)stringFromNumber:(NSNumber *)number
{
    if ([number integerValue] < 10) {
        return [self.spellOut stringFromNumber:number];
    }
    else {
        return [self.other stringFromNumber:number];
    }
}

- (NSLocale *)locale;
{
    return self.spellOut.locale;
}

- (void)setLocale:(NSLocale *)locale;
{
    self.spellOut.locale = locale;
    self.other.locale = locale;
}

@end
