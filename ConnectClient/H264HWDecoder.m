//
//  H264HWDecoder.m
//  SmartToothbrush
//
//  Created by Acen on 16/3/12.
//  Copyright © 2016年 Acen Works. All rights reserved.
//
//  RTP: https://en.wikipedia.org/wiki/Real-time_Transport_Protocol

#import "H264HWDecoder.h"
#import "LiveStreamDebugHelper.h"

#define H264_PAYLOAD_TYPE     98

#define NALU_TYPE_SPS         7
#define NALU_TYPE_PPS         8
#define NALU_TYPE_IFRAME      5
#define NALU_TYPE_PFRAME      1

#define IS_START_CODE_BYTES(_d_, _i_) (_d_[_i_] == 0x00 && _d_[_i_+1] == 0x00 && _d_[_i_+2] == 0x00 && _d_[_i_+3] == 0x01)

struct rtp_header {
    u_int16_t v:2; /* protocol version */
    u_int16_t p:1; /* padding flag */
    u_int16_t x:1; /* header extension flag */
    u_int16_t cc:4; /* CSRC count */
    u_int16_t m:1; /* marker bit */
    u_int16_t pt:7; /* payload type */
    u_int16_t seq:16; /* sequence number */
    u_int32_t ts; /* timestamp */
    u_int32_t ssrc; /* synchronization source */
};

@interface H264HWDecoder()

@property (nonatomic, assign) CMVideoFormatDescriptionRef formatDesc;

@end

@implementation H264HWDecoder

- (void)decodeFromRawRTPPacket:(NSData *)data timestamp:(CMTime)timestamp
//- (void)decodeFromRawRTPPacket:(NSData *)data
{
    NSLog(@"Got Data %ld bytes", data.length);
    
    // 取得RTP头，通常12字节，根据协议可以从这部分获得总长度
    // 暂时忽略seq起到的丢包控制作用
    struct rtp_header header;
    [data getBytes:&header length:12];
    
    if (header.pt == H264_PAYLOAD_TYPE) {
        NSLog(@"RTP header %d, seq=%d", header.ts, header.seq);
        
        // value / timescale(1000000000) = seconds
        // value  = seconds * timescale = ts(ms) / 1000 * 1000000000 = ts * 1000000
        CMTimeValue value = (CMTimeValue)header.ts; // * 1000000;
        CMTimeScale scale = 1000;
        CMTime timestamp = CMTimeMake(value, scale);
        
        // 剩余部分为AVC协议部分
        uint8_t *rawFrames = (uint8_t *)data.bytes + 12;
        uint32_t frameSize = (uint32_t)(data.length - 12);
        [self decodeFromRawFrames:rawFrames withSize:frameSize timestamp:timestamp];
    } else {
        NSLog(@"not a legal h264 rtp packet");
    }
}

#pragma mark - Real Decode Part

