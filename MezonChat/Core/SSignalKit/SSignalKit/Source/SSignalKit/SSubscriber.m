#import "SSubscriber.h"

#import <os/lock.h>

@interface SSubscriberBlocks : NSObject {
    @public
    void (^_next)(id);
    void (^_error)(id);
    void (^_completed)();
}

@end

@implementation SSubscriberBlocks

- (instancetype)initWithNext:(void (^)(id))next error:(void (^)(id))error completed:(void (^)())completed {
    self = [super init];
    if (self != nil) {
        _next = [next copy];
        _error = [error copy];
        _completed = [completed copy];
    }
    return self;
}

@end

@interface SSubscriber ()
{
    @protected
    os_unfair_lock _lock;
    bool _terminated;
    id<SDisposable> _disposable;
    SSubscriberBlocks *_blocks;
}

@end

@implementation SSubscriber

- (instancetype)initWithNext:(void (^)(id))next error:(void (^)(id))error completed:(void (^)())completed
{
    self = [super init];
    if (self != nil)
    {
        _blocks = [[SSubscriberBlocks alloc] initWithNext:next error:error completed:completed];
    }
    return self;
}

- (void)_assignDisposable:(id<SDisposable>)disposable
{
    bool dispose = false;
    os_unfair_lock_lock(&_lock);
    if (_terminated) {
        dispose = true;
    } else {
        _disposable = disposable;
    }
    os_unfair_lock_unlock(&_lock);
    if (dispose) {
        [disposable dispose];
    }
}

- (void)_markTerminatedWithoutDisposal
{
    id<SDisposable> disposable = nil;
    os_unfair_lock_lock(&_lock);
    SSubscriberBlocks *blocks = nil;
    if (!_terminated)
    {
        blocks = _blocks;
        _blocks = nil;
        
        _terminated = true;
    }
    disposable = _disposable;
    _disposable = nil;
    os_unfair_lock_unlock(&_lock);
    
    if (blocks) {
        blocks = nil;
    }
    if (disposable) {
        disposable = nil;
    }
}

- (void)putNext:(id)next
{
    SSubscriberBlocks *blocks = nil;
    
    os_unfair_lock_lock(&_lock);
    if (!_terminated) {
        blocks = _blocks;
    }
    os_unfair_lock_unlock(&_lock);
    
    if (blocks && blocks->_next) {
        blocks->_next(next);
    }
}

- (void)putError:(id)error
{
    bool shouldDispose = false;
    SSubscriberBlocks *blocks = nil;
    
    os_unfair_lock_lock(&_lock);
    if (!_terminated)
    {
        blocks = _blocks;
        _blocks = nil;
        
        shouldDispose = true;
        _terminated = true;
    }
    os_unfair_lock_unlock(&_lock);
    
    if (blocks && blocks->_error) {
        blocks->_error(error);
    }
    
    if (shouldDispose) {
        [self->_disposable dispose];
        self->_disposable = nil;
    }
}

- (void)putCompletion
{
    bool shouldDispose = false;
    SSubscriberBlocks *blocks = nil;
    
    os_unfair_lock_lock(&_lock);
    if (!_terminated)
    {
        blocks = _blocks;
        _blocks = nil;
        
        shouldDispose = true;
        _terminated = true;
    }
    os_unfair_lock_unlock(&_lock);
    
    if (blocks && blocks->_completed)
        blocks->_completed();
    
    if (shouldDispose) {
        [self->_disposable dispose];
        self->_disposable = nil;
    }
}

- (void)dispose
{
    [self->_disposable dispose];
    self->_disposable = nil;
}

@end

@interface STracingSubscriber ()
{
    NSString *_name;
}

@end

@implementation STracingSubscriber

- (instancetype)initWithName:(NSString *)name next:(void (^)(id))next error:(void (^)(id))error completed:(void (^)())completed
{
    self = [super initWithNext:next error:error completed:completed];
    if (self != nil)
    {
        _name = name;
    }
    return self;
}

@end
