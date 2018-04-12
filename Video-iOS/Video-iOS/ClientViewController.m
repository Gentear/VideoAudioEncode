//
//  ClientViewController.m
//  Video-iOS
//
//  Created by zyyt on 2018/4/9.
//  Copyright © 2018年 Gentear. All rights reserved.
//

#import "ClientViewController.h"
#import "H264HWEncode.h"
#import "TCPSocketDefine.h"
#import "AACEncode.h"
#import <AVFoundation/AVFoundation.h>
#import <CocoaAsyncSocket/GCDAsyncSocket.h>
#import "EncodeHeader.h"

@interface ClientViewController ()<GCDAsyncSocketDelegate,AVCaptureVideoDataOutputSampleBufferDelegate,AVCaptureAudioDataOutputSampleBufferDelegate,H264HWEncodeDelegate,AACEncodeDelegate>
@property (weak, nonatomic) IBOutlet UITextField *addressTf;
// 计时器
@property (nonatomic, strong) NSTimer *connectTimer;
/**<#desc#>*/
@property (nonatomic, strong) GCDAsyncSocket *serverSocket;
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
/**音频编码*/
@property (nonatomic, strong) AACEncode *audioEncode;
@end

@implementation ClientViewController{
    dispatch_queue_t mCaptureQueue;
    HJ_VideoDataContent dataContent;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view from its nib.
    [self createDataContent];
    [self serverSocket];
    [self startCapture];
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
            break;
        }
    }
    if (!inputCamera) {
        return;
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
    
    
    [self.mCaptureSession startRunning];
    
}
/**数据打包*/
- (void)sendData:(NSData *)data{
    // 打包成一个结构体
   
    dataContent.videoLength = (unsigned int)[data length];
    
    NSMutableData * h264Data = [NSMutableData dataWithBytes:&dataContent   length:sizeof(dataContent)];
    [h264Data appendData:data];
    [self.serverSocket writeData:h264Data withTimeout:-1 tag:0];
}
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    [self.view endEditing:YES];
}

// 信息展示
- (void)showMessageWithStr:(NSString *)str{
    NSLog(@"*****%@******",str);
}
- (void)dealloc{
    [self showMessageWithStr:@"断开连接"];
    _serverSocket.delegate = nil;
    [_serverSocket disconnect];
    _serverSocket = nil;
    [self.connectTimer invalidate];
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
- (AACEncode *)audioEncode{
    if (!_audioEncode) {
        _audioEncode = [[AACEncode alloc]init];
        _audioEncode.delegate = self;
    }
    return _audioEncode;
}
- (GCDAsyncSocket *)serverSocket {
    if (!_serverSocket) {
        _serverSocket = [[GCDAsyncSocket alloc]initWithDelegate:self delegateQueue:dispatch_get_main_queue()];
        //开启端口
        NSError *error;
        BOOL result = [_serverSocket connectToHost:self.addressTf.text onPort:9999 error:&error];
        
        if (!result) {
            NSLog(@"客户端连接失败---%@",error);
        }
    }
    return _serverSocket;
}
- (void)createDataContent{
//    malloc(sizeof(dataContent));
    dataContent.msgHeader.controlMask = CODECONTROLL_VIDEOTRANS_REPLY;
    dataContent.msgHeader.protocolHeader[0] = 'H';
    dataContent.msgHeader.protocolHeader[1] = 'M';
    dataContent.msgHeader.protocolHeader[2] = '_';
    dataContent.msgHeader.protocolHeader[3] = 'D';
}
#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection{
    if (output == self.mCaptureDeviceOutput) {
        dispatch_sync(mCaptureQueue, ^{
            [self.videoEncode encode:sampleBuffer];
        });
    }else{
        //        dispatch_sync(mCaptureQueue, ^{
        //            [self.audioEncode encodeSampleBuffer:sampleBuffer];
        //        });
    }
}

#pragma mark - GCDAsyncSocketDelegate
/**连接主机对应端口号*/
- (void)socket:(GCDAsyncSocket *)sock didConnectToHost:(NSString *)host port:(uint16_t)port {
    [self showMessageWithStr:[NSString stringWithFormat:@"服务器IP: %@-------端口: %d", host,port]];
}
/**读取数据*/
- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag{
   
}
/**客户端socket断开*/
- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)err{
    [self showMessageWithStr:@"断开连接"];
    self.serverSocket.delegate = nil;
    [self.serverSocket disconnect];
    self.serverSocket = nil;
    [self.connectTimer invalidate];

}
#pragma mark - H264HWEncodeDelegate
- (void)getSpsPps:(NSData *)sps pps:(NSData *)pps byteHeader:(NSData *)byteHeader{
    //每个nalu 的内容是确定的  分隔+sps+分隔+pps+分隔+data
    NSMutableData *h264Data = [[NSMutableData alloc] init];
    [h264Data appendData:byteHeader];
    [h264Data appendData:sps];
    [self sendData:h264Data];
    
    h264Data = [[NSMutableData alloc] init];
    [h264Data appendData:byteHeader];
    [h264Data appendData:pps];
    [self sendData:h264Data];
}
- (void)gotEncodedData:(NSData *)data byteHeader:(NSData *)byteHeader isKeyFrame:(BOOL)isKeyFrame{
    NSMutableData *h264Data = [[NSMutableData alloc] init];
    [h264Data appendData:byteHeader];
    [h264Data appendData:data];
    [self sendData:h264Data];
}
@end
