//
//  Communicator.m
//  ConnectClient
//
//  Created by Acen on 16/3/12.
//  Copyright © 2016年 Peergine. All rights reserved.
//

#import "Communicator.h"
#include "pgLibConnect.h"

static void dprintf0(const char* lpszFmt, ...)
{
    va_list args;
    char szBuf[1024] = {0};
    va_start(args, lpszFmt);
    int iSize = vsnprintf(szBuf, sizeof(szBuf), lpszFmt, args);
    if (iSize > 0 && (iSize + 3) < sizeof(szBuf)) {
        szBuf[iSize] = '\n';
        szBuf[iSize + 1] = '\0';
        printf("%s", szBuf);
    }
}

void DebugOut(unsigned int uLevel, const char* lpszOut)
{
//    dprintf0(lpszOut);
}

void onCallback(const char* lpszParam)
{
    NSString *sParam = [NSString stringWithUTF8String:lpszParam];
    
    NSLog(@"callback %@", sParam);
}

@implementation Communicator

- (instancetype)init
{
    if (self = [super init]) {
        m_Thread = nil;
        m_iTerm = 0;
        m_uInstID = 0;
        m_uSessID = 0;
        m_szDevID[0] = '\0';
    }
    
    return self;
}

-(void)cnntStart
{
    if (m_Thread != nil) {
        return;
    }
    
    m_iTerm = 0;
    m_uInstID = 0;
    m_uSessID = 0;
    
    NSLog(@"Connecting");
    
    m_Thread = [NSThread alloc];
    [m_Thread initWithTarget:self selector:@selector(cnntMain:) object:self];
    [m_Thread start];
}

-(void)cnntStop
{
    if (m_uSessID > 0) {
        pgClose(m_uInstID, m_uSessID);
    }
    
    [m_Thread cancel];
    while (m_iTerm == 0) {
        [NSThread sleepForTimeInterval:0.1f];
    }
    
    m_Thread = nil;
    
    NSLog(@"No Connect");
}

-(void)cnntWrite:(NSString *)sData
{
    NSLog(@"[WRITE]=%@", sData);
    
    const char* pszData = [sData UTF8String];
    if (pszData != 0) {
        int iErr = pgWrite(m_uInstID, m_uSessID, pszData, (unsigned int)strlen(pszData), PG_PRIORITY_1);
        if (iErr < PG_ERROR_OK) {
            dprintf0("pgWrite: iErr=%d", iErr);
        }
    }
}

- (void)cnntWriteBinary:(NSData *)data
{
    NSLog(@"[WRITE]=%ld bytes, sessID = %d", data.length, m_uSessID);
//    [self cnntWrite:[NSString stringWithFormat:@"<======== ping %ld ======", data.length]];
    if ([data length] > 0) {
        int iErr = pgWrite(m_uInstID, m_uSessID, data.bytes, (unsigned int)data.length, PG_PRIORITY_2);
        if (iErr < PG_ERROR_OK) {
            dprintf0("pgWrite: iErr=%d", iErr);
        }
    }
}

