//
//  Communicator.h
//  ConnectClient
//
//  Created by Acen on 16/3/12.
//  Copyright © 2016年 Peergine. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol CommunicatorDelegate;

@interface Communicator : NSObject
{
    NSThread *m_Thread;
    int m_iTerm;
    
    unsigned int m_uInstID;
    unsigned int m_uSessID;
    
    char m_szDevID[128];
}

@property (nonatomic, assign) id<CommunicatorDelegate> delegate;

-(void)cnntStart;
-(void)cnntStop;
-(void)cnntWrite:(NSString *)sData;
-(void)cnntWriteBinary:(NSData *)data;

-(void)cnntMain:(id)pThis;

@end

@protocol CommunicatorDelegate

@optional

- (void)communicatorConnectivityDidChange;

- (void)communicatorDidConnected;
- (void)communicatorDidDisConnect;

- (void)communicatorDidGetScanResult:(NSArray *)devices;

@end
