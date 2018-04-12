//
//  ServerViewController.m
//  Video-iOS
//
//  Created by zyyt on 2018/4/9.
//  Copyright © 2018年 Gentear. All rights reserved.
//

#import "ServerViewController.h"
#import <CocoaAsyncSocket/GCDAsyncSocket.h>
#import "TCPSocketDefine.h"
#import "H264HWDecode.h"
#import "AACDecode.h"
#import "AAPLEAGLLayer.h"
#import "EncodeHeader.h"

@interface ServerViewController ()<GCDAsyncSocketDelegate,H264HWDeEncodeDelegate>
/**<#desc#>*/
@property (nonatomic, strong) GCDAsyncSocket *serverSocket;
/**硬解码*/
@property (nonatomic, strong) H264HWDecode *videoDeEncode;
/**音频解码*/
@property (nonatomic, strong) AACDecode *audioDecode;
@property (nonatomic , strong) AAPLEAGLLayer *playLayer;
// 检测心跳计时器
@property (nonatomic, strong) NSTimer *checkTimer;
// 保存客户端socket
@property (nonatomic, strong) NSMutableArray *clientSockets;
/**<#desc#>*/
@property (nonatomic, strong) NSMutableData *tmpData;
/**<#desc#>*/
@property (nonatomic, strong) NSData *videoSpecData;
@end

@implementation ServerViewController
{
    HJ_VideoDataContent dataContent;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view from its nib.
    [self playLayer];
    [self videoDeEncode];
    [self serverSocket];
    
    
}
- (void)dealloc{
    free(&dataContent);
}
// 信息展示
- (void)showMessageWithStr:(NSString *)str{
    NSLog(@"********%@***********",str);
}
#pragma mark - H264HWDeEncodeDelegate
- (void)displayDecodedFrame:(CVImageBufferRef )imageBuffer{
    self.playLayer.pixelBuffer = imageBuffer;
}
#pragma mark - GCDAsyncSocketDelegate
// 连接上新的客户端socket
- (void)socket:(GCDAsyncSocket *)sock didAcceptNewSocket:(nonnull GCDAsyncSocket *)newSocket{
    // 保存客户端的socket
    [self.clientSockets addObject: newSocket];
    
    [self showMessageWithStr:@"链接成功"];
    [self showMessageWithStr:[NSString stringWithFormat:@"客户端的地址: %@ -------端口: %d", newSocket.connectedHost, newSocket.connectedPort]];
    
    [newSocket readDataWithTimeout:- 1 tag:0];
}

/**
 读取客户端的数据
 @param sock 客户端的Socket
 @param data 客户端发送的数据
 @param tag 当前读取的标记
 */
- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag{
    [self.tmpData appendData:data];
    [self didReadData];
    [sock readDataWithTimeout:- 1 tag:0];

}
- (void)didReadData{
    if (_tmpData.length <= 23) {
        return;
    }else{
        [[_tmpData subdataWithRange:NSMakeRange(0, 23)] getBytes: &dataContent length: sizeof(dataContent)];
        if (dataContent.videoLength < _tmpData.length - 23) {
            NSData * decodeData =  [_tmpData subdataWithRange:NSMakeRange(23, dataContent.videoLength)];
            [self.videoDeEncode decodeNalu:decodeData];
            NSData * remain = [_tmpData subdataWithRange:NSMakeRange(23+dataContent.videoLength, _tmpData.length - dataContent.videoLength - 23)];
            _tmpData = [NSMutableData dataWithData:remain];
            [self didReadData];
        }else if(dataContent.videoLength == _tmpData.length - 23){
            NSData * decodeData =  [_tmpData subdataWithRange:NSMakeRange(23, dataContent.videoLength)];
            [self.videoDeEncode decodeNalu:decodeData];
            _tmpData = [NSMutableData data];
            return;
        }
    }
}

#pragma mark - Lazy Load
- (NSMutableArray *)clientSockets
{
    if (_clientSockets == nil) {
        _clientSockets = [NSMutableArray array];
    }
    return _clientSockets;
}
- (GCDAsyncSocket *)serverSocket {
    if (!_serverSocket) {
        _serverSocket = [[GCDAsyncSocket alloc]initWithDelegate:self delegateQueue:dispatch_get_main_queue()];
        //开启端口
        NSError *error;
        BOOL result = [_serverSocket acceptOnPort:9999 error:&error];
        
        if (!result) {
            NSLog(@"端口开放失败---%@",error);
        }
    }
    return _serverSocket;
}
- (H264HWDecode *)videoDeEncode {
    if (!_videoDeEncode) {
        
        _videoDeEncode = [[H264HWDecode alloc]init];
        _videoDeEncode.delegate = self;
    }
    return _videoDeEncode;
}
- (AACDecode *)audioDecode{
    if (!_audioDecode) {
        AACDecode *decode = [[AACDecode alloc]init];
        _audioDecode = decode;
    }
    return _audioDecode;
}
- (AAPLEAGLLayer *)playLayer{
    if (!_playLayer) {
        _playLayer = [[AAPLEAGLLayer alloc] initWithFrame:CGRectMake(0, 0, UIScreen.mainScreen.bounds.size.width, UIScreen.mainScreen.bounds.size.height)];
        _playLayer.backgroundColor = [UIColor clearColor].CGColor;
        [self.view.layer addSublayer:_playLayer];
    }
    return _playLayer;
}
- (NSMutableData *)tmpData{
    if (!_tmpData) {
        _tmpData = [NSMutableData data];
    }
    return _tmpData;
}
#pragma mark - Private Method

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    [self.view endEditing:YES];
}
//}

@end