-(void)cnntMain:(id)pThis
{
    PG_INIT_CFG_S stInitCfg;
    stInitCfg.uBufSize[1] = 1024;
    stInitCfg.uBufSize[2] = 1024 * 2;
    stInitCfg.uBufSize[3] = 1024 * 3;
    memset(&stInitCfg, 0, sizeof(stInitCfg));
    if (pgInitialize(&m_uInstID, PG_MODE_LISTEN, "ACEN_1228", "",
                     "connect.peergine.com:7781", "", &stInitCfg, DebugOut) != PG_ERROR_OK)
    {
        dprintf0("Init peergine module failed.\n");
        m_iTerm = 1;
        return;
    }
    
    dprintf0("Init peergine module success.\n");
    
//    int iErr = pgOpen(m_uInstID, [@"MORE_1228" UTF8String], &m_uSessID);
//        if (iErr != PG_ERROR_OK) {
//    	    pgCleanup(m_uInstID);
//    	    m_uInstID = 0;
//            m_iTerm = 1;
//            return;
//        }
    
    unsigned int uCount = 0;
    NSLog(@"start to loop");
    while (!m_Thread.isCancelled) {
        
        unsigned int uSessIDNow = 0;
        unsigned int uEventNow = PG_EVENT_NULL;
        unsigned int uPrio = PG_PRIORITY_BUTT;
        
        int iErr = pgEvent(m_uInstID, &uEventNow, &uSessIDNow, &uPrio, 20);
        if (iErr != PG_ERROR_OK) {
            if (iErr != PG_ERROR_TIMEOUT) {
                dprintf0("Event: iErr=%d\n", iErr);
            }
            
            // heartbeat
            uCount++;
            if ((uCount % 100) == 0) {
                int iRet = pgServerRequest(m_uInstID, "Report: test", 0);
                if (iRet != PG_ERROR_TIMEOUT) {
                    printf("pgServerRequest: iErr=%d\n", iRet);
                }
            }
            
            continue;
        }
        
        if (uEventNow == PG_EVENT_CONNECT) {
            dprintf0("CONNECT: SessID=%u\n", uSessIDNow);
            m_uSessID = uSessIDNow;
            
            if (self.delegate) {
                [self.delegate communicatorDidConnected];
            }
        }
        else if (uEventNow == PG_EVENT_INFO) {
            dprintf0("INFO: SessID=%u\n", uSessIDNow);
            
            PG_INFO_S stInfo;
            int iRet = pgInfo(m_uInstID, uSessIDNow, &stInfo);
            if (iRet == PG_ERROR_OK) {
                printf("pgInfo: PeerID=%s, AddrPub=%s, AddrPriv=%s, CnntType=%u\n",
                       stInfo.szPeerID, stInfo.szAddrPub, stInfo.szAddrPriv, stInfo.uCnntType);
            }
        }
        else if (uEventNow == PG_EVENT_CLOSE) {
            dprintf0("CLOSE: SessID=%u\n", uSessIDNow);
            
            pgClose(m_uInstID, uSessIDNow);
            m_uSessID = 0;
            
            [self.delegate communicatorDidDisConnect];
        }
        else if (uEventNow == PG_EVENT_READ) {
            dprintf0("READ: SessID=%u, uPrio=%u\n", uSessIDNow, uPrio);
            
            char szCmd[256] = {0};
            unsigned int uPrio = 0;
            int iRet = pgRead(m_uInstID, uSessIDNow, szCmd, (sizeof(szCmd) - 1), &uPrio);
            if (iRet < PG_ERROR_OK) {
                dprintf0("Read: iErr=%d\n", iRet);
                continue;
            }
            
            szCmd[iRet] = '\0';
            dprintf0("COMMAND: %s\n", szCmd);
        }
        else if (uEventNow == PG_EVENT_WRITE) {
            dprintf0("WRITE: SessID=%u, uPrio=%u\n", uSessIDNow, uPrio);
        }
        else if (uEventNow == PG_EVENT_SVR_LOGIN) {
            dprintf0("SVR_LOGIN:\n");
        }
        else if (uEventNow == PG_EVENT_SVR_LOGOUT) {
            dprintf0("SVR_LOGOUT:\n");
        }
        else if (uEventNow == PG_EVENT_SVR_REPLY) {
            dprintf0("SVR_REPLY:\n");
            
            char szBuf[1024] = {0};
            unsigned int uParam = 0;
            int iRet = pgServerReply(m_uInstID, szBuf, sizeof(szBuf), &uParam);
            if (iRet < PG_ERROR_OK) {
                dprintf0("pgServerReply: iErr=%d\n", iErr);
                continue;
            }
            
            szBuf[iRet] = '\0';
            dprintf0("Reply: %s\n", szBuf);
        }
        else if (uEventNow == PG_EVENT_SVR_NOTIFY) {
            dprintf0("SVR_NOTIFY:\n");
            
            char szBuf[1024] = {0};
            int iRet = pgServerNotify(m_uInstID, szBuf, sizeof(szBuf));
            if (iRet < PG_ERROR_OK) {
                dprintf0("pgServerNotify: iErr=%d\n", iErr);
                continue;
            }
            
            szBuf[iRet] = '\0';
            dprintf0("Notify: %s\n", szBuf);
        }
        else if (uEventNow == PG_EVENT_OFFLINE) {
            dprintf0("OFFLINE: SessID=%u\n", uSessIDNow);
            onCallback("OFFLINE?");
        }
    }
    
    pgCleanup(m_uInstID);
    m_uInstID = 0;
    
    dprintf0("Clean peergine module.");
    
    m_iTerm = 1;
}

@end
