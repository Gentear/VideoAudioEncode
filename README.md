# VideoAudioEncode

> 视频音频编解码，对VideoToolBox进行封装，屏蔽了底层C语言的API，通过OC的方式进行程序调用

## 使用方式


### 视频硬编码

```
1. 
//将VideoAudioEncode 文件夹中的内容拖入到工程中
2.
//创建encode编码器，并设置编码的参数
self.encode = [[H264HWEncode alloc]init];
self.encode.delegate = self;
self.encode.frameInterval = 2.0;

/**设置关键帧（GOPsize）间隔*/
@property (nonatomic, assign) int frameInterval;
/**设置期望帧率*/
@property (nonatomic, assign) int fps;
/**设置码率 均值  单位是byte*/
@property (nonatomic, assign) int bitRate;
/**设置码率 ， 上限  单位是bps*/
@property (nonatomic, assign) int bitRateLimit;

3.
在AVCaptureVideoDataOutputSampleBufferDelegate 回调中将sampleBuffer传入
[self.encode encode:sampleBuffer];

4.
在回调程序中获取到sps pps 及 I B/P帧数据
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

```

### 视频硬解码


```
1. 
//将VideoAudioEncode 文件夹中的内容拖入到工程中

2.
//创建解码器并设置代理
_deEncode = [[H264HWDecode alloc];
self.deEncode.delegate = self;

3.
//分别传入sps + pps + I B/P帧的数据
NSMutableData *h264Data = [[NSMutableData alloc] init];
[h264Data appendData:byteHeader];
[h264Data appendData:sps];
[self.deEncode decodeNalu:h264Data];
    
h264Data = [[NSMutableData alloc] init];
[h264Data appendData:byteHeader];
[h264Data appendData:pps];
[self.deEncode decodeNalu:h264Data];
    
NSMutableData *h264Data = [[NSMutableData alloc] init];
[h264Data appendData:byteHeader];
[h264Data appendData:data];
[self.deEncode decodeNalu:h264Data];

4.
//回调中传入CVImageBufferRef流 并将ImageBuffer传入到palyer中（内部已经对CVImageBufferRef进行释放，未来会使用CVPixelBufferPool进行优化）
- (void)displayDecodedFrame:(CVImageBufferRef )imageBuffer{
    self.playLayer.pixelBuffer = imageBuffer;
}
```

### 音频硬解码


```
1. 导入头文件
#import "AACEncode.h"

2. AVCaptureVideoDataOutputSampleBufferDelegate回调方法中进行编码
 [self.audioEncode encodeSampleBuffer:sampleBuffer];
 
 3.代理方法中获取data数据
 - (void)AACCallBackData:(NSData *)audioData{
    NSLog(@"%@",audioData);
    [self.audiofileHanle writeData:audioData];
}
```
