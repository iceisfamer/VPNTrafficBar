#import "LocalClashTracker.h"

@interface LocalClashTracker ()
@property (nonatomic, strong) TrafficDB *db;
@property (nonatomic, copy) NSArray<VPNProviderConfig *> * (^providersBlock)(void);
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *lastConnBytes;
@property (nonatomic, assign) BOOL initialized;
@end

@implementation LocalClashTracker

- (instancetype)initWithDB:(TrafficDB *)db providersProvider:(NSArray<VPNProviderConfig *> * (^)(void))providersBlock {
    self = [super init];
    if (!self) return nil;
    _db = db;
    _providersBlock = [providersBlock copy];
    _lastConnBytes = [NSMutableDictionary dictionary];
    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    cfg.timeoutIntervalForRequest = 3.0;
    _session = [NSURLSession sessionWithConfiguration:cfg];
    return self;
}

- (void)start {
    [self stop];
    [self pollOnce];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:10.0
                                                  target:self
                                                selector:@selector(pollOnce)
                                                userInfo:nil
                                                 repeats:YES];
}

- (void)stop {
    [self.timer invalidate];
    self.timer = nil;
}

- (nullable NSString *)matchProviderIdForChains:(NSArray<NSString *> *)chains providers:(NSArray<VPNProviderConfig *> *)providers {
    if (chains.count == 0) return nil;
    for (NSString *c in chains) {
        NSString *up = c.uppercaseString;
        if ([up isEqualToString:@"DIRECT"] || [up isEqualToString:@"REJECT"]) {
            return nil;
        }
    }
    NSString *joined = [[chains componentsJoinedByString:@" "] lowercaseString];
    for (VPNProviderConfig *p in providers) {
        if (!p.enabled) continue;
        NSString *pid = p.providerId.lowercaseString;
        NSString *pname = p.name.lowercaseString;
        if (pid.length >= 2 && [joined containsString:pid]) return p.providerId;
        if (pname.length >= 2 && [joined containsString:pname]) return p.providerId;
        if (pname.length >= 2) {
            NSString *prefix2 = [pname substringToIndex:2];
            if ([joined containsString:prefix2]) return p.providerId;
        }
    }
    return nil;
}

- (void)pollOnce {
    NSURL *url = [NSURL URLWithString:@"http://127.0.0.1:9090/connections"];
    [[self.session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (err || !data) return;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSArray *conns = [json isKindOfClass:[NSDictionary class]] ? json[@"connections"] : nil;
        if (![conns isKindOfClass:[NSArray class]]) return;

        dispatch_async(dispatch_get_main_queue(), ^{
            NSArray<VPNProviderConfig *> *providers = self.providersBlock ? self.providersBlock() : @[];
            NSMutableDictionary<NSString *, NSNumber *> *nextMap = [NSMutableDictionary dictionaryWithCapacity:conns.count];
            NSMutableDictionary<NSString *, NSNumber *> *deltas = [NSMutableDictionary dictionary];

            for (NSDictionary *c in conns) {
                if (![c isKindOfClass:[NSDictionary class]]) continue;
                NSString *cid = c[@"id"];
                if (![cid isKindOfClass:[NSString class]] || cid.length == 0) continue;

                int64_t totalBytes = [c[@"upload"] longLongValue] + [c[@"download"] longLongValue];
                nextMap[cid] = @(totalBytes);

                if (self.initialized) {
                    NSNumber *prev = self.lastConnBytes[cid];
                    int64_t delta = prev ? MAX(0, totalBytes - prev.longLongValue) : totalBytes;
                    if (delta > 0) {
                        NSArray *chains = [c[@"chains"] isKindOfClass:[NSArray class]] ? c[@"chains"] : @[];
                        NSString *pid = [self matchProviderIdForChains:chains providers:providers];
                        if (pid) {
                            deltas[pid] = @(deltas[pid].longLongValue + delta);
                        }
                    }
                }
            }

            self.lastConnBytes = nextMap;
            self.initialized = YES;

            NSDate *now = [NSDate date];
            for (NSString *pid in deltas) {
                [self.db addLocalBytes:deltas[pid].longLongValue forProvider:pid atDate:now];
            }
        });
    }] resume];
}

@end
