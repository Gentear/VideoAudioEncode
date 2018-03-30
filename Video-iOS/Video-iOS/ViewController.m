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
#import "AACEncode.h"
#import "AAPLEAGLLayer.h"
#import <AVFoundation/AVFoundation.h>
#import <VideoToolbox/VideoToolbox.h>
#import <AudioToolbox/AudioToolbox.h>

@interface ViewController ()<AVCaptureVideoDataOutputSampleBufferDelegate,AVCaptureAudioDataOutputSampleBufferDelegate,H264HWEncodeDelegate,H264HWDeEncodeDelegate,AACEncodeDelegate>
/**session*/
@property (nonatomic, strong) AVCaptureSession *mCaptureSession;
/**device input*/
@property (nonatomic, strong) AVCaptureDeviceInput *mCaptureDeviceInput;
/**data output*/
@property (nonatomic, strong) AVCaptureVideoDataOutput *mCaptureDeviceOutput;
/**预览图*/
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *mPreviewlayer;
/**硬编码*/
@property (nonatomic, strong) H264HWEncode *videoEncode;
/**硬解码*/
@property (nonatomic, strong) H264HWDecode *videoDeEncode;
/**音频编码*/
@property (nonatomic, strong) AACEncode *audioEncode;

@property (nonatomic , strong) AAPLEAGLLayer *playLayer;
/**<#desc#>*/
@property (nonatomic, strong) NSFileHandle *fileHanle;
@property (nonatomic, strong) NSFileHandle *audiofileHanle; ;
@end

