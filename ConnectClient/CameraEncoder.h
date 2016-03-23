//
//  CameraEncoder.h
//  ConnectClient
//
//  Created by Acen on 16/3/12.
//  Copyright © 2016年 Peergine. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>

#import "H264HWEncoder.h"

@protocol CameraEncoderDelegate;

@interface CameraEncoder : NSObject<AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, H264HWEncoderDelegate>

@property (strong, nonatomic) AVCaptureVideoPreviewLayer *previewLayer;
@property (strong, nonatomic) AVSampleBufferDisplayLayer *displayLayer;
@property (nonatomic, assign) id<CameraEncoderDelegate> delegate;

- (void) initCameraWithOutputSize:(CGSize)size;
- (void) startCamera;
- (void) stopCamera;

- (void)ping;

@end

@protocol CameraEncoderDelegate <NSObject>

- (void)cameraDidGetSampleBuffer:(CMSampleBufferRef)sampleBuffer;

@end