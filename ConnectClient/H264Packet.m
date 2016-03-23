//
//  H264Packet.m
//  ConnectClient
//
//  Created by Acen on 16/3/12.
//  Copyright © 2016年 Peergine. All rights reserved.
//

#import "H264Packet.h"
#import "LiveStreamDebugHelper.h"

@implementation H264Packet

- (id)initWithCMSampleBuffer:(CMSampleBufferRef)sample
{
    self = [super init];
    if(self)
    {
        [self packetizeAVC:sample];
    }
    return self;
}

- (void)packetizeAVC:(CMSampleBufferRef)sample
{
    self.packet = [NSMutableData data];
    
    NSData *sps = NULL, *pps = NULL;
    
    CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sample);
    // CFDictionaryRef extensionDict = CMFormatDescriptionGetExtensions(format);
    // Get the extensions
    // From the extensions get the dictionary with key "SampleDescriptionExtensionAtoms"
    // From the dict, get the value for the key "avcC"
    
    size_t sparameterSetSize, sparameterSetCount;
    const uint8_t *sparameterSet;
    OSStatus statusCode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 0, &sparameterSet, &sparameterSetSize, &sparameterSetCount, 0 );
    if (statusCode == noErr)
    {
        // Found sps and now check for pps
        size_t pparameterSetSize, pparameterSetCount;
        const uint8_t *pparameterSet;
        OSStatus statusCode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 1, &pparameterSet, &pparameterSetSize, &pparameterSetCount, 0 );
        if (statusCode == noErr)
        {
            // Found pps
            sps = [NSData dataWithBytes:sparameterSet length:sparameterSetSize];
            pps = [NSData dataWithBytes:pparameterSet length:pparameterSetSize];
            
            const char bytes[] = "\x00\x00\x00\x01"; // SPS PPS Header
            size_t length = (sizeof bytes) - 1; //string literals have implicit trailing '\0'
            NSData *byteHeader = [NSData dataWithBytes:bytes length:length];
            NSMutableData *fullSPSData = [NSMutableData dataWithData:byteHeader];
            NSMutableData *fullPPSData = [NSMutableData dataWithData:byteHeader];
            
            [fullSPSData appendData:sps];
            [fullPPSData appendData:pps];
            
            sps = fullSPSData;
            pps = fullPPSData;
        }
    }
    
    // 每个packet只放置一个sps，pps
    [self.packet appendData:sps];
    [self.packet appendData:pps];
    
    // 增加其他
    CMBlockBufferRef dataBuffer = CMSampleBufferGetDataBuffer(sample);
    size_t length, totalLength;
    char *dataPointer;
    OSStatus statusCodeRet = CMBlockBufferGetDataPointer(dataBuffer, 0, &length, &totalLength, &dataPointer);
    if (statusCodeRet == noErr) {
        
        size_t bufferOffset = 0;
        static const int AVCCHeaderLength = 4;
        while (bufferOffset < totalLength - AVCCHeaderLength) {
            // Read the NAL unit length
            uint32_t NALUnitLength = 0;
            memcpy(&NALUnitLength, dataPointer + bufferOffset, AVCCHeaderLength);
            
            // Convert the length value from Big-endian to Little-endian
            NALUnitLength = CFSwapInt32BigToHost(NALUnitLength);
            
//            NSLog(@"~~~~~~~> buffer offset %ld", bufferOffset);
            char nalu_byte;
            memcpy(&nalu_byte, dataPointer + bufferOffset + 4, 1);
            
//            int nalu_type = (nalu_byte & 0x1f);
//            [LiveStreamDebugHelper translateNALUType:nalu_type];
            
            // 叠加nalu
            NSData* data = [[NSData alloc] initWithBytes:(dataPointer + bufferOffset + AVCCHeaderLength) length:NALUnitLength];
            
            const char bytes[] = "\x00\x00\x00\x01"; // AVC Header
            size_t length = (sizeof bytes) - 1; //string literals have implicit trailing '\0'
            NSData *byteHeader = [NSData dataWithBytes:bytes length:length];
            NSMutableData *fullAVCData = [NSMutableData dataWithData:byteHeader];
            [fullAVCData appendData:data];
            
//          [self.packet appendData:sps];
//          [self.packet appendData:pps];
            [self.packet appendData:fullAVCData];
            
            // Move to the next NAL unit in the block buffer
            bufferOffset += AVCCHeaderLength + NALUnitLength;
        }
    }
}

@end
