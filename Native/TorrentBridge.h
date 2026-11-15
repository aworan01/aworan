#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
/// Call off the main thread; reads poll once and return empty data while pending.
@interface WLTorrentBridge : NSObject
- (instancetype)initWithDirectory:(NSString *)directory cacheBytes:(int64_t)cacheBytes;
- (BOOL)open:(NSString *)source error:(NSError **)error;
- (nullable NSDictionary *)snapshot:(NSError **)error;
- (BOOL)selectFile:(NSInteger)index error:(NSError **)error;
- (nullable NSData *)readAt:(int64_t)offset count:(NSInteger)count requestID:(NSString *)requestID error:(NSError **)error NS_SWIFT_NAME(read(offset:count:requestID:));
- (void)finishRequest:(NSString *)requestID;
- (void)setCacheLimit:(int64_t)bytes;
- (void)cancel;
- (void)stop;
@end
NS_ASSUME_NONNULL_END
