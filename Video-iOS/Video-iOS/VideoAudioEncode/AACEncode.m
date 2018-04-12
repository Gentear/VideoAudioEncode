//
//  AACEncode.m
//  Video-iOS
//
//  Created by zyyt on 2018/3/29.
//  Copyright © 2018年 Gentear. All rights reserved.
//

#import "AACEncode.h"
#import <AudioToolbox/AudioToolbox.h>
#import "EncodeHeader.h"
@interface AACEncode()
/**音频转码器*/
@property (nonatomic) AudioConverterRef audioConverter;
@end

@implementation AACEncode
{
    dispatch_queue_t encodeQueue;
    dispatch_queue_t cellBackQueue;
    char *pcmBuffer;
    size_t pcmBufferSize;
    /**pcm转aac buffer 容器*/
    uint8_t *aacBuffer;
    NSUInteger aacBufferSize;
}
- (instancetype)init{
    if (self = [super init]) {
        encodeQueue = dispatch_queue_create("AAC Encoder Queue", DISPATCH_QUEUE_SERIAL);
        cellBackQueue = dispatch_queue_create("AAC CallBack Queue", DISPATCH_QUEUE_SERIAL);

        _audioConverter = NULL;
        pcmBufferSize = 0;
        pcmBuffer = NULL;
        aacBufferSize = 1024;
        aacBuffer = malloc(aacBufferSize * sizeof(uint8_t));
        memset(aacBuffer, 0, aacBufferSize);
    }
    return self;
}
- (void)encodeSampleBuffer:(CMSampleBufferRef)sampleBuffer{
    //这样就需要手动进行内存管理
    dispatch_async(encodeQueue, ^{
        if (!_audioConverter) {
            //配置编码参数
            [self initAudioEncoderFromSampleBuffer:sampleBuffer];
        }
        //获取samplebuffer数据
        CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
        
        //pcm
        OSStatus status = CMBlockBufferGetDataPointer(blockBuffer, 0, NULL, &pcmBufferSize , &pcmBuffer);
        NSError *error = nil;
        if (status != kCMBlockBufferNoErr) {
            error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
            NSLog(@"pcm error , %@",error);
            return ;
        }
        //AAC清空
        memset(aacBuffer, 0, aacBufferSize);
        
        //初始化缓存列表
        AudioBufferList outAudioBufferList = {0};
        //缓冲区个数
        outAudioBufferList.mNumberBuffers = 1;
        //数据通道
        outAudioBufferList.mBuffers[0].mNumberChannels = 1;
        //缓冲数据大小
        outAudioBufferList.mBuffers[0].mDataByteSize = (int)aacBufferSize;
        //缓冲区内容
        outAudioBufferList.mBuffers[0].mData = aacBuffer;
        
        //编码到缓存列表
        AudioStreamPacketDescription *outPacketDescription = NULL;
        UInt32  ioOutputDataPacketSize = 1;
        status = AudioConverterFillComplexBuffer(_audioConverter, inInputDataProc, (__bridge void *)self, &ioOutputDataPacketSize, &outAudioBufferList, outPacketDescription);
        
        
        if (status == noErr) {
            //编码成功的AAC数据
            NSData *rawAAC = [NSData dataWithBytes:outAudioBufferList.mBuffers[0].mData length:outAudioBufferList.mBuffers[0].mDataByteSize];
            //获取头文件
            NSData *adtsHeader = [self adtsDataForPacketLength:rawAAC.length];
            //整个data数据
            NSMutableData *fullData = [NSMutableData dataWithData:adtsHeader];
            [fullData appendData:rawAAC];
            dispatch_async(cellBackQueue, ^{
                if ([self.delegate respondsToSelector:@selector(AACCallBackData:)]) {
                    [self.delegate AACCallBackData:fullData];
                }
            });   
        }
//        CFRelease(blockBuffer);
        CFRelease(sampleBuffer);
    });
}
- (void)initAudioEncoderFromSampleBuffer:(CMSampleBufferRef)smapleBuffer{
    //获取原音频格式设置
    AudioStreamBasicDescription inAudioStreamBasicDecription = *CMAudioFormatDescriptionGetStreamBasicDescription((CMAudioFormatDescriptionRef)CMSampleBufferGetFormatDescription(smapleBuffer));
    //初始化输出流的结构体描述为0
    AudioStreamBasicDescription outAudioStreamBasicDescription = {0};
    //音频流，正常播放情况下的帧率。如果是压缩格式。这个属性表示为解压缩后的帧率。帧率不能为0
    outAudioStreamBasicDescription.mSampleRate = inAudioStreamBasicDecription.mSampleRate;
    //编码格式
    outAudioStreamBasicDescription.mFormatID = kAudioFormatMPEG4AAC;
    //无损编码 0表示没有
    outAudioStreamBasicDescription.mFormatFlags = kMPEG4Object_AAC_LC;
    //每一个packet的音频数据大小。如果动态大小，设置为0。动态大小的格式，需要用AudioStreamPacketDescription来确定每个packet的大小
    outAudioStreamBasicDescription.mBytesPerPacket = 0;
    //每个packet的帧数。如果未压缩的音频数据值是1  动态码率格式，这个值是一个较大的固定数字，比如AAC的1024
    outAudioStreamBasicDescription.mFramesPerPacket = 1024;
    outAudioStreamBasicDescription.mBytesPerFrame = 0;
    //声道数
    outAudioStreamBasicDescription.mChannelsPerFrame = 1;
    //压缩格式设置为0
    outAudioStreamBasicDescription.mBitsPerChannel = 0;
    //8字节对齐
    outAudioStreamBasicDescription.mReserved = 0;
    //软编 获取编码区
    AudioClassDescription *description = [self getAudioClassDescriptionWithType:kAudioFormatMPEG4AAC fromManuFacturer:kAppleSoftwareAudioCodecManufacturer];
    //创建音频转换器
    OSStatus status = AudioConverterNewSpecific(&inAudioStreamBasicDecription, &outAudioStreamBasicDescription, 1, description, &_audioConverter);
    NSAssert(status == noErr, [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil].localizedDescription);
}
/**
 * 解码器
 *  编解码器（codec）指的是一个能够对一个信号或者一个数据流进行变换的设备或者程序。这里指的变换既包括将 信号或者数据流进行编码（通常是为了传输、存储或者加密）或者提取得到一个编码流的操作，也包括为了观察或者处理从这个编码流中恢复适合观察或操作的形式的操作。编解码器经常用在视频会议和流媒体等应用中。
 */
