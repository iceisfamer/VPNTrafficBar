#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TrafficSnapshot : NSObject
@property (nonatomic, copy) NSString *providerId;
@property (nonatomic, strong) NSDate *timestamp;
@property (nonatomic, assign) int64_t upload;
@property (nonatomic, assign) int64_t download;
@property (nonatomic, assign) int64_t total;
@property (nonatomic, strong, nullable) NSDate *expire;
@property (nonatomic, readonly) int64_t used;
@property (nonatomic, readonly) int64_t remaining;
@end

@interface DailyUsageItem : NSObject
@property (nonatomic, strong) NSDate *date;
@property (nonatomic, copy) NSString *label;
@property (nonatomic, assign) int64_t bytes;
@end

@interface TrafficDB : NSObject
- (nullable instancetype)initWithPath:(NSString *)path;
- (void)insertSnapshot:(TrafficSnapshot *)snap;
- (nullable TrafficSnapshot *)latestSnapshotForProvider:(NSString *)providerId;
- (int64_t)usageForProvider:(NSString *)providerId since:(NSDate *)since;
- (NSArray<DailyUsageItem *> *)dailyUsage7DaysForProvider:(NSString *)providerId now:(NSDate *)now;

// Local ClashX Meta (127.0.0.1:9090) per-hour traffic tracking
- (void)addLocalBytes:(int64_t)bytes forProvider:(NSString *)providerId atDate:(NSDate *)date;
- (int64_t)localUsageForProvider:(NSString *)providerId since:(NSDate *)since;
- (NSArray<DailyUsageItem *> *)localDailyUsage7DaysForProvider:(NSString *)providerId now:(NSDate *)now;
@end

NS_ASSUME_NONNULL_END
