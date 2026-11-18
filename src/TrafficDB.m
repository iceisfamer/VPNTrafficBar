#import "TrafficDB.h"
#import <sqlite3.h>

@implementation TrafficSnapshot
- (int64_t)used { return self.upload + self.download; }
- (int64_t)remaining {
    int64_t rem = self.total - self.used;
    return rem > 0 ? rem : 0;
}
@end

@implementation DailyUsageItem
@end

@interface TrafficDB () {
    sqlite3 *_db;
}
@property (nonatomic, strong) dispatch_queue_t queue;
@end

@implementation TrafficDB

- (nullable instancetype)initWithPath:(NSString *)path {
    self = [super init];
    if (!self) return nil;
    _queue = dispatch_queue_create("com.vpntrafficbar.db", DISPATCH_QUEUE_SERIAL);
    NSString *dir = [path stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];

    if (sqlite3_open(path.UTF8String, &_db) != SQLITE_OK) {
        return nil;
    }
    const char *sql =
        "CREATE TABLE IF NOT EXISTS snapshots ("
        "  id INTEGER PRIMARY KEY AUTOINCREMENT,"
        "  provider_id TEXT NOT NULL,"
        "  timestamp REAL NOT NULL,"
        "  upload INTEGER NOT NULL,"
        "  download INTEGER NOT NULL,"
        "  total INTEGER NOT NULL,"
        "  expire REAL"
        ");"
        "CREATE INDEX IF NOT EXISTS idx_snapshots_provider_ts ON snapshots(provider_id, timestamp);"
        "CREATE TABLE IF NOT EXISTS local_hourly ("
        "  hour_ts INTEGER NOT NULL,"
        "  provider_id TEXT NOT NULL,"
        "  bytes INTEGER NOT NULL DEFAULT 0,"
        "  PRIMARY KEY(hour_ts, provider_id)"
        ");";
    sqlite3_exec(_db, sql, NULL, NULL, NULL);
    return self;
}

- (void)dealloc {
    if (_db) sqlite3_close(_db);
}

- (void)insertSnapshot:(TrafficSnapshot *)snap {
    dispatch_sync(self.queue, ^{
        const char *sql = "INSERT INTO snapshots (provider_id, timestamp, upload, download, total, expire) VALUES (?, ?, ?, ?, ?, ?);";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) != SQLITE_OK) return;
        sqlite3_bind_text(stmt, 1, snap.providerId.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_double(stmt, 2, snap.timestamp.timeIntervalSince1970);
        sqlite3_bind_int64(stmt, 3, snap.upload);
        sqlite3_bind_int64(stmt, 4, snap.download);
        sqlite3_bind_int64(stmt, 5, snap.total);
        if (snap.expire) {
            sqlite3_bind_double(stmt, 6, snap.expire.timeIntervalSince1970);
        } else {
            sqlite3_bind_null(stmt, 6);
        }
        sqlite3_step(stmt);
        sqlite3_finalize(stmt);
    });
}

- (TrafficSnapshot *)rowToSnapshot:(sqlite3_stmt *)stmt {
    TrafficSnapshot *s = [[TrafficSnapshot alloc] init];
    const unsigned char *pid = sqlite3_column_text(stmt, 0);
    s.providerId = pid ? [NSString stringWithUTF8String:(const char *)pid] : @"";
    s.timestamp = [NSDate dateWithTimeIntervalSince1970:sqlite3_column_double(stmt, 1)];
    s.upload = sqlite3_column_int64(stmt, 2);
    s.download = sqlite3_column_int64(stmt, 3);
    s.total = sqlite3_column_int64(stmt, 4);
    if (sqlite3_column_type(stmt, 5) != SQLITE_NULL) {
        s.expire = [NSDate dateWithTimeIntervalSince1970:sqlite3_column_double(stmt, 5)];
    }
    return s;
}

- (nullable TrafficSnapshot *)latestSnapshotForProvider:(NSString *)providerId {
    __block TrafficSnapshot *res = nil;
    dispatch_sync(self.queue, ^{
        const char *sql = "SELECT provider_id, timestamp, upload, download, total, expire FROM snapshots WHERE provider_id = ? ORDER BY timestamp DESC LIMIT 1;";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) != SQLITE_OK) return;
        sqlite3_bind_text(stmt, 1, providerId.UTF8String, -1, SQLITE_TRANSIENT);
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            res = [self rowToSnapshot:stmt];
        }
        sqlite3_finalize(stmt);
    });
    return res;
}

