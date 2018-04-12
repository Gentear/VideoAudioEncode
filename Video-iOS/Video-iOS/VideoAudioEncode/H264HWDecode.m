//
//  H264HWDeEncode.m
//  Video-iOS
//
//  Created by zyyt on 2018/3/27.
//  Copyright © 2018年 Gentear. All rights reserved.
//

#import "H264HWDecode.h"
#import "EncodeHeader.h"

const uint8_t lyStartCode[4] = {0, 0, 0, 1};
@interface H264HWDecode()
{
    uint8_t *mSPS;
    NSInteger mSPSSize;
    uint8_t *mPPS;
    NSInteger mPPSSize;
    VTDecompressionSessionRef sessionRef;
    CMVideoFormatDescriptionRef formatDescriptionOut;
}
/**<#desc#>*/
@property (nonatomic, strong) NSOperationQueue *operationQueue;
@end

@implementation H264HWDecode
- (instancetype)init{
    if (self = [super init]) {
        [self operationQueue];
    }
    return self;
}
- (void)decodeNalu:(NSData *)frameData{
    [self.operationQueue addOperationWithBlock:^{
        uint8_t * frameBuffer = (uint8_t *)[frameData bytes];
        uint32_t frameSize = (uint32_t)frameData.length;
        
        if(frameBuffer == NULL || frameSize == 0) {
            return ;
        }
        uint32_t nalSize = (uint32_t)(frameSize - 4);
        uint32_t *pNalSize = (uint32_t *)frameBuffer;
        *pNalSize = CFSwapInt32HostToBig(nalSize);
        
        // 在buffer的前面填入代表长度的int
        //                CVPixelBufferRef pixelBuffer = NULL;
        int nalType = frameBuffer[4] & 0x1F;
        
        switch (nalType) {
            case 0x05:
                NSLog(@"NAL type is IDR frame");
                [self initVideoToolBox];
                //                pixelBuffer = [self decodeFrame:frameBuffer frameSize:frameSize];
                [self decodeFrame:frameBuffer frameSize:frameSize];
                break;
            case 0x07:
                NSLog(@"NAL type is SPS");
                mSPSSize = frameSize - 4; //15
                mSPS = malloc(mSPSSize);
                memcpy(mSPS, frameBuffer + 4, mSPSSize);
                break;
            case 0x08:
                NSLog(@"NAL type is PPS");
                mPPSSize = frameSize -  4;
                mPPS = malloc(mPPSSize);
                memcpy(mPPS, frameBuffer + 4, mPPSSize);
                break;
            default:
                NSLog(@"Nal type is B/P frame");
                [self initVideoToolBox];
                //                                pixelBuffer = [self decodeFrame:frameBuffer frameSize:frameSize];
                [self decodeFrame:frameBuffer frameSize:frameSize];
                break;
        }
        NSLog(@"Read Nalu size %u", frameSize);
    }];
}
//CVPixelBufferRef
- (void)decodeFrame:(uint8_t *)frame  frameSize:(uint32_t)frameSize{
    CVPixelBufferRef  outputPixelBuffer = NULL;
    if (sessionRef) {
        CMBlockBufferRef blockBuffer = NULL;
        OSStatus status = CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault, (void *)frame, frameSize, kCFAllocatorNull, NULL, 0, frameSize, FALSE, &blockBuffer);
        
        if (status == kCMBlockBufferNoErr) {
            CMSampleBufferRef sampleBuffer = NULL;
            const size_t sampleSizeArray[] = {frameSize};
            status = CMSampleBufferCreateReady(kCFAllocatorDefault, blockBuffer, formatDescriptionOut, 1, 0, NULL, 1, sampleSizeArray, &sampleBuffer);
            
            if (status == kCMBlockBufferNoErr && sampleBuffer) {
                VTDecodeFrameFlags flags = 0;
                VTDecodeInfoFlags flagOut = 0;
                
                //默认是同步操作
                //调用didDecompress 返回后回调
                OSStatus decodeStatus = VTDecompressionSessionDecodeFrame(sessionRef, sampleBuffer, flags, &outputPixelBuffer, &flagOut);
                
                /**
                 * B/P帧可能会丢失  此处状态报错为-12911
                 */
                if (decodeStatus == kVTInvalidSessionErr) {
                    NSLog(@"IOS8VT: Invalid session, reset decoder session");
                }else if(decodeStatus == kVTVideoDecoderBadDataErr){
                    NSLog(@"IOS8VT: decode failed status=%d(Bad data)",(int )decodeStatus);
                }else if(decodeStatus != noErr){
                    NSLog(@"IOS8VT: decode failed status=%d",(int)decodeStatus);
                }
                
                CFRelease(sampleBuffer);
            }
            CFRelease(blockBuffer);
        }
        
    }
