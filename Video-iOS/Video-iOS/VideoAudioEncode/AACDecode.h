//
//  AACDecode.h
//  Video-iOS
//
//  Created by zyyt on 2018/3/30.
//  Copyright © 2018年 Gentear. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
@interface AACDecode : NSObject

- (void)encodeAudio:(NSData *)data;
@end
