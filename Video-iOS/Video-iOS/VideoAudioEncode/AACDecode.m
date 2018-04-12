//
//  AACDecode.m
//  Video-iOS
//
//  Created by zyyt on 2018/3/30.
//  Copyright © 2018年 Gentear. All rights reserved.
//

#import "AACDecode.h"
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import "EncodeHeader.h"

@interface AACDecode()
{
    AudioFileStreamID audioFileStream;
    NSInteger readPacketIndex;
    AudioStreamBasicDescription audioStreamDescription;
    AudioQueueRef audioQueue;
}
/**<#desc#>*/
@property (nonatomic, strong) NSMutableArray *dataArray;
@end

@implementation AACDecode

- (instancetype)init{
    if (self = [super init]) {
        
        //默认扬声器播放
        [[AVAudioSession sharedInstance]setCategory:AVAudioSessionCategoryPlayback error:nil];
        [[AVAudioSession sharedInstance]setActive:YES error:nil];
        //开启红外感应
//        [[UIDevice currentDevice]setProximityMonitoringEnabled:YES];
        //添加监听
//        [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(sensorStateChange:) name:@"UIDeviceProximityStateDidChangeNotification" object:nil];
        //设置代理方法
        AudioFileStreamOpen((__bridge void *)self, audioFileStreamProprtyListenerProc, audioFileStreamPacketsProc, 0, &audioFileStream);
        
        //网络测试
//        NSURLSession *session  =  [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration] delegate:self delegateQueue:nil];
//        NSString *mp3String = @"http://baxiang.qiniudn.com/chengdu.mp3";// mp3文件
//        NSURLSessionDataTask * task =  [session dataTaskWithURL:[NSURL URLWithString:mp3String]];
//        [task resume];
    }
    return self;
}
//- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data{
//    AudioFileStreamParseBytes(audioFileStream, (UInt32)data.length, data.bytes, 0);
//}
- (void)encodeAudio:(NSData *)data{
    AudioFileStreamParseBytes(audioFileStream, (UInt32)data.length, data.bytes, 0);
}
-(void)sensorStateChange:(NSNotificationCenter *)notification;{
    //如果此时手机靠近面部放在耳朵旁，那么声音将通过听筒输出，并将屏幕变暗（省电啊）
    if ([[UIDevice currentDevice] proximityState] == YES){
        NSLog(@"Device is close to user");
        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayAndRecord error:nil];
    }else{
        NSLog(@"Device is not close to user");
        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
    }
}

