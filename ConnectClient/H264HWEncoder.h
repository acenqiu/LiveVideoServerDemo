//
//  H264HWEncoder.h
//  ConnectClient
//
//  Created by Acen on 16/3/12.
//  Copyright © 2016年 Peergine. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <VideoToolbox/VideoToolbox.h>
#import <AVFoundation/AVFoundation.h>

@protocol H264HWEncoderDelegate <NSObject>

@required

- (void)gotH264EncodedSampleBuffer:(CMSampleBufferRef)sampleBuffer;

@end

@interface H264HWEncoder : NSObject

- (void) invalidate;
- (void) encode:(CMSampleBufferRef )sampleBuffer;

@property (assign, nonatomic) id<H264HWEncoderDelegate> delegate;

@end
