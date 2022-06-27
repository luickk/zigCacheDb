const std = @import("std");
const utils = @import("utils.zig");
const time = std.time;
const mem = std.mem;
const print = std.debug.print;
const test_allocator = std.testing.allocator;
const Allocator = std.mem.Allocator;
const native_endian = @import("builtin").target.cpu.arch.endian();

const RemoteCacheInstance = @import("RemoteCacheInstance.zig").RemoteCacheInstance;
const CacheClient = @import("CacheClient.zig").CacheClient;

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

pub fn main() !void {
    var server_thread = try std.Thread.spawn(.{}, serverTest, .{});

    time.sleep(time.ns_per_s * 0.1);

    var addr = try std.net.Address.parseIp("127.0.0.1", 8888);
    var client = CacheClient(KeyValGenericOperations(), []u8, []u8).init(test_allocator, addr);
    defer client.deinit();

    try client.connectToServer();
    print("client connected \n", .{});

    // pragmatic
    var key = "test-00000000000000000000".*;
    var val = "123456789".*;

    var i: u16 = 0;
    while (i < 500) : (i += 1) {
        mem.copy(u8, key[5..], &utils.uitoa(i));
        _ = i;
        try client.pushKeyVal(&key, &val);
        // time.sleep(time.ns_per_s * 0.1);
    }
    print("keys pushed \n", .{});

    server_thread.join();
    print("server thread joined \n", .{});
}

fn serverTest() void {
    var server = RemoteCacheInstance(KeyValGenericOperations(), []u8, []u8).init(test_allocator, 8888);
    defer server.deinit();

    _ = std.Thread.spawn(.{}, serverCacheMonitor, .{&server}) catch {
        print("serverCacheMonitor error \n", .{});
    };
    print("cache monitor started \n", .{});

    print("cache instance started \n", .{});
    server.startInstance() catch unreachable;
}

fn serverCacheMonitor(server: *RemoteCacheInstance(KeyValGenericOperations(), []u8, []u8)) void {
    while (true) {
        time.sleep(time.ns_per_s * 5);
        server.debugPrintLocalCache();
        break;
    }
}
