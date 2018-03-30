//
//  H264HWEncode.h
//  Video-iOS
//
//  Created by zyyt on 2018/3/27.
//  Copyright © 2018年 Gentear. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <CoreMedia/CoreMedia.h>
#import <AVFoundation/AVFoundation.h>
#import <VideoToolbox/VideoToolbox.h>
#import <AudioToolbox/AudioToolbox.h>

@protocol H264HWEncodeDelegate <NSObject>
/**
 sps和pps数据
 [fileHanle writeData:byteHeader];
 [fileHanle writeData:sps];
 [fileHanle writeData:byteHeader];
 [fileHanle writeData:pps];
 */
- (void)getSpsPps:(NSData *)sps pps:(NSData *)pps byteHeader:(NSData *)byteHeader;
/**
 编码数据
 [fileHanle writeData:ByteHeader];
 [fileHanle writeData:data];
 */
- (void)gotEncodedData:(NSData*)data byteHeader:(NSData *)byteHeader isKeyFrame:(BOOL)isKeyFrame ;

@end

@interface H264HWEncode : NSObject
/**代理*/
@property (nonatomic, weak) id<H264HWEncodeDelegate> delegate;
/**设置关键帧（GOPsize）间隔*/
@property (nonatomic, assign) int frameInterval;
/**设置期望帧率*/
@property (nonatomic, assign) int fps;
/**设置码率 均值  单位是byte*/
@property (nonatomic, assign) int bitRate;
/**设置码率 ， 上限  单位是bps*/
@property (nonatomic, assign) int bitRateLimit;
/**传入视频流*/
- (void)encode:(CMSampleBufferRef)sampleBuffer;
/**结束硬编码 内部自动销毁*/
- (void)endVideoToolBox;
@end