void audioFileStreamProprtyListenerProc(void *inClientData,AudioFileStreamID inAudioFileStream,AudioFileStreamPropertyID inPropertyID,AudioFileStreamPropertyFlags * ioFlags){
    
    AACDecode *decode = (__bridge AACDecode *)inClientData;
    [decode audioFileStreamPropertyListenerProcInAudioFileStream:inAudioFileStream inPropertyID:inPropertyID ioFlags:ioFlags];
}
- (void)audioFileStreamPropertyListenerProcInAudioFileStream:(AudioFileStreamID)inAudioFileStream inPropertyID:(AudioFilePropertyID)inPropertyID ioFlags:(AudioFileStreamPropertyFlags *)ioFlages{
    if (inPropertyID == kAudioFileStreamProperty_DataFormat) {
        UInt32 outDataSize = sizeof(AudioStreamBasicDescription);
        AudioFileStreamGetProperty(inAudioFileStream, inPropertyID, &outDataSize, &audioStreamDescription);
        [self createAudioQueueWithAudioStreamDescription];
    }
}
- (void)createAudioQueueWithAudioStreamDescription{
    //创建输出队列
    OSStatus status = AudioQueueNewOutput(&audioStreamDescription,audioQueueOutputCallback, (__bridge void *)self, NULL, kCFRunLoopCommonModes, 0, &audioQueue);
    assert(status == noErr);
    //设置参数
    status = AudioQueueSetParameter(audioQueue, kAudioQueueParam_Volume, 1.0);
    assert(status == noErr);
}
void audioQueueOutputCallback(void * inUserData,AudioQueueRef inAQ,AudioQueueBufferRef inBuffer){
    
    OSStatus status = AudioQueueFreeBuffer(inAQ, inBuffer);
    assert(status == noErr);
    
    AACDecode * decode = (__bridge AACDecode *)inUserData;
    
    [decode enqueueDataWithPacketsCount:(int)([decode packetSperSecond] * 2)];
    
}
void audioFileStreamPacketsProc(void * inClientData,UInt32 inNumberBytes,UInt32 inNumberPackets,const void *                    inInputData,AudioStreamPacketDescription *inPacketDescriptions){
    
    AACDecode * decode = (__bridge AACDecode *)inClientData;
    [decode storePacketsWithNumberOfBytes:inNumberBytes numberOfPackets:inNumberPackets inputData:inInputData packetDescriptions:inPacketDescriptions];
}
- (void)storePacketsWithNumberOfBytes:(UInt32)inNumberBytes numberOfPackets:(UInt32)inNumberPackets inputData:(const void *)inInputData packetDescriptions:(AudioStreamPacketDescription *)inPacketDescriptions{
    
    if (inPacketDescriptions) {
        for (int i = 0; i < inNumberPackets; i++) {
            SInt64 packetStart = inPacketDescriptions[i].mStartOffset;
            UInt32 packetSize = inPacketDescriptions[i].mDataByteSize;
            NSData *packet = [NSData dataWithBytes:inInputData + packetStart length:packetSize];
            [self.dataArray addObject:packet];
        }
    }else{
        UInt32 packetSize = inNumberBytes/inNumberPackets;
        for (int i = 0; i < inNumberPackets; i ++) {
            NSData *packet = [NSData dataWithBytes:inInputData + packetSize*(i+1) length:packetSize];
            [self.dataArray addObject:packet];
        }
    }
    
    if (readPacketIndex == 0 && self.dataArray.count > (int)([self packetSperSecond]*2)){
        OSStatus status = AudioQueueStart(audioQueue, NULL);
        assert(status == noErr);
        [self enqueueDataWithPacketsCount:(int)([self packetSperSecond] * 2)];
    }
    
}
- (UInt32)packetSperSecond{
    return audioStreamDescription.mSampleRate / audioStreamDescription.mFramesPerPacket;
}
- (void)enqueueDataWithPacketsCount:(size_t)inPacketCount{
    if (!audioQueue) {
        return;
    }
    if (readPacketIndex + inPacketCount >= self.dataArray.count) {
        inPacketCount = self.dataArray.count - readPacketIndex;
    }
    if (inPacketCount <= 0) {
        AudioQueueStop(audioQueue, false);
        AudioFileStreamClose(audioFileStream);
        return;
    }
    UInt32 totalSize = 0;
    for (UInt32 index = 0; index < inPacketCount; index ++) {
        NSData * data = [self.dataArray objectAtIndex:index + readPacketIndex];
        totalSize += data.length;
    }
    
    OSStatus status = 0;
    AudioQueueBufferRef outBuffer;
    status = AudioQueueAllocateBuffer(audioQueue, totalSize, &outBuffer);
    assert(status == noErr);
    
    outBuffer->mAudioDataByteSize = totalSize;
    outBuffer->mUserData = (__bridge void *)self;
    AudioStreamPacketDescription *inpacketDescriptions = calloc(inPacketCount, sizeof(AudioStreamPacketDescription));
    UInt32 startOffset = 0;
    for (int i = 0; i < inPacketCount; i ++) {
        
        NSData *data = [self.dataArray objectAtIndex:i + readPacketIndex];
        memcpy(outBuffer->mAudioData + startOffset, [data bytes], [data length]);
        AudioStreamPacketDescription packetDescriptions;
        packetDescriptions.mDataByteSize = (UInt32)data.length;
        packetDescriptions.mStartOffset = startOffset;
        packetDescriptions.mVariableFramesInPacket = 0;
        startOffset += data.length;
        memcpy(&inpacketDescriptions[i], &packetDescriptions, sizeof(AudioStreamPacketDescription));
    }
    status = AudioQueueEnqueueBuffer(audioQueue, outBuffer, (UInt32)inPacketCount, inpacketDescriptions);
    assert(status == noErr);
    free(inpacketDescriptions);
    readPacketIndex += inPacketCount;
    
}
- (void)dealloc{
    [[UIDevice currentDevice]setProximityMonitoringEnabled:NO];
}
#pragma mark - 懒加载
- (NSMutableArray *)dataArray {
    if (!_dataArray) {
        _dataArray = [NSMutableArray array];
    }
    return _dataArray;
}
@end






