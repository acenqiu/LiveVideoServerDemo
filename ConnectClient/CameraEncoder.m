//
//  CameraEncoder.m
//  ConnectClient
//
//  Created by Acen on 16/3/12.
//  Copyright © 2016年 Peergine. All rights reserved.
//

#import "CameraEncoder.h"
#import "Communicator.h"
#import "RTP.h"
#import "H264HWDecoder.h"
#import "H264Packet.h"

@interface CameraEncoder()<CommunicatorDelegate, H264HWDecoderDelegate>
{
    H264HWEncoder *h264Encoder;
    H264HWDecoder *h264Decoder;
    AVCaptureSession *captureSession;
    AVCaptureConnection* connectionVideo;
    
    BOOL isReadyVideo, isReadyAudio;
    BOOL tryOnce;
}

@property (nonatomic, strong) Communicator *communicator;
@property (nonatomic, strong) RTP *rtp_h264;
@property (nonatomic, assign) NSUInteger framesCount;

@property (nonatomic, strong) AVAssetWriter *assetWriter;
@property (nonatomic, strong) AVAssetWriterInput *assetWriterInput;
@property (nonatomic, assign) BOOL isRecording;

@end

@implementation CameraEncoder

- (void)initCameraWithOutputSize:(CGSize)size
{
    h264Encoder = [[H264HWEncoder alloc] init];
    h264Encoder.delegate = self;
    
    h264Decoder = [[H264HWDecoder alloc] init];
    h264Decoder.delegate = self;
    
    self.communicator = [[Communicator alloc] init];
    self.communicator.delegate = self;
    
    self.rtp_h264 = [[RTP alloc] init];
//    self.rtp_h264.communicator  = self.communicator;
    
    self.framesCount = 0;
    
    isReadyAudio = NO;
    isReadyVideo = NO;
    tryOnce = YES;
    
    [self initCamera];
//    [self initAssetWriter];
}

- (void)dealloc {
    [h264Encoder invalidate];
    isReadyVideo = NO;
    
    [super dealloc];
}

#pragma mark - Camera Control

- (void) initCamera
{
    // make input device
    
    NSError *deviceError;
    
    AVCaptureDevice *cameraDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    AVCaptureDeviceInput *inputCameraDevice = [AVCaptureDeviceInput deviceInputWithDevice:cameraDevice error:&deviceError];
    
    // make output device
    
    AVCaptureVideoDataOutput *outputVideoDevice = [[AVCaptureVideoDataOutput alloc] init];
    
    NSString* key = (NSString*)kCVPixelBufferPixelFormatTypeKey;
    NSNumber* val = [NSNumber numberWithUnsignedInt:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange];
    NSDictionary* videoSettings = [NSDictionary dictionaryWithObject:val forKey:key];
    
    outputVideoDevice.videoSettings = videoSettings;
    [outputVideoDevice setSampleBufferDelegate:self queue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0)];
    
    // initialize capture session
    
    captureSession = [[AVCaptureSession alloc] init];
    [captureSession addInput:inputCameraDevice];
    [captureSession addOutput:outputVideoDevice];
    
    // begin configuration for the AVCaptureSession
    [captureSession beginConfiguration];
    
    // picture resolution
    [captureSession setSessionPreset:[NSString stringWithString:AVCaptureSessionPresetMedium]];
    
    connectionVideo = [outputVideoDevice connectionWithMediaType:AVMediaTypeVideo];
    
    [self setRelativeVideoOrientation];
    
    NSNotificationCenter* notify = [NSNotificationCenter defaultCenter];
    [notify addObserver:self
               selector:@selector(statusBarOrientationDidChange:)
                   name:@"StatusBarOrientationDidChange"
                 object:nil];
    
    [captureSession commitConfiguration];
    
    // make preview layer and add so that camera's view is displayed on screen
    
    self.previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:captureSession];
    [self.previewLayer setVideoGravity:AVLayerVideoGravityResizeAspect];
    
    self.displayLayer = [AVSampleBufferDisplayLayer layer];
    self.displayLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    self.displayLayer.backgroundColor = [[UIColor greenColor] CGColor];
    
    //set Timebase
    CMTimebaseRef controlTimebase;
    CMTimebaseCreateWithMasterClock( CFAllocatorGetDefault(), CMClockGetHostTimeClock(), &controlTimebase );
    
    self.displayLayer.controlTimebase = controlTimebase;
    CMTimebaseSetTime(self.displayLayer.controlTimebase, CMTimeMake(0, 1));
    CMTimebaseSetRate(self.displayLayer.controlTimebase, 1.0);
}

