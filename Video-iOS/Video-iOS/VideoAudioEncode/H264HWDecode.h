//
//  H264HWDeEncode.h
//  Video-iOS
//
//  Created by zyyt on 2018/3/27.
//  Copyright © 2018年 Gentear. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <VideoToolbox/VideoToolbox.h>
@protocol H264HWDeEncodeDelegate <NSObject>
/**拿到coreVide缓冲*/
- (void)displayDecodedFrame:(CVImageBufferRef )imageBuffer;
@end


@interface H264HWDecode : NSObject
/**代理*/
@property (nonatomic, weak) id<H264HWDeEncodeDelegate> delegate;
/**参考viewController中的方式传参*/
- (void)decodeNalu:(NSData *)frameData;
/**结束硬编码 内部自动销毁*/
- (void)endVideoToolBox;
@end