@implementation ViewController{
    dispatch_queue_t mCaptureQueue;
 
}
- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Do any additional setup after loading the view, typically from a nib.
    UIButton *button = [[UIButton alloc]initWithFrame:CGRectMake(0, 0, UIScreen.mainScreen.bounds.size.width, 64)];
    [button setTitle:@"play" forState:UIControlStateNormal];
    [button setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
    [button addTarget:self action:@selector(onClick:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:button];

}
- (void)onClick:(UIButton *)btn{
    if (!self.mCaptureSession||!self.mCaptureSession.running) {
        [btn setTitle:@"stop" forState:UIControlStateNormal];
        [self playLayer];
        [self.view bringSubviewToFront:btn];
        [self startCapture];
    }else{
        [btn setTitle:@"play" forState:UIControlStateNormal];
        [self stopCapture];
    }
}
- (void)startCapture{

    self.mCaptureSession = [[AVCaptureSession alloc]init];
    self.mCaptureSession.sessionPreset = AVCaptureSessionPreset640x480;

    mCaptureQueue =  dispatch_get_global_queue(0, 0);

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

    NSArray *audioDevices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeAudio];
    AVCaptureDevice *audioDevice = audioDevices.lastObject;

    NSError * error;

    AVCaptureDeviceInput * deviceInput = [AVCaptureDeviceInput deviceInputWithDevice:audioDevice error:&error];

    AVCaptureAudioDataOutput *audioOutput = [[AVCaptureAudioDataOutput alloc]init];

    if ([self.mCaptureSession canAddInput:deviceInput]) {
        [self.mCaptureSession addInput:deviceInput];
    }
    if ([self.mCaptureSession canAddOutput:audioOutput]) {
        [self.mCaptureSession addOutput:audioOutput];
    }
    dispatch_queue_t outQueue = dispatch_queue_create("Audio Output Queue", DISPATCH_QUEUE_SERIAL);
    
    [audioOutput setSampleBufferDelegate:self queue:outQueue];
    
    
    AVCaptureConnection * connection = [self.mCaptureDeviceOutput connectionWithMediaType:AVMediaTypeVideo];
    [connection setVideoOrientation:AVCaptureVideoOrientationPortrait];
    [self videoEncode];

    [self fileHanle];
    
    [self audiofileHanle];
    
    [self.mCaptureSession startRunning];

}
////停止捕获
- (void)stopCapture{
    [self.mCaptureSession stopRunning];
    [self.playLayer removeFromSuperlayer];
    [self.fileHanle closeFile];
    [self.audiofileHanle closeFile];
    _playLayer = nil;
    _fileHanle = nil;
    _audiofileHanle = nil;
}
#pragma mark - H264HWEncodeDelegate
- (void)getSpsPps:(NSData *)sps pps:(NSData *)pps byteHeader:(NSData *)byteHeader{
    //每个nalu 的内容是确定的  分隔+sps+分隔+pps+分隔+data

    NSMutableData *h264Data = [[NSMutableData alloc] init];
    [h264Data appendData:byteHeader];
    [h264Data appendData:sps];
    //写入数据
    [self.fileHanle writeData:h264Data];
    [self.videoDeEncode decodeNalu:h264Data];
    
    h264Data = [[NSMutableData alloc] init];
    [h264Data appendData:byteHeader];
    [h264Data appendData:pps];
    [self.fileHanle writeData:h264Data];
    [self.videoDeEncode decodeNalu:h264Data];

}
- (void)gotEncodedData:(NSData *)data byteHeader:(NSData *)byteHeader isKeyFrame:(BOOL)isKeyFrame{
    NSMutableData *h264Data = [[NSMutableData alloc] init];
    [h264Data appendData:byteHeader];
    [h264Data appendData:data];
    [self.fileHanle writeData:h264Data];
    [self.videoDeEncode decodeNalu:h264Data];
}
#pragma mark - H264HWDeEncodeDelegate
- (void)displayDecodedFrame:(CVImageBufferRef )imageBuffer{
    self.playLayer.pixelBuffer = imageBuffer;
}
#pragma mark - AACEncodeDelegate
- (void)AACCallBackData:(NSData *)audioData{
    NSLog(@"%@",audioData);
    [self.audiofileHanle writeData:audioData];
}
#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection{
    if (output == self.mCaptureDeviceOutput) {
        [self.videoEncode encode:sampleBuffer];
    }else{
        [self.audioEncode encodeSampleBuffer:sampleBuffer];
    }
}
#pragma mark - 懒加载
- (H264HWEncode *)videoEncode{
    if (!_videoEncode) {
        _videoEncode = [[H264HWEncode alloc]init];
        
        _videoEncode.delegate = self;
        
        _videoEncode.frameInterval = 2.0;
    }
    return _videoEncode;
}
- (H264HWDecode *)videoDeEncode {
    if (!_videoDeEncode) {
        
        _videoDeEncode = [[H264HWDecode alloc]init];
        _videoDeEncode.delegate = self;
    }
    return _videoDeEncode;
}
- (AAPLEAGLLayer *)playLayer{
    if (!_playLayer) {
        _playLayer = [[AAPLEAGLLayer alloc] initWithFrame:CGRectMake(0, 0, UIScreen.mainScreen.bounds.size.width, UIScreen.mainScreen.bounds.size.height)];
        _playLayer.backgroundColor = [UIColor clearColor].CGColor;
        [self.view.layer addSublayer:_playLayer];
    }
    return _playLayer;
}
- (AACEncode *)audioEncode{
    if (!_audioEncode) {
        _audioEncode = [[AACEncode alloc]init];
        _audioEncode.delegate = self;
    }
    return _audioEncode;
}
- (NSFileHandle *)fileHanle{
    if (!_fileHanle) {
        NSString *file = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent:@"adc.h264"];
        [[NSFileManager defaultManager]removeItemAtPath:file error:nil];
        [[NSFileManager defaultManager]createFileAtPath:file contents:nil attributes:nil];
        _fileHanle = [NSFileHandle fileHandleForWritingAtPath:file];
    }
    return _fileHanle;
}
- (NSFileHandle *)audiofileHanle{
    if (!_audiofileHanle) {
        NSString *file = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent:@"aaa.aac"];
        [[NSFileManager defaultManager]removeItemAtPath:file error:nil];
        [[NSFileManager defaultManager]createFileAtPath:file contents:nil attributes:nil];
        _audiofileHanle = [NSFileHandle fileHandleForWritingAtPath:file];
    }
    return _audiofileHanle;
}
@end
