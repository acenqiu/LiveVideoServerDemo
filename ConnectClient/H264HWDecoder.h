//
//  H264HWDecoder.h
//  SmartToothbrush
//
//  Created by Acen on 16/3/12.
//  Copyright © 2016年 Acen Works. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <VideoToolbox/VideoToolbox.h>

@protocol H264HWDecoderDelegate;

@interface H264HWDecoder : NSObject

@property (nonatomic, assign) id<H264HWDecoderDelegate> delegate;

- (void)decodeFromRawRTPPacket:(NSData *)data timestamp:(CMTime)timestamp;;
- (void)decodeFromRawFrames:(uint8_t *)frame withSize:(uint32_t)frameSize timestamp:(CMTime)timestamp;

@end

@protocol H264HWDecoderDelegate <NSObject>

- (void)displaySampleBuffer:(CMSampleBufferRef)sampleBuffer formatDescription:(CMFormatDescriptionRef)formatDescription;

@end