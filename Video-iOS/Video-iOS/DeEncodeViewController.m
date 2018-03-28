//
//  DeEncodeViewController.m
//  Video-iOS
//
//  Created by zyyt on 2018/3/23.
//  Copyright © 2018年 Gentear. All rights reserved.
//

#import "DeEncodeViewController.h"
#import <VideoToolbox/VideoToolbox.h>
#import "AAPLEAGLLayer.h"
const uint8_t lyStartCode[4] = {0, 0 ,0 , 1};

@interface DeEncodeViewController ()
@property (nonatomic , strong) AAPLEAGLLayer *playLayer;
@property (nonatomic, strong) NSInputStream *inputStream;
@property (nonatomic, strong) CADisplayLink *disPlayLink;
@property (nonatomic , strong) UILabel  *mLabel;
@property (nonatomic , strong) UIButton *mButton;
@end

@implementation DeEncodeViewController
{
    dispatch_queue_t mDecodeQueue;
    VTDecompressionSessionRef sessionRef;
    CMFormatDescriptionRef formatDescriptionOut;
    uint8_t *mSPS;
    long mSPSSize;
    uint8_t *mPPS;
    long mPPSSize;
    //输入
    uint8_t * packetBuffer;
    long packetSize;
    uint8_t * inputBuffer;
    long inputSize;
    long inputMaxSize;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    self.view.backgroundColor = [UIColor whiteColor];
    
    [self playLayer];

    mDecodeQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    [self mLabel];
    [self mButton];
    [self disPlayLink];
    
}
- (void)onClick:(UIButton *)btn{
    btn.hidden = YES;
    [self inputStream];
    [self.disPlayLink setPaused:NO];
}
- (void)updataFrame{
    if (_inputStream) {
        dispatch_sync(mDecodeQueue, ^{
            
            [self readPacket];
            
            if (packetBuffer == NULL || packetSize == 0) {
                [self onInputEnd];
                return ;
            }
            uint32_t nalSize = (uint32_t)(packetSize -4);
            uint32_t * pNalSize = (uint32_t *)packetBuffer;
            *pNalSize = CFSwapInt32HostToBig(nalSize);
            
            //buffer的前面填入代表长度的int
            CVPixelBufferRef pixelBuffer = NULL;
            int nalType = packetBuffer[4] & 0x1F;
            switch (nalType) {
                case 0x05:
                    NSLog(@"NAL type is IDR frame");
                    [self initVideoToolBox];
                    pixelBuffer = [self decode];
                    break;
                case 0x07:
                    NSLog(@"NAL type is SPS");
                    mSPSSize = packetSize - 4;
                    mSPS = malloc(mSPSSize);
                    memcpy(mSPS, packetBuffer + 4, mSPSSize);
                    break;
                case 0x08:
                    NSLog(@"NAL type is PPS");
                    mPPSSize = packetSize -  4;
                    mPPS = malloc(mPPSSize);
                    memcpy(mPPS, packetBuffer + 4, mPPSSize);
                default:
                    NSLog(@"Nal type is B/P frame");
                    pixelBuffer = [self decode];
                    break;
            }
            NSLog(@"Read Nalu size %ld", packetSize);
            
        });
    }
}
- (void)readPacket{
    
    if (packetSize && packetBuffer) {
        packetSize = 0;
        free(packetBuffer);
        packetBuffer = NULL;
    }
    
    if (inputSize < inputMaxSize && _inputStream.hasBytesAvailable) {
        inputSize += [_inputStream read:inputBuffer + inputSize maxLength:inputMaxSize - inputSize];
    }
    if (memcmp(inputBuffer, lyStartCode , 4) == 0) {
        if (inputSize > 4) {
            uint8_t *pStart = inputBuffer + 4;
            uint8_t *pEnd = inputBuffer + inputSize;
            
            while (pStart != pEnd) {
                if (memcmp(pStart - 3, lyStartCode, 4) == 0) {
                    packetSize = pStart - inputBuffer - 3;
                    if (packetBuffer) {
                        free(packetBuffer);
                        packetBuffer = NULL;
                    }
                    packetBuffer = malloc(packetSize);
                    //复制packet内容到缓冲区
                    memcpy(packetBuffer , inputBuffer , packetSize);
                    //把缓冲区前移
                    memmove(inputBuffer, inputBuffer + packetSize, inputSize - packetSize);
                    inputSize -= packetSize;
                    break;
                }else{
                    ++ pStart;
                }
            }
        }
    }
}

