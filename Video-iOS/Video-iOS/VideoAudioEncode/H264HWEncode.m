//
//  H264HWEncode.m
//  Video-iOS
//
//  Created by zyyt on 2018/3/27.
//  Copyright © 2018年 Gentear. All rights reserved.
//

#import "H264HWEncode.h"
#import "EncodeHeader.h"
@interface H264HWEncode()
{
    int frameID;
    dispatch_queue_t mEncodeQueue;
    VTCompressionSessionRef EncodeSession;
    CMFormatDescriptionRef format;
}
/**<#desc#>*/
//@property (nonatomic, strong) NSOperationQueue *<#name#>;
@end

@implementation H264HWEncode
- (instancetype)init{
    if (self = [super init]) {
        mEncodeQueue =  dispatch_get_global_queue(0, 0);
        [self initVideoToolBox];
        self.frameInterval = 10;
        self.fps = 10;
        int width = 480 , height = 640;
        self.bitRateLimit = width * height * 3 * 4;
        self.bitRate = width * height * 3 * 4 * 8;
    }
    return self;
}
- (void)setFrameInterval:(int)frameInterval{
    _frameInterval = frameInterval;
    dispatch_sync(mEncodeQueue, ^{
        //设置关键帧（GOPsize）间隔
        CFNumberRef frameIntervalRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &frameInterval);
        VTSessionSetProperty(EncodeSession, kVTCompressionPropertyKey_MaxKeyFrameInterval, frameIntervalRef);
        VTCompressionSessionPrepareToEncodeFrames(EncodeSession);
        CFRelease(frameIntervalRef);
    });
}
- (void)setFps:(int)fps{
    _fps = fps;
    dispatch_sync(mEncodeQueue, ^{
        //设置期望帧率
        CFNumberRef fpsRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &fps);
        VTSessionSetProperty(EncodeSession, kVTCompressionPropertyKey_ExpectedFrameRate, fpsRef);
        VTCompressionSessionPrepareToEncodeFrames(EncodeSession);
        CFRelease(fpsRef);
    });
}
- (void)setBitRate:(int)bitRate{
    _bitRate = bitRate;
    dispatch_sync(mEncodeQueue, ^{
        //设置码率 均值  单位是byte
        CFNumberRef bitRateRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &bitRate);
        VTSessionSetProperty(EncodeSession, kVTCompressionPropertyKey_AverageBitRate, bitRateRef);
        VTCompressionSessionPrepareToEncodeFrames(EncodeSession);
        CFRelease(bitRateRef);
    });
}
- (void)setBitRateLimit:(int)bitRateLimit{
    _bitRateLimit = bitRateLimit;
    dispatch_sync(mEncodeQueue, ^{
        //设置码率 ， 上限  单位是bps
        CFNumberRef bitRateLimitRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &bitRateLimit);
        VTSessionSetProperty(EncodeSession, kVTCompressionPropertyKey_DataRateLimits, bitRateLimitRef);
        VTCompressionSessionPrepareToEncodeFrames(EncodeSession);
        CFRelease(bitRateLimitRef);
    });
}
- (void)initVideoToolBox{
    if (EncodeSession) {
        return;
    }
    dispatch_sync(mEncodeQueue, ^{
        frameID = 0;
        int width = 480 , height = 640;
        OSStatus status = VTCompressionSessionCreate(NULL, width, height, kCMVideoCodecType_H264 , NULL, NULL, NULL, didCompressH264,(__bridge void *)(self), &EncodeSession);
        
        NSLog(@"H264: VTCompressionSessionCreate %d", (int)status);
        //成功
        if (status != 0)
        {
            NSLog(@"H264: Unable to create a H264 session");
            return ;
        }
        //设置实时编码输出（避免延迟）
        VTSessionSetProperty(EncodeSession, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue);
        VTSessionSetProperty(EncodeSession, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_Baseline_AutoLevel);
        VTCompressionSessionPrepareToEncodeFrames(EncodeSession);
    });
}
- (void)encode:(CMSampleBufferRef)sampleBuffer{
    dispatch_sync(mEncodeQueue, ^{
        //将sampleBuffer转为CVImageBuffer
        CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        
        //帧时间  如果不设置会导致时间轴过长
        CMTime presenetationTimeStamp = CMTimeMake(frameID ++, 1000);
        VTEncodeInfoFlags flags;
        [self initVideoToolBox];
        OSStatus stasusCode = VTCompressionSessionEncodeFrame(EncodeSession, imageBuffer, presenetationTimeStamp, kCMTimeInvalid, NULL, NULL, &flags);
        
        //        NSAssert(stasusCode == noErr, [NSError errorWithDomain:NSOSStatusErrorDomain code:stasusCode userInfo:nil].localizedDescription);
        
        if (stasusCode != noErr) {
            NSLog(@"H264: VTCompressionSessionEncodeFrame faild  with %d", (int)stasusCode);
            
            VTCompressionSessionInvalidate(EncodeSession);
            CFRelease(EncodeSession);
            EncodeSession = NULL;
            return;
        }
        NSLog(@"VTCompressionSessionEncodeFrame success");
    });
}
/**
 *  编码完成的回调
 */
