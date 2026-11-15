#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
/// All operations may block. Call off the main thread; cancel is nonblocking.
@interface WLTorrentBridge : NSObject
- (instancetype)initWithDirectory:(NSString *)directory cacheBytes:(int64_t)cacheBytes;
- (BOOL)open:(NSString *)source error:(NSError **)error;
- (nullable NSDictionary *)snapshot:(NSError **)error;
- (BOOL)selectFile:(NSInteger)index error:(NSError **)error;
- (nullable NSData *)readAt:(int64_t)offset count:(NSInteger)count error:(NSError **)error NS_SWIFT_NAME(read(offset:count:));
- (void)cancel;
- (void)stop;
@end
NS_ASSUME_NONNULL_END
