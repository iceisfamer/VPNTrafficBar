#import <Foundation/Foundation.h>
#import "TrafficDB.h"

NS_ASSUME_NONNULL_BEGIN

@interface VPNProviderConfig : NSObject
@property (nonatomic, copy) NSString *providerId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *subscriptionURL;
@property (nonatomic, copy, nullable) NSString *keychainService;
@property (nonatomic, copy, nullable) NSString *keychainAccount;
@property (nonatomic, assign) BOOL useProxy;
@property (nonatomic, assign) BOOL enabled;
- (NSDictionary *)toDictionary;
+ (instancetype)fromDictionary:(NSDictionary *)dict;
@end

@interface AppConfig : NSObject
@property (nonatomic, assign) NSInteger refreshIntervalMinutes;
@property (nonatomic, copy) NSString *proxyHost;
@property (nonatomic, assign) NSInteger proxyPort;
@property (nonatomic, copy, nullable) NSString *primaryProviderId;
@property (nonatomic, strong) NSMutableArray<VPNProviderConfig *> *providers;
+ (NSString *)appSupportDir;
+ (NSString *)configPath;
+ (NSString *)databasePath;
+ (instancetype)loadOrSeed;
- (void)save;
- (NSDictionary *)toDictionary;
+ (instancetype)fromDictionary:(NSDictionary *)dict;
@end

@interface SubscriptionFetcher : NSObject
+ (void)fetchProvider:(VPNProviderConfig *)provider
            proxyHost:(NSString *)proxyHost
            proxyPort:(NSInteger)proxyPort
           completion:(void (^)(TrafficSnapshot * _Nullable snapshot, NSString * _Nullable errorMessage))completion;
@end

NS_ASSUME_NONNULL_END
