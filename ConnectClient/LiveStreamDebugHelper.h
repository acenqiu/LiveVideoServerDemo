//
//  LiveStreamDebugHelper.h
//  ConnectClient
//
//  Created by Acen on 16/3/13.
//  Copyright © 2016年 Peergine. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface LiveStreamDebugHelper : NSObject

+ (void)translateNALUType:(int)type;
+ (void)translateNALUType:(int)type size:(int)size;

@end
