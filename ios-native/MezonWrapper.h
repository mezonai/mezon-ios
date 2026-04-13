#import <Foundation/Foundation.h>

@interface MezonWrapper : NSObject

- (instancetype)initWithHost:(NSString *)host port:(int)port;
- (int)sendData:(NSData *)data;
- (void)poll;
- (void)disconnect;

@end