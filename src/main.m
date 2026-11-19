#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>
#import "TrafficDB.h"
#import "Fetcher.h"
#import "DashboardHTML.h"
#import "LocalClashTracker.h"

@interface AppDelegate : NSObject <NSApplicationDelegate, WKScriptMessageHandler, WKNavigationDelegate>
@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, strong) NSPopover *popover;
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) AppConfig *config;
@property (nonatomic, strong) TrafficDB *db;
@property (nonatomic, strong) LocalClashTracker *localTracker;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *healthByProvider;
@property (nonatomic, strong) NSDate *lastRefreshTime;
@property (nonatomic, assign) BOOL isRefreshing;
@property (nonatomic, assign) BOOL webLoaded;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];

    self.config = [AppConfig loadOrSeed];
    self.db = [[TrafficDB alloc] initWithPath:[AppConfig databasePath]];
    self.healthByProvider = [NSMutableDictionary dictionary];

    // Setup Status Bar Item (icon-only)
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    NSImage *icon = [NSImage imageWithSystemSymbolName:@"chart.bar.fill" accessibilityDescription:@"VPN 流量监控"];
    [icon setTemplate:YES];
    self.statusItem.button.image = icon;
    self.statusItem.button.title = @"";
    self.statusItem.button.toolTip = @"VPN 流量监控";
    self.statusItem.button.target = self;
    self.statusItem.button.action = @selector(togglePopover:);

    // Setup Popover + WKWebView
    WKWebViewConfiguration *wkCfg = [[WKWebViewConfiguration alloc] init];
    [wkCfg.userContentController addScriptMessageHandler:self name:@"bridge"];

    self.webView = [[WKWebView alloc] initWithFrame:NSMakeRect(0, 0, 390, 560) configuration:wkCfg];
    self.webView.navigationDelegate = self;
    [self.webView setValue:@NO forKey:@"drawsBackground"];
    [self.webView loadHTMLString:[DashboardHTML htmlTemplate] baseURL:nil];

    NSViewController *vc = [[NSViewController alloc] init];
    vc.view = self.webView;

    self.popover = [[NSPopover alloc] init];
    self.popover.contentSize = NSMakeSize(390, 560);
    self.popover.behavior = NSPopoverBehaviorTransient;
    self.popover.contentViewController = vc;

    [self updateMenuBarTitle];
    [self scheduleTimer];
    [self refreshAll];

    __weak typeof(self) weakSelf = self;
    self.localTracker = [[LocalClashTracker alloc] initWithDB:self.db providersProvider:^NSArray<VPNProviderConfig *> *{
        return weakSelf.config.providers ?: @[];
    }];
    [self.localTracker start];
}

- (void)togglePopover:(id)sender {
    if (self.popover.isShown) {
        [self.popover performClose:sender];
    } else {
        [self pushStateToWebView];
        [self.popover showRelativeToRect:self.statusItem.button.bounds
                                  ofView:self.statusItem.button
                           preferredEdge:NSRectEdgeMinY];
        [NSApp activateIgnoringOtherApps:YES];
    }
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    self.webLoaded = YES;
    [self pushStateToWebView];
}

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message {
    if (![message.body isKindOfClass:[NSDictionary class]]) return;
    NSString *action = message.body[@"action"];
    NSDictionary *payload = message.body[@"payload"];

    if ([action isEqualToString:@"refresh"]) {
        [self refreshAll];
    } else if ([action isEqualToString:@"saveConfig"] && [payload isKindOfClass:[NSDictionary class]]) {
        self.config = [AppConfig fromDictionary:payload];
        [self.config save];
        [self scheduleTimer];
        [self refreshAll];
    } else if ([action isEqualToString:@"quit"]) {
        [NSApp terminate:nil];
    }
}

- (void)scheduleTimer {
    [self.timer invalidate];
    self.timer = nil;
    if (self.config.refreshIntervalMinutes <= 0) {
        return;
    }
    NSTimeInterval interval = self.config.refreshIntervalMinutes * 60.0;
    self.timer = [NSTimer scheduledTimerWithTimeInterval:interval
                                                  target:self
                                                selector:@selector(refreshAll)
                                                userInfo:nil
                                                 repeats:YES];
}

