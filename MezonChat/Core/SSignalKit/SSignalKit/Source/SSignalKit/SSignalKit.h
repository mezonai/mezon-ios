#if __IPHONE_OS_VERSION_MIN_REQUIRED
#import <UIKit/UIKit.h>
#else
#import <Foundation/Foundation.h>
#endif

FOUNDATION_EXPORT double SSignalKitVersionNumber;

FOUNDATION_EXPORT const unsigned char SSignalKitVersionString[];

#import <SSignalKit/SAtomic.h>
#import <SSignalKit/SBag.h>
#import <SSignalKit/SSignal.h>
#import <SSignalKit/SSubscriber.h>
#import <SSignalKit/SDisposable.h>
#import <SSignalKit/SDisposableSet.h>
#import <SSignalKit/SBlockDisposable.h>
#import <SSignalKit/SMetaDisposable.h>
#import <SSignalKit/SSignal+Single.h>
#import <SSignalKit/SSignal+Mapping.h>
#import <SSignalKit/SSignal+Meta.h>
#import <SSignalKit/SSignal+Dispatch.h>
#import <SSignalKit/SSignal+Catch.h>
#import <SSignalKit/SSignal+SideEffects.h>
#import <SSignalKit/SSignal+Combine.h>
#import <SSignalKit/SSignal+Timing.h>
#import <SSignalKit/SSignal+Take.h>
#import <SSignalKit/SSignal+Pipe.h>
#import <SSignalKit/STimer.h>
#import <SSignalKit/SVariable.h>
#import <SSignalKit/SQueueLocalObject.h>