- (CVPixelBufferRef)decode{
    CVPixelBufferRef  outputPixelBuffer = NULL;
    if (sessionRef) {
        CMBlockBufferRef blockBuffer = NULL;
        OSStatus status = CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault, (void *)packetBuffer, packetSize, kCFAllocatorNull, NULL, 0, packetSize, 0, &blockBuffer);
        
        if (status == kCMBlockBufferNoErr) {
            CMSampleBufferRef sampleBuffer = NULL;
            const size_t sampleSizeArray[] = {packetSize};
            status = CMSampleBufferCreateReady(kCFAllocatorDefault, blockBuffer, formatDescriptionOut, 1, 0, NULL, 1, sampleSizeArray, &sampleBuffer);
            
            if (status == kCMBlockBufferNoErr && sampleBuffer) {
                VTDecodeFrameFlags flags = 0;
                VTDecodeInfoFlags flagOut = 0;
                
                //默认是同步操作
                //调用didDecompress 返回后回调
                OSStatus decodeStatus = VTDecompressionSessionDecodeFrame(sessionRef, sampleBuffer, flags, &outputPixelBuffer, &flagOut);
                
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
    return outputPixelBuffer;
}

- (void)onInputEnd{
    [_inputStream close];
    _inputStream = nil;
    if (inputBuffer) {
        free(inputBuffer);
        inputBuffer = NULL;
    }
    [self.disPlayLink setPaused:YES];
    self.mButton.hidden = NO;
}
- (void)initVideoToolBox{
    if (!sessionRef) {
        const uint8_t* parameterSetPointers[2] = {mSPS,mPPS};
        const size_t parameterSetSizes[2] = {mSPSSize,mPPSSize};
        OSStatus status = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault, 2, parameterSetPointers, parameterSetSizes, 4, &formatDescriptionOut);
        
        if (status == noErr) {
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
            
            CFRelease(attrs);
        }else{
            NSLog(@"IOS8VT: reset decoder session failed status=%d", status);
        }
    }
}
- (void)endVideoToolBox{
    if (sessionRef) {
        VTDecompressionSessionInvalidate(sessionRef);
        CFRelease(sessionRef);
        sessionRef = NULL;
    }
    if (formatDescriptionOut) {
        CFRelease(formatDescriptionOut);
        formatDescriptionOut = NULL;
    }
    free(mSPS);
    free(mPPS);
    mSPSSize = mPPSSize = 0;
}
void didDecompress(void *  decompressionOutputRefCon,void *  sourceFrameRefCon, OSStatus status, VTDecodeInfoFlags infoFlags,  CVImageBufferRef imageBuffer, CMTime presentationTimeStamp, CMTime presentationDuration){
    
    CVPixelBufferRef *outputPixelBuffer = (CVPixelBufferRef *)sourceFrameRefCon;
    
    *outputPixelBuffer = CVPixelBufferRetain(imageBuffer);
    
    ((__bridge DeEncodeViewController *)decompressionOutputRefCon).playLayer.pixelBuffer = imageBuffer;
    CVPixelBufferRelease(imageBuffer);
}
- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}
#pragma mark - lazy load
//- (dispatch_queue_t)mDecodeQueue{
//    if (!_mDecodeQueue) {
//        _mDecodeQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
//    }
//    return _mDecodeQueue;
//}
- (NSInputStream *)inputStream{
    if (!_inputStream) {
        NSString * path = [[NSBundle mainBundle] pathForResource:@"abc" ofType:@"h264"];
        _inputStream = [[NSInputStream alloc]initWithFileAtPath:path];
        [_inputStream open];
        inputSize = 0 ;
        inputMaxSize = 640 * 480 * 3 * 4;
        inputBuffer = malloc(inputMaxSize);
    }
    return _inputStream;
}
- (CADisplayLink *)disPlayLink{
    if (!_disPlayLink) {
        
        _disPlayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(updataFrame)];
        _disPlayLink.frameInterval = 1; //默认是30帧
        [_disPlayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
        [_disPlayLink setPaused:YES];
        
    }
    return _disPlayLink;
}
- (AAPLEAGLLayer *)playLayer{
    if (!_playLayer) {
        _playLayer = [[AAPLEAGLLayer alloc] initWithFrame:CGRectMake(0, 0, 375, 668)];
        _playLayer.backgroundColor = [UIColor blackColor].CGColor;
        [self.view.layer addSublayer:_playLayer];
    }
    return _playLayer;
}
- (UILabel *)mLabel{
    if (!_mLabel) {
        _mLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 20, 200, 100)];
        _mLabel.textColor = [UIColor redColor];
        [self.view addSubview:_mLabel];
        _mLabel.text = @"测试H264硬解码";
    }
    return _mLabel;
}
- (UIButton *)mButton{
    if (!_mButton) {
        UIButton *button = [[UIButton alloc] initWithFrame:CGRectMake(200, 20, 100, 100)];
        [button setTitle:@"play" forState:UIControlStateNormal];
        [button setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
        [self.view addSubview:button];
        [button addTarget:self action:@selector(onClick:) forControlEvents:UIControlEventTouchUpInside];
        _mButton = button;
    }
    return _mButton;
}
/*
 #pragma mark - Navigation
 
 // In a storyboard-based application, you will often want to do a little preparation before navigation
 - (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
 // Get the new view controller using [segue destinationViewController].
 // Pass the selected object to the new view controller.
 }
 */

@end
