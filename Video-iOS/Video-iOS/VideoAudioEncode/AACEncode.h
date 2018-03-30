//
//  AACEncode.h
//  Video-iOS
//
//  Created by zyyt on 2018/3/29.
//  Copyright © 2018年 Gentear. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>
@protocol AACEncodeDelegate <NSObject>

- (void)AACCallBackData:(NSData *)audioData;

@end

@interface AACEncode : NSObject

/**<#desc#>*/
@property (nonatomic, weak) id<AACEncodeDelegate> delegate;
/**通过sampleBuffer流获取data数据*/
- (void)encodeSampleBuffer:(CMSampleBufferRef)sampleBuffer;
/**结束硬编码 内部自动销毁*/
- (void)endAudioToolBox;
@end
