//
//  RTP.m
//  ConnectClient
//
//  Created by Acen on 16/3/12.
//  Copyright © 2016年 Peergine. All rights reserved.
//

#import "RTP.h"

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

@interface RTP()
{
    uint16_t seqNum;
    int64_t start_t;
}
@end

@implementation RTP

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        seqNum = 0;
        start_t = 0;
    }
    return self;
}

#pragma mark - Publish

- (NSData *)publish:(NSData *)data timestamp:(CMTime)timestamp payloadType:(NSInteger)payloadType
{
    int64_t t = (timestamp.value / 10000); // 1/100ms
    if (start_t == 0) start_t = t;
    
//    NSLog(@"time value=%lld, scale=%d, t=%lld", timestamp.value, timestamp.timescale, t);
    
    struct rtp_header header;
    
    //fill the header array of byte with RTP header fields
    header.v = 2;
    header.p = 0;
    header.x = 0;
    header.cc = 0;
    header.m = 0;
    header.pt = payloadType;
    header.seq = seqNum;
    header.ts = (uint32_t)(t - start_t);
    header.ssrc = (u_int32_t)554; // self.port;
    
    /* send RTP stream packet */
    NSMutableData *packet = [NSMutableData dataWithBytes:&header length:12];
    [packet appendData:data];
    
    seqNum++;
    
    return packet;
    
//    [self.communicator cnntWriteBinary:packet];
}


@end
