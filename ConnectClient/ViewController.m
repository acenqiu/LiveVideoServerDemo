//
//  ViewController.m
//  ConnectClient
//
//  Created by yjx0755 on 13-11-19.
//  Copyright (c) 2013年 Peergine. All rights reserved.
//

#import "ViewController.h"
#import "Communicator.h"
#import "CameraEncoder.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreImage/CoreImage.h>

@interface ViewController ()<CameraEncoderDelegate>

@property (retain, nonatomic) IBOutlet UIView *cameraView;

@property (nonatomic, strong) CameraEncoder *encoder;
@property (nonatomic, assign) BOOL isStart;
@property (retain, nonatomic) IBOutlet UIView *beforeTransferView;
@property (retain, nonatomic) IBOutlet UIImageView *imageView;

@property (nonatomic, assign) BOOL takeOnce;

@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	
    self.isStart = YES;
    self.takeOnce = NO;
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    if (!_encoder) {
        self.encoder = [[CameraEncoder alloc] init];
        self.encoder.delegate = self;
        [self.encoder initCameraWithOutputSize:self.cameraView.frame.size];
        self.encoder.previewLayer.frame = self.cameraView.bounds;
        [self.cameraView.layer addSublayer:self.encoder.previewLayer];
        
        self.encoder.displayLayer.bounds = self.beforeTransferView.bounds;
        self.encoder.displayLayer.position = CGPointMake(CGRectGetMidX(self.beforeTransferView.bounds), CGRectGetMidY(self.beforeTransferView.bounds));
        [self.beforeTransferView.layer addSublayer:self.encoder.displayLayer];
    }
}

- (IBAction)start:(UIButton *)sender
{
    if (self.isStart) {
        self.encoder.previewLayer.hidden = NO;
        [self.encoder startCamera];
        [sender setTitle:@"停止" forState:UIControlStateNormal];
    } else {
        [self.encoder stopCamera];
        [sender setTitle:@"开始" forState:UIControlStateNormal];
    }
    
    self.isStart = !self.isStart;
}

- (IBAction)ping:(id)sender
{
    self.takeOnce = YES;
//    AVSampleBufferDisplayLayer *layer = self.encoder.displayLayer;
    
//    UIView *snapshot = [self.cameraView snapshotViewAfterScreenUpdates:NO];
    
    
//    UIGraphicsBeginImageContextWithOptions(self.view.frame.size, NO, 0);
//    
//    [self.view drawViewHierarchyInRect:self.view.bounds afterScreenUpdates:NO];
//    UIImage *newImage = UIGraphicsGetImageFromCurrentImageContext();
//    UIGraphicsEndImageContext();
//    
//    self.imageView.image = newImage;
}

- (void)cameraDidGetSampleBuffer:(CMSampleBufferRef)sampleBuffer
{
    if (self.takeOnce) {
        self.takeOnce = NO;
        
        CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        
        [self screenshotOfVideoStream:imageBuffer];
    }
}

// Create a UIImage from sample buffer data
- (UIImage *)imageFromSampleBuffer:(CMSampleBufferRef) sampleBuffer
{
    // Get a CMSampleBuffer's Core Video image buffer for the media data
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    // Lock the base address of the pixel buffer
    CVPixelBufferLockBaseAddress(imageBuffer, 0);
    
    void *baseAddress = CVPixelBufferGetBaseAddress(imageBuffer);
    
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
    size_t width = CVPixelBufferGetWidth(imageBuffer);
    size_t height = CVPixelBufferGetHeight(imageBuffer);
    
    // Create a device-dependent RGB color space
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    
    // Create a bitmap graphics context with the sample buffer data
    CGContextRef context = CGBitmapContextCreate(baseAddress, width, height, 8,
                                                 bytesPerRow, colorSpace, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    // Create a Quartz image from the pixel data in the bitmap graphics context
    CGImageRef quartzImage = CGBitmapContextCreateImage(context);
    // Unlock the pixel buffer
    CVPixelBufferUnlockBaseAddress(imageBuffer,0);
    
    
    // Free up the context and color space
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);
    
    // Create an image object from the Quartz image
    UIImage *image = [UIImage imageWithCGImage:quartzImage];
    
    // Release the Quartz image
    CGImageRelease(quartzImage);
    
    return image;
}

- (void) screenshotOfVideoStream:(CVImageBufferRef)imageBuffer
{
    CIImage *ciImage = [CIImage imageWithCVPixelBuffer:imageBuffer];
    CIContext *temporaryContext = [CIContext contextWithOptions:nil];
    CGImageRef videoImage = [temporaryContext
                             createCGImage:ciImage
                             fromRect:CGRectMake(0, 0,
                                                 CVPixelBufferGetWidth(imageBuffer),
                                                 CVPixelBufferGetHeight(imageBuffer))];
    
    UIImage *image = [[UIImage alloc] initWithCGImage:videoImage];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        self.imageView.image = image;
    });

    CGImageRelease(videoImage);
}

- (void)dealloc {
    [_cameraView release];
    [_beforeTransferView release];
    [_imageView release];
    [super dealloc];
}
@end
