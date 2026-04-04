#import "OpenURLHelper.h"

@implementation OpenURLHelper

+ (void)openURL:(NSURL *)url completionHandler:(void (^)(BOOL success))completionHandler {
    UIApplication *application = [UIApplication performSelector:@selector(sharedApplication)];
    if (application == nil) {
        NSLog(@"[MezonSharing] ERROR: UIApplication.sharedApplication returned nil");
        if (completionHandler) {
            completionHandler(NO);
        }
        return;
    }

    NSLog(@"[MezonSharing] ObjC: Calling open:options:completionHandler: with URL: %@", url.absoluteString);

    if ([application respondsToSelector:@selector(openURL:options:completionHandler:)]) {
        [application openURL:url options:@{} completionHandler:^(BOOL success) {
            NSLog(@"[MezonSharing] ObjC: openURL result: %d", success);
            if (completionHandler) {
                completionHandler(success);
            }
        }];
    } else {
        NSLog(@"[MezonSharing] ObjC ERROR: application does not respond to open:options:completionHandler:");
        if (completionHandler) {
            completionHandler(NO);
        }
    }
}

@end
