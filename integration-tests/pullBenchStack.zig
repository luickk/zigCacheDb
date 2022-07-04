const std = @import("std");
const time = std.time;
const mem = std.mem;
const print = std.debug.print;

const test_allocator = std.testing.allocator;
const Allocator = std.mem.Allocator;

const test_utils = @import("utils.zig");

const src = @import("src");
const RemoteCacheInstance = src.RemoteCacheInstance;
const CacheClient = src.CacheClient;
const CacheDataTypes = src.CacheDataTypes;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa_allocator = gpa.allocator();
    defer {
        const leaked = gpa.deinit();
        if (leaked) std.testing.expect(false) catch @panic("TEST FAIL");
    }

    // last two CacheDataType bool are true since the key/ vals are both on the stack, thus not referenced as pointer
    // and as such need different data handling. The branches are comptime  and as such shouldn't have an influence on performance
    const CacheTypes = CacheDataTypes(KeyValGenericFn, u128, u64);

    const test_data_set_size = 50;

    var remote_cache = RemoteCacheInstance(CacheTypes).init(gpa_allocator, 8888);
    defer remote_cache.deinit();

    // "adding" data-set to server by adding it to its local cache (since it's a pull and not a push test...)
    var data_set = try test_utils.createTestSetInt(gpa_allocator, test_data_set_size);
    defer data_set.deinit();
    for (data_set.items) |item| {
        try remote_cache.cache.addKeyVal(item[0], item[1]);
    }

    var remote_cache_thread = try remote_cache.startInstance();
    _ = remote_cache_thread;
    // remote_cache_thread.join();

    time.sleep(time.ns_per_s * 0.1);

    var addr = try std.net.Address.parseIp("127.0.0.1", 8888);
    var client = CacheClient(CacheTypes).init(gpa_allocator, addr);
    defer client.deinit();

    try client.connectToServer();

    var timer = time.Timer.start() catch @panic("need timer to work");
    var all_time: u128 = 0;
    const start_time = timer.read();
    var j: usize = 0;
    for (data_set.items) |item| {
        if (try client.pullValByKey(item[0])) |pull_val| {
            _ = pull_val;
            all_time += timer.read() - all_time;
            j += 1;
        }
    }
    print("avg time per pull(stack based): {d}ns \n", .{(all_time - start_time) / j});
}

fn KeyValGenericFn(comptime KeyType: type, comptime ValType: type) type {
    return struct {

        // If the data contains a pointer and needs memory management, the following fns is required
        // since key/val (in this test)are both purely located on the stack, no allocations or frees are required
        pub fn freeKey(a: Allocator, key: KeyType) void {
            _ = a;
            _ = key;
            // no free
        }

        pub fn freeVal(a: Allocator, val: KeyType) void {
            _ = a;
            _ = val;
            // no free
        }

        pub fn cloneKey(a: Allocator, key: KeyType) !KeyType {
            _ = a;
            return key;
        }

        pub fn cloneVal(a: Allocator, val: ValType) !ValType {
            _ = a;
            return val;
        }

        // for both kinds of data, the fns below are required
        pub fn eql(k1: KeyType, k2: KeyType) bool {
            return k1 == k2;
        }

        pub fn serializeKey(key: KeyType) ![16]u8 {
            var int_buf = [_]u8{0} ** 16;
            mem.writeIntSliceNative(u128, &int_buf, key);
            return int_buf;
        }

        pub fn deserializeKey(key: []u8) !KeyType {
            return mem.readIntNative(u128, key[0..16]);
        }

        pub fn serializeVal(val: ValType) ![8]u8 {
            var int_buf = [_]u8{0} ** 8;
            mem.writeIntSliceNative(u64, &int_buf, val);
            return int_buf;
        }

        pub fn deserializeVal(val: []u8) !ValType {
            return mem.readIntNative(u64, val[0..8]);
        }
    };
}