- (void)refreshAll {
    if (self.isRefreshing) return;
    self.isRefreshing = YES;
    [self pushStateToWebView];

    NSMutableArray<VPNProviderConfig *> *enabled = [NSMutableArray array];
    for (VPNProviderConfig *p in self.config.providers) {
        if (p.enabled) [enabled addObject:p];
    }

    if (enabled.count == 0) {
        self.isRefreshing = NO;
        self.lastRefreshTime = [NSDate date];
        [self updateMenuBarTitle];
        [self pushStateToWebView];
        return;
    }

    dispatch_group_t grp = dispatch_group_create();
    NSString *proxyHost = self.config.proxyHost;
    NSInteger proxyPort = self.config.proxyPort;

    for (VPNProviderConfig *prov in enabled) {
        dispatch_group_enter(grp);
        [SubscriptionFetcher fetchProvider:prov
                                   proxyHost:proxyHost
                                   proxyPort:proxyPort
                                  completion:^(TrafficSnapshot *snap, NSString *errMsg) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (snap) {
                    [self.db insertSnapshot:snap];
                    self.healthByProvider[prov.providerId] = @"ok";
                } else {
                    self.healthByProvider[prov.providerId] = errMsg ?: @"错误";
                }
                dispatch_group_leave(grp);
            });
        }];
    }

    dispatch_group_notify(grp, dispatch_get_main_queue(), ^{
        self.isRefreshing = NO;
        self.lastRefreshTime = [NSDate date];
        [self updateMenuBarTitle];
        [self pushStateToWebView];
    });
}

- (NSString *)compactBytes:(int64_t)bytes {
    double gb = (double)bytes / 1073741824.0;
    if (gb >= 100.0) return [NSString stringWithFormat:@"%.0fG", gb];
    if (gb >= 1.0) return [NSString stringWithFormat:@"%.1fG", gb];
    if (bytes <= 0) return @"0G";
    double mb = (double)bytes / 1048576.0;
    return [NSString stringWithFormat:@"%.0fM", mb];
}

- (void)updateMenuBarTitle {
    NSDate *now = [NSDate date];
    NSDate *since24h = [now dateByAddingTimeInterval:-86400.0];

    NSMutableArray<VPNProviderConfig *> *enabled = [NSMutableArray array];
    for (VPNProviderConfig *p in self.config.providers) {
        if (p.enabled) [enabled addObject:p];
    }

    if (self.config.primaryProviderId.length > 0) {
        for (VPNProviderConfig *p in enabled) {
            if ([p.providerId isEqualToString:self.config.primaryProviderId]) {
                TrafficSnapshot *snap = [self.db latestSnapshotForProvider:p.providerId];
                if (snap) {
                    int64_t u24 = [self.db usageForProvider:p.providerId since:since24h];
                    self.statusItem.button.title = @"";
                    self.statusItem.button.toolTip = [NSString stringWithFormat:@"%@ 余 %@ · 24h %@",
                        p.name, [self compactBytes:snap.remaining], [self compactBytes:u24]];
                    return;
                }
            }
        }
    }

    int64_t totalRem = 0;
    int64_t total24h = 0;
    BOOL any = NO;
    for (VPNProviderConfig *p in enabled) {
        TrafficSnapshot *snap = [self.db latestSnapshotForProvider:p.providerId];
        if (snap) {
            any = YES;
            totalRem += snap.remaining;
            total24h += [self.db usageForProvider:p.providerId since:since24h];
        }
    }

    self.statusItem.button.title = @"";
    if (any) {
        self.statusItem.button.toolTip = [NSString stringWithFormat:@"余 %@ · 24h %@",
            [self compactBytes:totalRem], [self compactBytes:total24h]];
    } else {
        self.statusItem.button.toolTip = @"VPN 流量监控";
    }
}

