#import "Fetcher.h"

@implementation VPNProviderConfig

- (NSDictionary *)toDictionary {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"id"] = self.providerId ?: @"";
    d[@"name"] = self.name ?: @"";
    d[@"subscriptionURL"] = self.subscriptionURL ?: @"";
    if (self.keychainService.length > 0) d[@"keychainService"] = self.keychainService;
    if (self.keychainAccount.length > 0) d[@"keychainAccount"] = self.keychainAccount;
    d[@"useProxy"] = @(self.useProxy);
    d[@"enabled"] = @(self.enabled);
    return d;
}

+ (instancetype)fromDictionary:(NSDictionary *)dict {
    VPNProviderConfig *p = [[VPNProviderConfig alloc] init];
    p.providerId = dict[@"id"] ?: [[NSUUID UUID] UUIDString];
    p.name = dict[@"name"] ?: @"VPN";
    p.subscriptionURL = dict[@"subscriptionURL"] ?: @"";
    p.keychainService = dict[@"keychainService"];
    p.keychainAccount = dict[@"keychainAccount"];
    p.useProxy = [dict[@"useProxy"] boolValue];
    p.enabled = dict[@"enabled"] ? [dict[@"enabled"] boolValue] : YES;
    return p;
}

@end

@implementation AppConfig

+ (NSString *)appSupportDir {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    return [paths.firstObject stringByAppendingPathComponent:@"VPNTrafficBar"];
}

+ (NSString *)configPath {
    return [[self appSupportDir] stringByAppendingPathComponent:@"config.json"];
}

+ (NSString *)databasePath {
    return [[self appSupportDir] stringByAppendingPathComponent:@"traffic.db"];
}

- (NSDictionary *)toDictionary {
    NSMutableArray *arr = [NSMutableArray array];
    for (VPNProviderConfig *p in self.providers) {
        [arr addObject:[p toDictionary]];
    }
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"refreshIntervalMinutes"] = @(self.refreshIntervalMinutes);
    d[@"proxyHost"] = self.proxyHost ?: @"127.0.0.1";
    d[@"proxyPort"] = @(self.proxyPort);
    if (self.primaryProviderId.length > 0) d[@"primaryProviderId"] = self.primaryProviderId;
    d[@"providers"] = arr;
    return d;
}

+ (instancetype)fromDictionary:(NSDictionary *)dict {
    AppConfig *c = [[AppConfig alloc] init];
    c.refreshIntervalMinutes = dict[@"refreshIntervalMinutes"] ? MAX(0, [dict[@"refreshIntervalMinutes"] integerValue]) : 480;
    c.proxyHost = dict[@"proxyHost"] ?: @"127.0.0.1";
    c.proxyPort = dict[@"proxyPort"] ? [dict[@"proxyPort"] integerValue] : 7899;
    c.primaryProviderId = dict[@"primaryProviderId"];
    c.providers = [NSMutableArray array];
    for (NSDictionary *pd in (dict[@"providers"] ?: @[])) {
        [c.providers addObject:[VPNProviderConfig fromDictionary:pd]];
    }
    return c;
}

+ (instancetype)loadOrSeed {
    NSData *data = [NSData dataWithContentsOfFile:[self configPath]];
    if (data) {
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([json isKindOfClass:[NSDictionary class]]) {
            return [self fromDictionary:json];
        }
    }
    AppConfig *cfg = [[AppConfig alloc] init];
    cfg.refreshIntervalMinutes = 480;
    cfg.proxyHost = @"127.0.0.1";
    cfg.proxyPort = 7899;
    cfg.primaryProviderId = nil;
    cfg.providers = [NSMutableArray array];
    [cfg save];
    return cfg;
}

- (void)save {
    [[NSFileManager defaultManager] createDirectoryAtPath:[AppConfig appSupportDir] withIntermediateDirectories:YES attributes:nil error:nil];
    NSData *data = [NSJSONSerialization dataWithJSONObject:[self toDictionary] options:NSJSONWritingPrettyPrinted error:nil];
    if (data) {
        [data writeToFile:[AppConfig configPath] atomically:YES];
    }
}