- (NSArray<TrafficSnapshot *> *)snapshotsForProvider:(NSString *)providerId since:(NSDate *)since {
    NSMutableArray<TrafficSnapshot *> *arr = [NSMutableArray array];
    dispatch_sync(self.queue, ^{
        const char *sql = "SELECT provider_id, timestamp, upload, download, total, expire FROM snapshots WHERE provider_id = ? AND timestamp >= ? ORDER BY timestamp ASC;";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) != SQLITE_OK) return;
        sqlite3_bind_text(stmt, 1, providerId.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_double(stmt, 2, since.timeIntervalSince1970);
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            [arr addObject:[self rowToSnapshot:stmt]];
        }
        sqlite3_finalize(stmt);
    });
    return arr;
}

- (nullable TrafficSnapshot *)lastSnapshotForProvider:(NSString *)providerId before:(NSDate *)before {
    __block TrafficSnapshot *res = nil;
    dispatch_sync(self.queue, ^{
        const char *sql = "SELECT provider_id, timestamp, upload, download, total, expire FROM snapshots WHERE provider_id = ? AND timestamp < ? ORDER BY timestamp DESC LIMIT 1;";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) != SQLITE_OK) return;
        sqlite3_bind_text(stmt, 1, providerId.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_double(stmt, 2, before.timeIntervalSince1970);
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            res = [self rowToSnapshot:stmt];
        }
        sqlite3_finalize(stmt);
    });
    return res;
}

- (int64_t)usageForProvider:(NSString *)providerId since:(NSDate *)since {
    TrafficSnapshot *baseline = [self lastSnapshotForProvider:providerId before:since];
    NSArray<TrafficSnapshot *> *window = [self snapshotsForProvider:providerId since:since];
    NSMutableArray<TrafficSnapshot *> *series = [NSMutableArray array];
    if (baseline) [series addObject:baseline];
    [series addObjectsFromArray:window];
    if (series.count < 2) return 0;

    int64_t total = 0;
    for (NSUInteger i = 1; i < series.count; i++) {
        int64_t prev = series[i - 1].used;
        int64_t curr = series[i].used;
        total += (curr >= prev) ? (curr - prev) : curr;
    }
    return total;
}

- (NSArray<DailyUsageItem *> *)dailyUsage7DaysForProvider:(NSString *)providerId now:(NSDate *)now {
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDate *todayStart = [cal startOfDayForDate:now];
    NSDate *sevenDaysAgo = [cal dateByAddingUnit:NSCalendarUnitDay value:-6 toDate:todayStart options:0];

    TrafficSnapshot *baseline = [self lastSnapshotForProvider:providerId before:sevenDaysAgo];
    NSArray<TrafficSnapshot *> *window = [self snapshotsForProvider:providerId since:sevenDaysAgo];
    NSMutableArray<TrafficSnapshot *> *series = [NSMutableArray array];
    if (baseline) [series addObject:baseline];
    [series addObjectsFromArray:window];

    NSMutableDictionary<NSDate *, NSNumber *> *buckets = [NSMutableDictionary dictionary];
    NSMutableArray<NSDate *> *orderedDays = [NSMutableArray array];
    for (NSInteger offset = 0; offset < 7; offset++) {
        NSDate *d = [cal dateByAddingUnit:NSCalendarUnitDay value:offset toDate:sevenDaysAgo options:0];
        if (d) {
            buckets[d] = @(0);
            [orderedDays addObject:d];
        }
    }

    if (series.count >= 2) {
        for (NSUInteger i = 1; i < series.count; i++) {
            int64_t prev = series[i - 1].used;
            int64_t curr = series[i].used;
            int64_t delta = (curr >= prev) ? (curr - prev) : curr;
            NSDate *day = [cal startOfDayForDate:series[i].timestamp];
            if (buckets[day]) {
                buckets[day] = @(buckets[day].longLongValue + MAX(0, delta));
            }
        }
    }

    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"MM/dd";

    NSMutableArray<DailyUsageItem *> *out = [NSMutableArray array];
    for (NSDate *day in orderedDays) {
        DailyUsageItem *item = [[DailyUsageItem alloc] init];
        item.date = day;
        item.label = [cal isDateInToday:day] ? @"今天" : [fmt stringFromDate:day];
        item.bytes = buckets[day].longLongValue;
        [out addObject:item];
    }
    return out;
}