- (AudioClassDescription *)getAudioClassDescriptionWithType:(UInt32)type fromManuFacturer:(UInt32)manufacturer{
    
    static AudioClassDescription desc;
    UInt32 encoderSpecifier = type;
    UInt32 size;
    
    OSStatus status = AudioFormatGetPropertyInfo(kAudioFormatProperty_Encoders, sizeof(encoderSpecifier), &encoderSpecifier, &size);
    
    NSAssert(status == noErr, [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil].localizedDescription);
    
    unsigned int count = size / sizeof(AudioClassDescription);
    
    AudioClassDescription descriptions[count];
    
    status = AudioFormatGetProperty(kAudioFormatProperty_Encoders, sizeof(encoderSpecifier), &encoderSpecifier, &size, descriptions);
    
    NSAssert(status == noErr, [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil].localizedDescription);
    
    for (unsigned int i = 0; i < count; i ++) {
        if ((type == descriptions[i].mSubType) && (manufacturer == descriptions[i].mManufacturer)) {
            memcpy(&desc, &(descriptions[i]), sizeof(desc));
            return  &desc;
        }
    }
    return nil;
    
}

/**模认添加头文件*/
- (NSData *)adtsDataForPacketLength:(NSUInteger)packetLength{
    int adtsLength = 7;
    char * packet = malloc(sizeof(char) * adtsLength);
    
    int proFile = 2;
    int freqIdx = 4;
    int chanCfg = 1;
    
    NSUInteger fullLength = adtsLength + packetLength;
    
    packet[0] = (char)0xFF; //32
    packet[1] = (char)0xF9; //25
    packet[2] = (char)(((proFile - 1) << 6) + (freqIdx << 2) + (chanCfg >> 2));
    packet[3] = (char)(((chanCfg & 3)<<6) + (fullLength >> 11));
    packet[4] = (char)((fullLength & 0x7FF) >> 3);
    packet[5] = (char)(((fullLength & 7) << 5) + 0x1F);
    packet[6] = (char)0xFC;
    
    NSData * data = [NSData dataWithBytesNoCopy:packet length:adtsLength freeWhenDone:YES];
    return data;
}

OSStatus inInputDataProc(AudioConverterRef inAudioConverter,UInt32 *ioNumberDataPackets,AudioBufferList *ioData,AudioStreamPacketDescription ** outDataPacketDescription,void * inUserData){
    //获取编码区
    AACEncode * encode = (__bridge AACEncode *)inUserData;
    //请求数据长度
    UInt32 requestedPackets = *ioNumberDataPackets;
    //pcm数据填充到缓冲区
    size_t copiedSamples = [encode copyPCMSamplesIntoBuffer:ioData];
    if (copiedSamples < requestedPackets) {
        //PCM 缓冲区还没满
        *ioNumberDataPackets = 0;
        return  -1;
    }
    *ioNumberDataPackets = 1;
    
    return noErr;
}
/**
 *  填充PCM到缓冲区
 */
- (size_t)copyPCMSamplesIntoBuffer:(AudioBufferList *)ioData{
    //获取pcm
    size_t originalBufferSize = pcmBufferSize;
    //没有数据返回
    if (!originalBufferSize) {
        return 0;
    }
    //aac缓存区填充pcm数据
    ioData->mBuffers[0].mData = pcmBuffer;
    ioData->mBuffers[0].mDataByteSize = (int)pcmBufferSize;
    //清空pcm
    pcmBuffer = NULL;
    pcmBufferSize = 0;
    return originalBufferSize;
}
- (void)dealloc {
    [self endAudioToolBox];
}
- (void)endAudioToolBox{
    AudioConverterDispose(_audioConverter);
    free(aacBuffer);
}
@end
