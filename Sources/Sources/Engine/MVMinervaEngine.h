#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface MVMinervaEngine : NSObject
- (NSInteger)generateTestChunkAndReturnVisibleFaceCountAtX:(NSInteger)x z:(NSInteger)z;
- (NSString *)engineVersion;
@end
NS_ASSUME_NONNULL_END
