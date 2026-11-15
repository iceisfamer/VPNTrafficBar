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
    [req setValue:@"mihomo/1.19.30" forHTTPHeaderField:@"User-Agent"];
    [req setValue:@"text/plain, application/yaml, */*" forHTTPHeaderField:@"Accept"];

    NSURLSessionDataTask *task = [session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        [session invalidateAndCancel];
        if (error) {
            completion(nil, [NSString stringWithFormat:@"连接失败 (%ld)", (long)error.code]);
            return;
        }
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
        if (![http isKindOfClass:[NSHTTPURLResponse class]]) {
            completion(nil, @"无效响应");
            return;
        }
        if (http.statusCode != 200) {
            if (http.statusCode == 401) {
                completion(nil, @"HTTP 401（链接已失效，需更新）");
            } else {
                completion(nil, [NSString stringWithFormat:@"HTTP %ld", (long)http.statusCode]);
            }
            return;
        }

        NSString *headerVal = nil;
        for (id key in http.allHeaderFields) {
            if ([[key description].lowercaseString isEqualToString:@"subscription-userinfo"]) {
                headerVal = [http.allHeaderFields[key] description];
                break;
            }
        }
        if (headerVal.length == 0) {
            completion(nil, @"响应头无流量信息");
            return;
        }

        TrafficSnapshot *snap = [self parseUserinfo:headerVal providerId:provider.providerId];
        if (!snap) {
            completion(nil, @"流量头解析失败");
            return;
        }
        completion(snap, nil);
    }];
    [task resume];
}

@end