void didCompressH264(void *  outputCallbackRefCon, void *  sourceFrameRefCon,OSStatus status,VTEncodeInfoFlags infoFlags, CMSampleBufferRef sampleBuffer){
    
    NSLog(@"didCompressH264 called with status %d infoFlags %d",(int)status , (int)infoFlags);
    
    if (status != 0) {
        return;
    }
    if (!CMSampleBufferDataIsReady(sampleBuffer)) {
        NSLog(@"didCompressH264 data is not ready");
    }
    H264HWEncode *encoder = (__bridge H264HWEncode *)outputCallbackRefCon;
    
    //判断当前帧是否为关键帧
    bool keyframe = !CFDictionaryContainsKey((CFArrayGetValueAtIndex(CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, true), 0)), kCMSampleAttachmentKey_NotSync);
    
    //获取sps & pps数据
    if (keyframe) {
        CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sampleBuffer);
        size_t sparameterSetSize , sparameterSetCount;
        const uint8_t *sparameterSet;
        OSStatus statusCode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 0, &sparameterSet, &sparameterSetSize, &sparameterSetCount, 0);
        if (statusCode == noErr) {
            size_t pparameterSetSize,pparameterSetCount;
            const uint8_t * pparameterSet;
            OSStatus statusCode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 1, &pparameterSet, &pparameterSetSize, &pparameterSetCount, 0);
            if (statusCode == noErr) {
                
                NSData *sps = [NSData dataWithBytes:sparameterSet length:sparameterSetSize];
                NSData *pps = [NSData dataWithBytes:pparameterSet length:pparameterSetSize];
                
                if (encoder) {
                    [encoder getSpsPps:sps pps:pps];
                }
            }
        }
    }
    
    CMBlockBufferRef dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    //偏移长  和   全长
    size_t length,totalLength;
    //数据
    char *dataPointer;
    OSStatus statusCodeRet = CMBlockBufferGetDataPointer(dataBuffer, 0, &length, &totalLength, &dataPointer);
    
    if (statusCodeRet == noErr) {
        
        size_t bufferOffset = 0 ;
        
        static const int AVCCHeaderLength = 4;
        //从末尾往前写入数据
        while (bufferOffset < totalLength - AVCCHeaderLength) {
            
            uint32_t NALUintLength = 0;
            //字符串拷贝
            memcpy(&NALUintLength, dataPointer + bufferOffset, AVCCHeaderLength);
            
            //从大端转小端  由高地址保存低位 ----> 高地址保存高位
            NALUintLength = CFSwapInt32BigToHost(NALUintLength);
            
            NSData *data = [[NSData alloc]initWithBytes:(dataPointer + bufferOffset + AVCCHeaderLength) length:NALUintLength];
            [encoder gotEncodedData:data isKeyFrame:keyframe];
            
            // Move to the next NAL unit in the block buffer
            bufferOffset += AVCCHeaderLength + NALUintLength;
        }
        
    }
}
- (void)getSpsPps:(NSData *)sps pps:(NSData *)pps{
    NSLog(@"gotSpsPps %d %d",(int)[sps length],(int)[pps length]);
    if ([self.delegate respondsToSelector:@selector(getSpsPps:pps:byteHeader:)]) {
        [self.delegate getSpsPps:sps pps:pps byteHeader:[self getByteData]];
    }
}
- (void)gotEncodedData:(NSData*)data isKeyFrame:(BOOL)isKeyFrame
{
    NSLog(@"gotEncodedData %d", (int)[data length]);
    if ([self.delegate respondsToSelector:@selector(gotEncodedData:byteHeader:isKeyFrame:)]) {
        [self.delegate gotEncodedData:data byteHeader:[self getByteData] isKeyFrame:isKeyFrame];
    }
}
- (NSData *)getByteData{
    const char bytes[] = "\x00\x00\x00\x01";
    size_t length = (sizeof bytes) - 1; //string literals have implicit trailing '\0'
    return [NSData dataWithBytes:bytes length:length];
}
- (void)endVideoToolBox{
    VTCompressionSessionCompleteFrames(EncodeSession, kCMTimeInvalid);
    VTCompressionSessionInvalidate(EncodeSession);
    CFRelease(EncodeSession);
    CFRelease(format);
    EncodeSession = NULL;
}
- (void)dealloc{
    [self endVideoToolBox];
}
@end
