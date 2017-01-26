/*
* Wire
* Copyright (C) 2016 Wire Swiss GmbH
*
* This program is free software: you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation, either version 3 of the License, or
* (at your option) any later version.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
* GNU General Public License for more details.
*
* You should have received a copy of the GNU General Public License
* along with this program. If not, see <http://www.gnu.org/licenses/>.
*/
//#import <Foundation/Foundation.h>

#import "AVSMediaManager.h"

/* Make sure to keep this in sync with avs_flowmgr.h */
/*
typedef NS_ENUM(int, AVSFlowManagerCategory) {
	FLOWMANAGER_CATEGORY_NORMAL,
	FLOWMANAGER_CATEGORY_HOLD,
	FLOWMANAGER_CATEGORY_PLAYBACK,
	FLOWMANAGER_CATEGORY_CALL
};


@protocol AVSFlowManagerResponseInternal<NSObject>

- (void)mediaCategoryChanged:(NSString *)convId
                    category:(enum AVSFlowManagerCategory)mcat;

@end

@protocol AVSMediaManagerInternal <AVSMediaManager>

- (void)mediaCategoryChange:(NSString *)convId
                   category:(AVSFlowManagerCategory)cat
                    context:(void const *)ctx;


- (void)didUpdateVolume:(double)volume
          conversationId:(NSString *)convid
           participantId:(NSString *)participantId;

- (void)registerFlowManagerResponseDelegate:(id)delegate;

@end


*/
