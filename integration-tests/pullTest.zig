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

pub fn main() !void {
    var remote_cache = RemoteCacheInstance(KeyValGenericOperations([]u8, []u8), []u8, []u8).init(test_allocator, 8888);
    defer remote_cache.deinit();

    for ((try test_utils.createTestSet(test_allocator, 50)).items) |*item| {
        var tset_key_a: []u8 = try test_allocator.alloc(u8, item[0][0..].len);
        var tset_val_a: []u8 = try test_allocator.alloc(u8, item[1][0..].len);
        mem.copy(u8, tset_key_a, item[0][0..]);
        mem.copy(u8, tset_val_a, item[1][0..]);
        try remote_cache.cache.addKeyVal(tset_key_a, tset_val_a);
    }

    var remote_cache_thread = try remote_cache.startInstance();
    _ = remote_cache_thread;
    // remote_cache_thread.join();

    time.sleep(time.ns_per_s * 0.1);

    var addr = try std.net.Address.parseIp("127.0.0.1", 8888);
    var client = CacheClient(KeyValGenericOperations([]u8, []u8), []u8, []u8).init(test_allocator, addr);
    defer client.deinit();

    try client.connectToServer();
    print("---------- PULL integration test ----------  \n", .{});
    print("client connected \n", .{});

    for ((try test_utils.createTestSet(test_allocator, 50)).items) |*item, i| {
        var pull_val = (try client.pullValByKey(item[0][0..])) orelse {
            print("pull test failed(val not correct) \n", .{});
            break;
        };
        if (!mem.eql(u8, pull_val, item[1][0..])) {
            print("pull test failed \n", .{});
            break;
        }
        if (i == 49) {
            print("pull test successfull \n", .{});
        }
    }
    print("---------- PULL integration test ----------  \n", .{});
}

fn KeyValGenericOperations(comptime KeyType: type, comptime ValType: type) type {
    return struct {
        pub fn eql(k1: anytype, k2: anytype) bool {
            return mem.eql(u8, k1, k2);
        }

        pub fn freeKey(a: Allocator, key: anytype) void {
            a.free(key);
        }

        pub fn freeVal(a: Allocator, val: anytype) void {
            a.free(val);
        }

        // must NOT be alloce; free is not invoked
        pub fn serializeKey(key: KeyType) []u8 {
            return key;
        }

        // ! MUST allocate on heap if not static size or type !!
        pub fn deserializeKey(a: Allocator, key: []u8) !KeyType {
            var alloced_key = try a.alloc(u8, key.len);
            std.mem.copy(u8, alloced_key, key);
            return alloced_key;
        }

        // must NOT be alloce; free is not invoked
        pub fn serializeVal(val: ValType) []u8 {
            return val;
        }

        // ! MUST allocate on heap if not static size(array) or type !!
        pub fn deserializeVal(a: Allocator, val: []u8) !ValType {
            var alloced_val = try a.alloc(u8, val.len);
            std.mem.copy(u8, alloced_val, val);
            return alloced_val;
        }
    };
}
