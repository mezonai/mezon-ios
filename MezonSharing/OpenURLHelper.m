#import "OpenURLHelper.h"

@implementation OpenURLHelper

+ (void)openURL:(NSURL *)url completionHandler:(void (^)(BOOL success))completionHandler {
    UIApplication *application = [UIApplication performSelector:@selector(sharedApplication)];
    if (application == nil) {
        if (completionHandler) {
            completionHandler(NO);
        }
        return;
    }

    if ([application respondsToSelector:@selector(openURL:options:completionHandler:)]) {
        [application openURL:url options:@{} completionHandler:^(BOOL success) {
            if (completionHandler) {
                completionHandler(success);
            }
        }];
    } else {
        if (completionHandler) {
            completionHandler(NO);
        }
    }
}

@end