@end

@implementation SubscriptionFetcher

+ (nullable NSString *)readKeychainService:(NSString *)service account:(NSString *)account {
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/security"];
    task.arguments = @[@"find-generic-password", @"-s", service, @"-a", account ?: @"default", @"-w"];
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = [NSPipe pipe];
    NSError *err = nil;
    if (![task launchAndReturnError:&err]) return nil;
    [task waitUntilExit];
    if (task.terminationStatus != 0) return nil;
    NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
    NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return [str stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

+ (nullable TrafficSnapshot *)parseUserinfo:(NSString *)header providerId:(NSString *)providerId {
    NSMutableDictionary<NSString *, NSNumber *> *vals = [NSMutableDictionary dictionary];
    for (NSString *part in [header componentsSeparatedByString:@";"]) {
        NSRange eq = [part rangeOfString:@"="];
        if (eq.location == NSNotFound) continue;
        NSString *key = [[part substringToIndex:eq.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]].lowercaseString;
        NSString *valStr = [[part substringFromIndex:eq.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (valStr.length > 0) {
            vals[key] = @(strtoll(valStr.UTF8String, NULL, 10));
        }
    }
    if (!vals[@"total"]) return nil;
    TrafficSnapshot *snap = [[TrafficSnapshot alloc] init];
    snap.providerId = providerId;
    snap.timestamp = [NSDate date];
    snap.upload = vals[@"upload"].longLongValue;
    snap.download = vals[@"download"].longLongValue;
    snap.total = vals[@"total"].longLongValue;
    int64_t exp = vals[@"expire"].longLongValue;
    if (exp > 0) {
        snap.expire = [NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)exp];
    }
    return snap;
}

+ (void)fetchProvider:(VPNProviderConfig *)provider
            proxyHost:(NSString *)proxyHost
            proxyPort:(NSInteger)proxyPort
           completion:(void (^)(TrafficSnapshot * _Nullable, NSString * _Nullable))completion {
    NSString *rawURL = nil;
    if (provider.keychainService.length > 0) {
        rawURL = [self readKeychainService:provider.keychainService account:provider.keychainAccount ?: @"default"];
        if (rawURL.length == 0) {
            completion(nil, @"钥匙串中未找到订阅");
            return;
        }
    } else {
        rawURL = [provider.subscriptionURL stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (rawURL.length == 0) {
            completion(nil, @"未配置订阅链接");
            return;
        }
    }

    NSURL *url = [NSURL URLWithString:rawURL];
    if (!url) {
        completion(nil, @"订阅链接格式无效");
        return;
    }

    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    cfg.timeoutIntervalForRequest = 15.0;
    cfg.timeoutIntervalForResource = 20.0;
    if (provider.useProxy && proxyHost.length > 0 && proxyPort > 0) {
        cfg.connectionProxyDictionary = @{
            (NSString *)kCFNetworkProxiesHTTPEnable: @YES,
            (NSString *)kCFNetworkProxiesHTTPProxy: proxyHost,
            (NSString *)kCFNetworkProxiesHTTPPort: @(proxyPort),
            (NSString *)kCFNetworkProxiesHTTPSEnable: @YES,
            (NSString *)kCFNetworkProxiesHTTPSProxy: proxyHost,
            (NSString *)kCFNetworkProxiesHTTPSPort: @(proxyPort),
        };
    }

    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"GET";
    req.cachePolicy = NSURLRequestReloadIgnoringLocalAndRemoteCacheData;
    [req setValue:@"clash.meta" forHTTPHeaderField:@"User-Agent"];
    [req setValue:@"text/plain, application/yaml, */*" forHTTPHeaderField:@"Accept"];

    NSURLSessionDataTask *task = [session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        [session invalidateAndCancel];
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
        if (!error && [http isKindOfClass:[NSHTTPURLResponse class]] && http.statusCode == 200) {
            NSString *headerVal = nil;
            for (id key in http.allHeaderFields) {
                if ([[key description].lowercaseString isEqualToString:@"subscription-userinfo"]) {
                    headerVal = [http.allHeaderFields[key] description];
                    break;
                }
            }
            if (headerVal.length > 0) {
                TrafficSnapshot *snap = [self parseUserinfo:headerVal providerId:provider.providerId];
                if (snap) {
                    completion(snap, nil);
                    return;
                }
            }
        }

        // Fallback: ask local Clash/Mihomo external-controller (127.0.0.1:9090) if available
        NSString *directErr = error
            ? [NSString stringWithFormat:@"连接失败 (%ld)", (long)error.code]
            : ([http isKindOfClass:[NSHTTPURLResponse class]]
                ? (http.statusCode == 401 ? @"HTTP 401（服务端暂拒，沿用缓存）" : [NSString stringWithFormat:@"HTTP %ld", (long)http.statusCode])
                : @"无效响应");

        [self fetchFromLocalClashAPIForProvider:provider completion:^(TrafficSnapshot * _Nullable clashSnap) {
            if (clashSnap) {
                completion(clashSnap, nil);
            } else {
                completion(nil, directErr);
            }
        }];
    }];
    [task resume];
}

+ (void)fetchFromLocalClashAPIForProvider:(VPNProviderConfig *)provider
                               completion:(void (^)(TrafficSnapshot * _Nullable))completion {
    NSURL *listURL = [NSURL URLWithString:@"http://127.0.0.1:9090/providers/proxies"];
    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    cfg.timeoutIntervalForRequest = 4.0;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg];

    [[session dataTaskWithURL:listURL completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (err || !data) {
            [session invalidateAndCancel];
            completion(nil);
            return;
        }
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSDictionary *providers = [json isKindOfClass:[NSDictionary class]] ? json[@"providers"] : nil;
        if (![providers isKindOfClass:[NSDictionary class]]) {
            [session invalidateAndCancel];
            completion(nil);
            return;
        }

        NSString *matchedKey = nil;
        for (NSString *k in providers) {
            if ([k.lowercaseString isEqualToString:provider.providerId.lowercaseString] ||
                [k.lowercaseString isEqualToString:provider.name.lowercaseString]) {
                matchedKey = k;
                break;
            }
        }
        if (!matchedKey) {
            [session invalidateAndCancel];
            completion(nil);
            return;
        }

        NSString *encodedKey = [matchedKey stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLPathAllowedCharacterSet]];
        NSURL *putURL = [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:9090/providers/proxies/%@", encodedKey]];
        NSMutableURLRequest *putReq = [NSMutableURLRequest requestWithURL:putURL];
        putReq.HTTPMethod = @"PUT";
        putReq.timeoutInterval = 12.0;

        [[session dataTaskWithRequest:putReq completionHandler:^(NSData *d2, NSURLResponse *r2, NSError *e2) {
            [[session dataTaskWithURL:listURL completionHandler:^(NSData *d3, NSURLResponse *r3, NSError *e3) {
                [session invalidateAndCancel];
                if (e3 || !d3) { completion(nil); return; }
                NSDictionary *j3 = [NSJSONSerialization JSONObjectWithData:d3 options:0 error:nil];
                NSDictionary *info = j3[@"providers"][matchedKey][@"subscriptionInfo"];
                if (![info isKindOfClass:[NSDictionary class]] || !info[@"Total"]) {
                    completion(nil);
                    return;
                }
                TrafficSnapshot *snap = [[TrafficSnapshot alloc] init];
                snap.providerId = provider.providerId;
                snap.timestamp = [NSDate date];
                snap.upload = [info[@"Upload"] longLongValue];
                snap.download = [info[@"Download"] longLongValue];
                snap.total = [info[@"Total"] longLongValue];
                int64_t exp = [info[@"Expire"] longLongValue];
                if (exp > 0) snap.expire = [NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)exp];
                completion(snap);
            }] resume];
        }] resume];
    }] resume];
}

@end