- (void)decodeFromRawFrames:(uint8_t *)frame withSize:(uint32_t)frameSize timestamp:(CMTime)timestamp
{
    OSStatus status = -1;
    
    uint8_t *sps = NULL;
    uint8_t *pps = NULL;
    uint32_t spsSize = 0, ppsSize = 0;
    
    int theNaluIndex = [self findNextNALUFromRawFrames:frame size:frameSize withStartIndex:0];
    while (theNaluIndex >= 0) {
        
        // 搜索下一个NALU位置，获得当前NALU的大小
        int nextNaluIndex = [self findNextNALUFromRawFrames:frame size:frameSize withStartIndex:theNaluIndex + 4];
        int naluType = (frame[theNaluIndex + 4] & 0x1F);
        uint32_t naluSize = (nextNaluIndex < 0 ? frameSize : nextNaluIndex) - theNaluIndex - 4; // 不含头
        [LiveStreamDebugHelper translateNALUType:naluType size:naluSize];
        
        // 根据类型处理
        if (naluType == NALU_TYPE_SPS) {
            sps = malloc(naluSize);
            spsSize = naluSize;
            memcpy(sps, &frame[theNaluIndex+4], naluSize);
            
        } else if (naluType == NALU_TYPE_PPS) {
            pps = malloc(naluSize);
            ppsSize = naluSize;
            memcpy(pps, &frame[theNaluIndex+4], naluSize);
            
            // 拿到PPS后可以获得FormatDescription
            if (sps != NULL && pps != NULL) {
                uint8_t* parameterSetPointers[2] = {sps, pps};
                size_t parameterSetSizes[2] = {spsSize, ppsSize};
                
                status = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault, 2,
                                                                             (const uint8_t *const*)parameterSetPointers,
                                                                             parameterSetSizes, 4,
                                                                             &_formatDesc);
//                NSLog(@"\t\t Creation of CMVideoFormatDescription: %@", (status == noErr) ? @"successful!" : @"failed...");
            }
            
            // 拿到pps后，不管有没有sps都释放掉
            if (sps != NULL) {
                free(sps);
                sps = NULL;
            }
            if (pps != NULL) {
                free(pps);
                pps = NULL;
            }
            
            // 创建失败，直接跳过这个packet
            if (status != noErr) {
                NSLog(@"\t\t Format Description ERROR type: %d", (int)status);
                break;
            }
            
        } else if (naluType == NALU_TYPE_PFRAME || naluType == NALU_TYPE_IFRAME) {
            
            // 复制数据
            uint8_t *data = NULL;
            size_t blockLength = naluSize + 4;
            data = malloc(blockLength); // 4字节长度
            data = memcpy(data, &frame[theNaluIndex], blockLength);
            
            uint32_t dataLength32 = htonl(naluSize);
            memcpy(data, &dataLength32, sizeof(uint32_t));
            
            // 创建CMBlockBuffer
            CMBlockBufferRef blockBuffer = NULL;
            status = CMBlockBufferCreateWithMemoryBlock(NULL, data,  // memoryBlock to hold buffered data
                                                        blockLength,  // block length of the mem block in bytes.
                                                        kCFAllocatorNull, NULL,
                                                        0, // offsetToData
                                                        blockLength,   // dataLength of relevant bytes, starting at offsetToData
                                                        0, &blockBuffer);
//            NSLog(@"\t\t BlockBufferCreation: \t %@", (status == kCMBlockBufferNoErr) ? @"successful!" : @"failed...");
            
            // 创建CMSampleBuffer
            if (status == noErr) {
                CMSampleTimingInfo timingInfo;
                timingInfo.duration = kCMTimeInvalid;
                timingInfo.presentationTimeStamp = timestamp;
                timingInfo.decodeTimeStamp = kCMTimeInvalid;
                
                CMSampleBufferRef sampleBuffer = NULL;
                const size_t sampleSize = blockLength;
                status = CMSampleBufferCreate(kCFAllocatorDefault,
                                              blockBuffer, true, NULL, NULL,
                                              _formatDesc, 1, 1, &timingInfo, 1,
                                              &sampleSize, &sampleBuffer);
//                NSLog(@"\t\t SampleBufferCreate: \t %@", (status == noErr) ? @"successful!" : @"failed...");
                
                if (status == noErr) {
                    [self render:sampleBuffer];
                }
            }
            
            // 释放内存
            if (NULL != data) {
                free(data);
                data = NULL;
            }
        } else {
            // 忽略其他类型的NALU
        }
        
        theNaluIndex = nextNaluIndex;
    }
}

- (int)findNextNALUFromRawFrames:(uint8_t *)frame size:(uint32_t)dataSize withStartIndex:(int)startIndex
{
    for (int i=startIndex; i<dataSize; i++) {
        if (IS_START_CODE_BYTES(frame, i)) {
            return i;
        }
    }
    
    return -1;
}

- (void)render:(CMSampleBufferRef)sampleBuffer
{
    [self.delegate displaySampleBuffer:sampleBuffer formatDescription:self.formatDesc];
}

@end
