

#import <Foundation/Foundation.h>
#import <AsyncDisplayKit/ASBaseDefines.h>
#import <CoreGraphics/CGDataProvider.h>

NS_ASSUME_NONNULL_BEGIN

AS_SUBCLASSING_RESTRICTED
@interface ASCGImageBuffer : NSObject

- (instancetype)initWithLength:(NSUInteger)length;

@property (readonly) void *mutableBytes NS_RETURNS_INNER_POINTER;

- (CGDataProviderRef)createDataProviderAndInvalidate CF_RETURNS_RETAINED;

@end

NS_ASSUME_NONNULL_END