#pragma mark - Local Clash Hourly Tracking

- (void)addLocalBytes:(int64_t)bytes forProvider:(NSString *)providerId atDate:(NSDate *)date {
    if (bytes <= 0 || providerId.length == 0) return;
    int64_t ts = (int64_t)[date timeIntervalSince1970];
    int64_t hourTs = (ts / 3600) * 3600;
    dispatch_sync(self.queue, ^{
        const char *sql =
            "INSERT INTO local_hourly (hour_ts, provider_id, bytes) VALUES (?, ?, ?) "
            "ON CONFLICT(hour_ts, provider_id) DO UPDATE SET bytes = bytes + excluded.bytes;";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) != SQLITE_OK) return;
        sqlite3_bind_int64(stmt, 1, hourTs);
        sqlite3_bind_text(stmt, 2, providerId.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_int64(stmt, 3, bytes);
        sqlite3_step(stmt);
        sqlite3_finalize(stmt);
    });
}

- (int64_t)localUsageForProvider:(NSString *)providerId since:(NSDate *)since {
    int64_t sinceHour = ((int64_t)[since timeIntervalSince1970] / 3600) * 3600;
    __block int64_t sum = 0;
    dispatch_sync(self.queue, ^{
        const char *sql = "SELECT COALESCE(SUM(bytes), 0) FROM local_hourly WHERE provider_id = ? AND hour_ts >= ?;";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) != SQLITE_OK) return;
        sqlite3_bind_text(stmt, 1, providerId.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_int64(stmt, 2, sinceHour);
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            sum = sqlite3_column_int64(stmt, 0);
        }
        sqlite3_finalize(stmt);
    });
    return sum;
}

- (NSArray<DailyUsageItem *> *)localDailyUsage7DaysForProvider:(NSString *)providerId now:(NSDate *)now {
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDate *todayStart = [cal startOfDayForDate:now];
    NSDate *sevenDaysAgo = [cal dateByAddingUnit:NSCalendarUnitDay value:-6 toDate:todayStart options:0];
    int64_t sinceTs = (int64_t)[sevenDaysAgo timeIntervalSince1970];

    NSMutableDictionary<NSDate *, NSNumber *> *buckets = [NSMutableDictionary dictionary];
    NSMutableArray<NSDate *> *orderedDays = [NSMutableArray array];
    for (NSInteger offset = 0; offset < 7; offset++) {
        NSDate *d = [cal dateByAddingUnit:NSCalendarUnitDay value:offset toDate:sevenDaysAgo options:0];
        if (d) {
            buckets[d] = @(0);
            [orderedDays addObject:d];
        }
    }

    dispatch_sync(self.queue, ^{
        const char *sql = "SELECT hour_ts, bytes FROM local_hourly WHERE provider_id = ? AND hour_ts >= ?;";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) != SQLITE_OK) return;
        sqlite3_bind_text(stmt, 1, providerId.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_int64(stmt, 2, sinceTs);
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            int64_t hTs = sqlite3_column_int64(stmt, 0);
            int64_t b = sqlite3_column_int64(stmt, 1);
            NSDate *day = [cal startOfDayForDate:[NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)hTs]];
            if (buckets[day]) {
                buckets[day] = @(buckets[day].longLongValue + MAX(0, b));
            }
        }
        sqlite3_finalize(stmt);
    });

    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"MM/dd";

    NSMutableArray<DailyUsageItem *> *out = [NSMutableArray array];
    for (NSDate *day in orderedDays) {
        DailyUsageItem *item = [[DailyUsageItem alloc] init];
        item.date = day;
        item.label = [cal isDateInToday:day] ? @"今天" : [fmt stringFromDate:day];
        item.bytes = buckets[day].longLongValue;
        [out addObject:item];
    }
    return out;
}

@end
