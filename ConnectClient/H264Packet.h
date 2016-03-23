//
//  H264Packet.h
//  ConnectClient
//
//  Created by Acen on 16/3/12.
//  Copyright © 2016年 Peergine. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <VideoToolbox/VideoToolbox.h>

@interface H264Packet : NSObject

@property (strong, nonatomic) NSMutableData *packet;

- (id)initWithCMSampleBuffer:(CMSampleBufferRef)sample;

- (void)packetizeAVC:(CMSampleBufferRef)sample;

@end
