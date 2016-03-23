//
//  RTP.h
//  ConnectClient
//
//  Created by Acen on 16/3/12.
//  Copyright © 2016年 Peergine. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>
#import "Communicator.h"

@interface RTP : NSObject

- (NSData *)publish:(NSData *)data timestamp:(CMTime)timestamp payloadType:(NSInteger)payloadType;

@end