- (void)pushStateToWebView {
    if (!self.webLoaded) return;

    NSDate *now = [NSDate date];
    NSDate *since24h = [now dateByAddingTimeInterval:-86400.0];
    NSDate *dayStart = [[NSCalendar currentCalendar] startOfDayForDate:now];

    NSDateFormatter *expFmt = [[NSDateFormatter alloc] init];
    expFmt.dateFormat = @"yyyy/MM/dd";

    NSDateFormatter *timeFmt = [[NSDateFormatter alloc] init];
    timeFmt.dateFormat = @"HH:mm";

    NSMutableArray *statusesJSON = [NSMutableArray array];
    NSMutableArray<NSNumber *> *allDailySums = [NSMutableArray arrayWithObjects:@0,@0,@0,@0,@0,@0,@0, nil];
    NSMutableArray<NSNumber *> *allLocalDailySums = [NSMutableArray arrayWithObjects:@0,@0,@0,@0,@0,@0,@0, nil];
    NSArray<DailyUsageItem *> *templateDays = nil;

    for (VPNProviderConfig *p in self.config.providers) {
        if (!p.enabled) continue;
        TrafficSnapshot *snap = [self.db latestSnapshotForProvider:p.providerId];
        int64_t u24 = [self.db usageForProvider:p.providerId since:since24h];
        int64_t uToday = [self.db usageForProvider:p.providerId since:dayStart];
        NSArray<DailyUsageItem *> *d7 = [self.db dailyUsage7DaysForProvider:p.providerId now:now];

        int64_t lu24 = [self.db localUsageForProvider:p.providerId since:since24h];
        int64_t luToday = [self.db localUsageForProvider:p.providerId since:dayStart];
        NSArray<DailyUsageItem *> *ld7 = [self.db localDailyUsage7DaysForProvider:p.providerId now:now];

        int64_t effective24h = MAX(u24, lu24);
        int64_t effectiveToday = MAX(uToday, luToday);

        if (!templateDays) templateDays = d7;

        NSMutableArray *d7JSON = [NSMutableArray array];
        for (NSUInteger i = 0; i < d7.count; i++) {
            int64_t rBytes = d7[i].bytes;
            int64_t lBytes = (i < ld7.count) ? ld7[i].bytes : 0;
            int64_t merged = MAX(rBytes, lBytes);
            if (i < allDailySums.count) {
                allDailySums[i] = @(allDailySums[i].longLongValue + merged);
            }
            [d7JSON addObject:@{ @"label": d7[i].label, @"bytes": @(merged) }];
        }

        NSMutableArray *ld7JSON = [NSMutableArray array];
        for (NSUInteger i = 0; i < ld7.count; i++) {
            DailyUsageItem *item = ld7[i];
            if (i < allLocalDailySums.count) {
                allLocalDailySums[i] = @(allLocalDailySums[i].longLongValue + item.bytes);
            }
            [ld7JSON addObject:@{ @"label": item.label, @"bytes": @(item.bytes) }];
        }

        NSString *rawHealth = self.healthByProvider[p.providerId] ?: (snap ? @"ok" : @"pending");
        BOOL isEstimated = NO;
        int64_t localSinceSnap = 0;
        if (snap && ![rawHealth isEqualToString:@"ok"] && lu24 > 0) {
            isEstimated = YES;
            localSinceSnap = [self.db localUsageForProvider:p.providerId since:snap.timestamp];
        }

        NSMutableDictionary *st = [NSMutableDictionary dictionary];
        st[@"id"] = p.providerId;
        st[@"name"] = p.name;
        st[@"health"] = isEstimated ? @"local_est" : rawHealth;
        st[@"usage24h"] = @(effective24h);
        st[@"usageToday"] = @(effectiveToday);
        st[@"daily7d"] = d7JSON;
        st[@"local24h"] = @(lu24);
        st[@"localToday"] = @(luToday);
        st[@"localDaily7d"] = ld7JSON;

        if (snap) {
            int64_t estUsed = MIN(snap.total, snap.used + localSinceSnap);
            int64_t estRem = MAX(0, snap.total - estUsed);
            NSMutableDictionary *latestDict = [NSMutableDictionary dictionaryWithDictionary:@{
                @"used": @(estUsed),
                @"remaining": @(estRem),
                @"total": @(snap.total),
            }];
            if (snap.expire) {
                latestDict[@"expireLabel"] = [expFmt stringFromDate:snap.expire];
            }
            st[@"latest"] = latestDict;
        }
        [statusesJSON addObject:st];
    }

    NSMutableArray *allDailyJSON = [NSMutableArray array];
    NSMutableArray *allLocalDailyJSON = [NSMutableArray array];
    if (templateDays) {
        for (NSUInteger i = 0; i < templateDays.count; i++) {
            [allDailyJSON addObject:@{
                @"label": templateDays[i].label,
                @"bytes": allDailySums[i]
            }];
            [allLocalDailyJSON addObject:@{
                @"label": templateDays[i].label,
                @"bytes": allLocalDailySums[i]
            }];
        }
    }

    NSDictionary *state = @{
        @"isRefreshing": @(self.isRefreshing),
        @"lastRefreshLabel": self.lastRefreshTime ? [timeFmt stringFromDate:self.lastRefreshTime] : @"",
        @"config": [self.config toDictionary],
        @"statuses": statusesJSON,
        @"allDaily7d": allDailyJSON,
        @"allLocalDaily7d": allLocalDailyJSON
    };

    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:state options:0 error:nil];
    if (!jsonData) return;
    NSString *jsonStr = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    NSString *js = [NSString stringWithFormat:@"window.updateState(%@);", jsonStr];
    [self.webView evaluateJavaScript:js completionHandler:nil];
}

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
