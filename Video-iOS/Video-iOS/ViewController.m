//
//  ViewController.m
//  Video-iOS
//
//  Created by zyyt on 2018/3/20.
//  Copyright © 2018年 Gentear. All rights reserved.
//

#import "ViewController.h"
#import "H264HWEncode.h"
#import "H264HWDecode.h"
#import "AAPLEAGLLayer.h"
#import <AVFoundation/AVFoundation.h>
#import <VideoToolbox/VideoToolbox.h>
#import <AudioToolbox/AudioToolbox.h>

@interface ViewController ()<AVCaptureVideoDataOutputSampleBufferDelegate,H264HWEncodeDelegate,H264HWDeEncodeDelegate>
/**session*/
@property (nonatomic, strong) AVCaptureSession *mCaptureSession;
/**device input*/
@property (nonatomic, strong) AVCaptureDeviceInput *mCaptureDeviceInput;
/**data output*/
@property (nonatomic, strong) AVCaptureVideoDataOutput *mCaptureDeviceOutput;
/**预览图*/
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *mPreviewlayer;
/**硬编码*/
@property (nonatomic, strong) H264HWEncode *encode;
/**硬解码*/
@property (nonatomic, strong) H264HWDecode *deEncode;
@property (nonatomic , strong) AAPLEAGLLayer *playLayer;
@end

@implementation ViewController{
    dispatch_queue_t mCaptureQueue;
    NSFileHandle *fileHanle;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Do any additional setup after loading the view, typically from a nib.
    UIButton *button = [[UIButton alloc]initWithFrame:CGRectMake(0, 10, 100, 44)];
    [button setTitle:@"play" forState:UIControlStateNormal];
    [button setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
    [self.view addSubview:button];
    [button addTarget:self action:@selector(onClick:) forControlEvents:UIControlEventTouchUpInside];
    
    [self playLayer];
}
- (void)onClick:(UIButton *)btn{
    if (!self.mCaptureSession||!self.mCaptureSession.running) {
        [btn setTitle:@"stop" forState:UIControlStateNormal];
        [self startCapture];
    }else{
        [btn setTitle:@"play" forState:UIControlStateNormal];
        [self stopCapture];
    }
}
- (void)startCapture{

    self.mCaptureSession = [[AVCaptureSession alloc]init];
    self.mCaptureSession.sessionPreset = AVCaptureSessionPreset640x480;

    mCaptureQueue = dispatch_get_global_queue(0, 0);

    AVCaptureDevice *inputCamera = nil;
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for (AVCaptureDevice *device in devices) {
        if ([device position] == AVCaptureDevicePositionBack) {
            inputCamera = device;
        }
    }
    self.mCaptureDeviceInput = [[AVCaptureDeviceInput alloc]initWithDevice:inputCamera error:nil];

    if ([self.mCaptureSession canAddInput:self.mCaptureDeviceInput]) {
        [self.mCaptureSession addInput:self.mCaptureDeviceInput];
    }
    self.mCaptureDeviceOutput = [[AVCaptureVideoDataOutput alloc]init];
    //不丢弃延迟的帧
    self.mCaptureDeviceOutput.alwaysDiscardsLateVideoFrames = NO;

    [self.mCaptureDeviceOutput setVideoSettings:@{(NSString *)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)}];

    [self.mCaptureDeviceOutput setSampleBufferDelegate:self queue:mCaptureQueue];

    if ([self.mCaptureSession canAddOutput:self.mCaptureDeviceOutput]) {
        [self.mCaptureSession addOutput:self.mCaptureDeviceOutput];
    }

    AVCaptureConnection * connection = [self.mCaptureDeviceOutput connectionWithMediaType:AVMediaTypeVideo];
    [connection setVideoOrientation:AVCaptureVideoOrientationPortrait];

    NSString *file = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent:@"adc.h264"];
    [[NSFileManager defaultManager]removeItemAtPath:file error:nil];
    [[NSFileManager defaultManager]createFileAtPath:file contents:nil attributes:nil];
    fileHanle = [NSFileHandle fileHandleForWritingAtPath:file];
    
    self.encode = [[H264HWEncode alloc]init];
    
    self.encode.delegate = self;
    
    self.encode.frameInterval = 2.0;
    
    [self.mCaptureSession startRunning];

}
////停止捕获
- (void)stopCapture{
    [self.mCaptureSession stopRunning];
    [self.mPreviewlayer removeFromSuperlayer];
    [self.encode endVideoToolBox];
    [self.deEncode endVideoToolBox];
    [fileHanle closeFile];
    fileHanle = NULL;
}
#pragma mark - H264HWEncodeDelegate
- (void)getSpsPps:(NSData *)sps pps:(NSData *)pps byteHeader:(NSData *)byteHeader{
    //每个nalu 的内容是确定的  分隔+sps+分隔+pps+分隔+data

    NSMutableData *h264Data = [[NSMutableData alloc] init];
    [h264Data appendData:byteHeader];
    [h264Data appendData:sps];
    //写入数据
    [fileHanle writeData:h264Data];
    [self.deEncode decodeNalu:h264Data];
    
    h264Data = [[NSMutableData alloc] init];
    [h264Data appendData:byteHeader];
    [h264Data appendData:pps];
    [fileHanle writeData:h264Data];
    [self.deEncode decodeNalu:h264Data];

}
- (void)gotEncodedData:(NSData *)data byteHeader:(NSData *)byteHeader isKeyFrame:(BOOL)isKeyFrame{
    NSMutableData *h264Data = [[NSMutableData alloc] init];
    [h264Data appendData:byteHeader];
    [h264Data appendData:data];
    [fileHanle writeData:h264Data];
    [self.deEncode decodeNalu:h264Data];
}
#pragma mark - H264HWDeEncodeDelegate
- (void)displayDecodedFrame:(CVImageBufferRef )imageBuffer{
    self.playLayer.pixelBuffer = imageBuffer;
}
#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection{
    [self.encode encode:sampleBuffer];
}
#pragma mark - 懒加载
- (H264HWDecode *)deEncode {
    if (!_deEncode) {
        
        _deEncode = [[H264HWDecode alloc]init];
        self.deEncode.delegate = self;
    }
    return _deEncode;
}
- (AAPLEAGLLayer *)playLayer{
    if (!_playLayer) {
        _playLayer = [[AAPLEAGLLayer alloc] initWithFrame:CGRectMake(0, 50, UIScreen.mainScreen.bounds.size.width, UIScreen.mainScreen.bounds.size.height)];
        _playLayer.backgroundColor = [UIColor blackColor].CGColor;
        [self.view.layer addSublayer:_playLayer];
    }
    return _playLayer;
}
@end
