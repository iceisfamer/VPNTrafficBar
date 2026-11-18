#import <Foundation/Foundation.h>
#import "TrafficDB.h"
#import "Fetcher.h"

NS_ASSUME_NONNULL_BEGIN

@interface LocalClashTracker : NSObject
- (instancetype)initWithDB:(TrafficDB *)db providersProvider:(NSArray<VPNProviderConfig *> * (^)(void))providersBlock;
- (void)start;
- (void)stop;
@end

NS_ASSUME_NONNULL_END
