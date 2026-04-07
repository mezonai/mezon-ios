#import <UIKit/UIKit.h>

@interface OpenURLHelper : NSObject

/// Opens a URL from a Share Extension by calling the non-deprecated
/// -[UIApplication open:options:completionHandler:] via ObjC runtime.
+ (void)openURL:(NSURL *)url completionHandler:(void (^)(BOOL success))completionHandler;

@end
