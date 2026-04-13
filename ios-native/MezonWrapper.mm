#import "MezonWrapper.h"
#include "mezon_client.h"
#include <vector>

@implementation MezonWrapper {
    mezon_session_t *_session;
}

- (instancetype)initWithHost:(NSString *)host port:(int)port {
    self = [super init];
    if (self) {
        mezon_config_t cfg;
        memset(&cfg, 0, sizeof(cfg));
        
        // Convert NSString to C-String
        cfg.host = [host UTF8String];
        
        // Note: For raw TCP sockets on iOS, ensure your mezon_create 
        // handles the sockaddr setup internally.
        _session = mezon_create(&cfg, 0);
        
        if (!_session) {
            NSLog(@"[Mezon-iOS] Failed to create session");
            return nil;
        }
        NSLog(@"[Mezon-iOS] Session created for %@:%d", host, port);
    }
    return self;
}

- (int)sendData:(NSData *)data {
    if (!_session) return -1;
    
    // Pass raw bytes from NSData to the C core
    int result = mezon_send(_session, 
                            0, 
                            (const uint8_t *)[data bytes], 
                            [data length], 
                            false);
    return result;
}

- (void)poll {
    if (_session) {
        // mezon_tick polls the raw socket and handles the Abridged framing
        mezon_tick(_session, 0);
    }
}

- (void)disconnect {
    if (_session) {
        // mezon_destroy(s) should be in your mezon_client.c to close sockets
        free(_session);
        _session = nullptr;
    }
}

- (void)dealloc {
    [self disconnect];
}

@end