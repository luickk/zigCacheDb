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
    var remote_cache = RemoteCacheInstance(KeyValGenericOperations(), []u8, []u8).init(test_allocator, 8888);
    defer remote_cache.deinit();

    var remote_cache_thread = try remote_cache.startInstance();
    _ = remote_cache_thread;
    // instance_thread.join();

    time.sleep(time.ns_per_s * 0.1);

    var addr = try std.net.Address.parseIp("127.0.0.1", 8888);
    var client = CacheClient(KeyValGenericOperations(), []u8, []u8).init(test_allocator, addr);
    defer client.deinit();

    try client.connectToServer();
    print("---------- PUSH integration test ----------  \n", .{});
    print("client connected \n", .{});

    for ((try test_utils.createTestSet(test_allocator, 50)).items) |item| {
        var key = item[0][0..].*;
        var val = item[1][0..].*;
        try client.pushKeyVal(&key, &val);
    }
    print("keys pushed \n", .{});

    time.sleep(time.ns_per_s * 0.5);

    if (remote_cache.cache.getNKeyVal() == 50) {
        print("push test successfull \n", .{});
    } else {
        print("push test failed \n", .{});
    }
    print("---------- PUSH integration test ----------  \n", .{});
    return;
}

fn KeyValGenericOperations() type {
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

        pub fn serializeKey(key: anytype) []u8 {
            return key;
        }

        pub fn deserializeKey(key: anytype) []u8 {
            return key;
        }

        pub fn serializeVal(val: anytype) []u8 {
            return val;
        }

        pub fn deserializeVal(val: anytype) []u8 {
            return val;
        }
    };
}
