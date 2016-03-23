//
//  H264HWEncoder.m
//  ConnectClient
//
//  Created by Acen on 16/3/12.
//  Copyright © 2016年 Peergine. All rights reserved.
//

#import "H264HWEncoder.h"
#import "H264Packet.h"

@implementation H264HWEncoder
{
    VTCompressionSessionRef session;
}

- (void) dealloc {
    [self invalidate];
    [super dealloc];
}

- (id) init {
    if (self = [super init]) {
        session = NULL;
    }
    return self;
}

void didCompressH264(void *outputCallbackRefCon, void *sourceFrameRefCon, OSStatus status, VTEncodeInfoFlags infoFlags,
                     CMSampleBufferRef sampleBuffer )
{
    H264HWEncoder* encoder = (__bridge H264HWEncoder*)outputCallbackRefCon;
    
    if (status == noErr) {
        return [encoder didReceiveSampleBuffer:sampleBuffer];
    }
}

- (void)didReceiveSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    if (!sampleBuffer) {
        return;
    }
    
    [self.delegate gotH264EncodedSampleBuffer:sampleBuffer];
}

- (void)initSession
{
    CFMutableDictionaryRef encoderSpecifications = NULL;
    
    OSStatus ret = VTCompressionSessionCreate(kCFAllocatorDefault, 500, 664, kCMVideoCodecType_H264, encoderSpecifications, NULL, NULL, didCompressH264, (__bridge void *)(self), &session);
    if (ret == noErr) {
        VTSessionSetProperty(session, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue);
        VTSessionSetProperty(session, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_Baseline_3_0);
        VTSessionSetProperty(session, kVTCompressionPropertyKey_AspectRatio16x9, kCFBooleanTrue);
        VTSessionSetProperty(session, kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanTrue);
        VTSessionSetProperty(session, kVTCompressionPropertyKey_MaxKeyFrameInterval, (__bridge CFTypeRef)@(90));
//        VTSessionSetProperty(session, kVTCompressionPropertyKey_MaxH264SliceBytes, (__bridge CFTypeRef)@(184)); // this is not working yet.
//        VTSessionSetProperty(session, kVTCompressionPropertyKey_ExpectedFrameRate, (__bridge CFTypeRef)@(15));
        
        // Bitrate is only working iOS. not Mac OSX
        int bitrate = 800000;
        int v = bitrate;
        
        CFNumberRef ref = CFNumberCreate(NULL, kCFNumberSInt32Type, &v);
        OSStatus ret = VTSessionSetProperty(session, kVTCompressionPropertyKey_AverageBitRate, ref);
        CFRelease(ref);
        
        ret = VTSessionCopyProperty(session, kVTCompressionPropertyKey_AverageBitRate, kCFAllocatorDefault, &ref);
        if(ret == noErr && ref) {
            SInt32 br = 0;
            
            CFNumberGetValue(ref, kCFNumberSInt32Type, &br);
            
            bitrate = br;
            CFRelease(ref);
        } else {
            bitrate = v;
        }
        
        v = bitrate/ 8;
        CFNumberRef bytes = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &v);
        v = 1;
        CFNumberRef duration = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &v);
        CFMutableArrayRef limit = CFArrayCreateMutable(kCFAllocatorDefault, 2, &kCFTypeArrayCallBacks);
        
        CFArrayAppendValue(limit, bytes);
        CFArrayAppendValue(limit, duration);
        
        VTSessionSetProperty(session, kVTCompressionPropertyKey_DataRateLimits, limit);
        CFRelease(bytes);
        CFRelease(duration);
        CFRelease(limit);
        
        VTCompressionSessionPrepareToEncodeFrames(session);
    }
}

- (void)invalidate
{
    if(session) {
        VTCompressionSessionCompleteFrames(session, kCMTimeInvalid);
        VTCompressionSessionInvalidate(session);
        CFRelease(session);
        session = NULL;
    }
}

- (void)encode:(CMSampleBufferRef )sampleBuffer
{
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    
    if(session == NULL) {
        [self initSession];
    }
    
    if( session != NULL && sampleBuffer != NULL ) {
        // Create properties
        CMTime timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
        
        VTCompressionSessionEncodeFrame(session, imageBuffer, timestamp, kCMTimeInvalid, NULL, NULL, NULL);
    }
}

@end