- (void) startCamera
{
    [captureSession startRunning];
    [self.communicator cnntStart];
}

- (void) stopCamera
{
    [h264Encoder invalidate];
    [captureSession stopRunning];
    [self.communicator cnntStop];
    
    if (self.assetWriter) {
        [self.assetWriterInput markAsFinished];
        [self.assetWriter finishWritingWithCompletionHandler:^{
            NSLog(@"finish completion %ld", (long)self.assetWriter.status);
        }];
    }
}

- (void)statusBarOrientationDidChange:(NSNotification*)notification {
    [self setRelativeVideoOrientation];
}

- (void)setRelativeVideoOrientation {
    switch ([[UIDevice currentDevice] orientation]) {
        case UIInterfaceOrientationPortrait:
#if defined(__IPHONE_8_0) && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_8_0
        case UIInterfaceOrientationUnknown:
#endif
            connectionVideo.videoOrientation = AVCaptureVideoOrientationPortrait;
            break;
        case UIInterfaceOrientationPortraitUpsideDown:
            connectionVideo.videoOrientation = AVCaptureVideoOrientationPortraitUpsideDown;
            break;
        case UIInterfaceOrientationLandscapeLeft:
            connectionVideo.videoOrientation = AVCaptureVideoOrientationLandscapeLeft;
            break;
        case UIInterfaceOrientationLandscapeRight:
            connectionVideo.videoOrientation = AVCaptureVideoOrientationLandscapeRight;
            break;
        default:
            break;
    }
}

- (void)captureOutput:(AVCaptureOutput*)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection*)connection
{
    
    if (tryOnce) {
        [h264Encoder encode:sampleBuffer];
//        tryOnce = NO;
    }
}

#pragma mark - Write

- (void)initAssetWriterWithFormatDescription:(CMVideoFormatDescriptionRef)formatDesc
{
    NSDictionary *compressionKey = @{AVVideoPixelAspectRatioKey: @{
                                             AVVideoPixelAspectRatioHorizontalSpacingKey: @(1),
                                             AVVideoPixelAspectRatioVerticalSpacingKey: @(1)
                                             },
                                     AVVideoMaxKeyFrameIntervalKey: @(1),
                                     AVVideoAverageBitRateKey: @(1280000)};
    
    NSDictionary *settings = @{AVVideoCodecKey: AVVideoCodecH264,
                               AVVideoWidthKey: @(500),
                               AVVideoHeightKey: @(664),
                               AVVideoCompressionPropertiesKey: compressionKey};
    
    NSURL *documentURL = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] firstObject];
    NSURL *fileURL = [documentURL URLByAppendingPathComponent:[NSString stringWithFormat:@"tmp_%d.mp4", arc4random()]];
    NSLog(@"output to %@", fileURL);
    
    NSError *error = nil;
    self.assetWriter = [AVAssetWriter assetWriterWithURL:fileURL fileType:AVFileTypeMPEG4 error:&error];
    
    if (formatDesc) {
        self.assetWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:nil sourceFormatHint:formatDesc];
    } else {
        self.assetWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:settings];
    }
    self.assetWriterInput.expectsMediaDataInRealTime = YES;
    if ([self.assetWriter canAddInput:self.assetWriterInput]) {
        [self.assetWriter addInput:self.assetWriterInput];
        NSLog(@"input added");
    }
}