//    return outputPixelBuffer;
}
- (void)initVideoToolBox{
    if (!sessionRef) {
        const uint8_t* parameterSetPointers[2] = {mSPS,mPPS};
        const size_t parameterSetSizes[2] = {mSPSSize,mPPSSize};
        OSStatus status = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault, 2, parameterSetPointers, parameterSetSizes, 4, &formatDescriptionOut);
        
        NSAssert(status == noErr, [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil].localizedDescription);
        
        //        if (status == noErr) {
        CFDictionaryRef attrs = NULL;
        
        const void *key[] = {kCVPixelBufferPixelFormatTypeKey};
        uint32_t v = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange;
        const void *values[] = {CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type , &v)};
        attrs = CFDictionaryCreate(kCFAllocatorDefault, key , values, 1, NULL, NULL);
        
        //回调
        VTDecompressionOutputCallbackRecord callBackRecord;
        callBackRecord.decompressionOutputCallback = didDecompress;
        callBackRecord.decompressionOutputRefCon = (__bridge void *)self;
        //创建解码器
        status = VTDecompressionSessionCreate(kCFAllocatorDefault, formatDescriptionOut , NULL, attrs, &callBackRecord, &sessionRef);
        NSAssert(status == noErr, [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil].localizedDescription);
        
        VTSessionSetProperty(sessionRef, kVTDecompressionPropertyKey_ThreadCount, (__bridge CFTypeRef)[NSNumber numberWithInt:1]);
        VTSessionSetProperty(sessionRef, kVTDecompressionPropertyKey_RealTime, kCFBooleanTrue);
        CFRelease(attrs);
        //        }else{
        //            NSLog(@"IOS8VT: reset decoder session failed status=%d", (int)status);
        //        }
    }
}

void didDecompress(void *  decompressionOutputRefCon,void *  sourceFrameRefCon, OSStatus status, VTDecodeInfoFlags infoFlags,  CVImageBufferRef imageBuffer, CMTime presentationTimeStamp, CMTime presentationDuration){
    
    CVPixelBufferRef *outputPixelBuffer = (CVPixelBufferRef *)sourceFrameRefCon;
    
    *outputPixelBuffer = CVPixelBufferRetain(imageBuffer);
    
    H264HWDecode * deEncode = (__bridge H264HWDecode *)decompressionOutputRefCon;
    
    if ([deEncode.delegate respondsToSelector:@selector(displayDecodedFrame:)]) {
        [deEncode.delegate displayDecodedFrame:imageBuffer];
    }
    CVPixelBufferRelease(imageBuffer);
}
- (void)dealloc{
    [self endVideoToolBox];
}
- (void)endVideoToolBox{
    if(sessionRef) {
        VTDecompressionSessionInvalidate(sessionRef);
        CFRelease(sessionRef);
        sessionRef = NULL;
    }
    
    if(formatDescriptionOut) {
        CFRelease(formatDescriptionOut);
        formatDescriptionOut = NULL;
    }
    
    free(mSPS);
    free(mPPS);
    mSPSSize = mPPSSize = 0;
}
#pragma mark - 懒加载
- (NSOperationQueue *)operationQueue {
    if (!_operationQueue) {
        _operationQueue = [NSOperationQueue alloc].init;
        _operationQueue.maxConcurrentOperationCount = 1;
    }
    return _operationQueue;
}
@end
