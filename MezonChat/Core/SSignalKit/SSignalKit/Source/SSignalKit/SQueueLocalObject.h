

#import <Foundation/Foundation.h>
#import <SSignalKit/SQueue.h>
NS_ASSUME_NONNULL_BEGIN

@interface SQueueLocalObject : NSObject
-(id)initWithQueue:(SQueue *)queue generate:(id (^)(void))next;
-(void)with:(void (^)(id object))f;
@end

NS_ASSUME_NONNULL_END