- (void)tryAppendSampleBuffer:(CMSampleBufferRef)sampleBuffer
{
    AVAssetWriterStatus status = self.assetWriter.status;
    if (status != AVAssetWriterStatusUnknown && status != AVAssetWriterStatusWriting) {
        NSLog(@"can't append status %ld, error=%@", (long)self.assetWriter.status, self.assetWriter.error);
        return;
    }
    
    if (status == AVAssetWriterStatusUnknown) {
        [self.assetWriter startWriting];
        
        CMTime sourceTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
        NSLog(@"source time %f", ((float)sourceTime.value / sourceTime.timescale) * 1000);
        [self.assetWriter startSessionAtSourceTime:sourceTime];
    }
    
    CMTime sourceTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    CMTime duration = CMSampleBufferGetDuration(sampleBuffer);
    NSLog(@"source time %f, duration valid %@, zero? %@", ((float)sourceTime.value / sourceTime.timescale) * 1000, CMTIME_IS_VALID(duration) ? @"valid" : @"invalid", CMTimeCompare(duration, kCMTimeZero) ? @"zero" : @"no");
    
    if ([self.assetWriterInput isReadyForMoreMediaData]) {
        BOOL appended = [self.assetWriterInput appendSampleBuffer:sampleBuffer];
        NSLog(@"append sample %@", appended ? @"succeed" : @"failed");
        
        if (!appended) {
            NSLog(@"append failed status %ld, error=%@", (long)self.assetWriter.status, self.assetWriter.error);
        }
    } else {
        NSLog(@"can't append status %ld, error=%@", (long)self.assetWriter.status, self.assetWriter.error);
    }
}

#pragma mark - RTSPClientDelegate

- (void)communicatorDidConnected
{
    NSLog(@"Connected, ready to send data");
    isReadyVideo = YES;
}

- (void)communicatorDidDisConnect
{
    isReadyVideo = NO;
}

#pragma mark -  H264HWEncoderDelegate declare

- (void)gotH264EncodedSampleBuffer:(CMSampleBufferRef)sampleBuffer
{
    // 理论上这边的samplebuffer与rtp解出来的相同
    [self displaySampleBuffer:sampleBuffer];
    
//    [self digSampleBuffer:sampleBuffer label:@"BEFORE:"];
    
    // 获得经过压缩的内容，经过AVC, RTP封装
    H264Packet *packet = [[H264Packet alloc] initWithCMSampleBuffer:sampleBuffer];
    CMTime timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    NSData *rtp = [self.rtp_h264 publish:packet.packet timestamp:timestamp payloadType:98];
    
    if (isReadyVideo) {
        [self.communicator cnntWriteBinary:rtp];
    }
    
//    CMTime test_ts = CMTimeMake((timestamp.value - 412842498677833) / 1000000, timestamp.timescale / 1000000);
    
//    [h264Decoder decodeFromRawRTPPacket:rtp timestamp:test_ts];
}

- (void)displaySampleBuffer:(CMSampleBufferRef)sampleBuffer formatDescription:(CMFormatDescriptionRef)formatDescription
{
    [self digSampleBuffer:sampleBuffer label:@"AFTER:"];
    
    if (!_assetWriter) {
        [self initAssetWriterWithFormatDescription:CMSampleBufferGetFormatDescription(sampleBuffer)];
    }

    if (self.assetWriter) {
        [self tryAppendSampleBuffer:sampleBuffer];
    }
}

- (void)displaySampleBuffer:(CMSampleBufferRef)sampleBuffer
{
    if (self.displayLayer.isReadyForMoreMediaData) {
        CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, YES);
        CFMutableDictionaryRef dict = (CFMutableDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
        CFDictionarySetValue(dict, kCMSampleAttachmentKey_DisplayImmediately, kCFBooleanTrue);
        
        [self.displayLayer enqueueSampleBuffer:sampleBuffer];
    }
}

- (void)ping
{
}

#pragma mark - debug output

- (void)digSampleBuffer:(CMSampleBufferRef)sampleBuffer label:(NSString *)label
{
    CMTime timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    int32_t tt = (int32_t)(timestamp.value / timestamp.timescale); // s
    NSLog(@"----");
    NSLog(@"%@: time value=%lld, scale=%d, t=%d, epoch=%lld, flags=%d", label, timestamp.value, timestamp.timescale, tt, timestamp.epoch, timestamp.flags);
    NSLog(@"----");
}

@end
