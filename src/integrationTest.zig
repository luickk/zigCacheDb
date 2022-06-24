const std = @import("std");
const mem = std.mem;
const print = std.debug.print;
const test_allocator = std.testing.allocator;

const RemoteCacheInstance = @import("RemoteCacheInstance.zig").RemoteCacheInstance;
const CacheClient = @import("CacheClient.zig").CacheClient;

fn KeyValGenericOperations() type {
    return struct {
        pub fn eql(k1: anytype, k2: anytype) bool {
            return mem.eql(u8, k1, k2);
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

    std.time.sleep(50000);

    var addr = try std.net.Address.parseIp("127.0.0.1", 8888);
    var client = CacheClient(KeyValGenericOperations(), []u8, []u8).init(test_allocator, addr);
    defer client.deinit();

    try client.connectToServer();
    print("client connected \n", .{});

    var key = "test".*;
    var val = "123456789".*;
    try client.pushKeyVal(&key, &val);
    print("key pushed \n", .{});

    server_thread.join();
    print("server thread joined \n", .{});
}

fn serverTest() void {
    var server = RemoteCacheInstance(KeyValGenericOperations(), []u8, []u8).init(test_allocator, 8888);
    defer server.deinit();

    print("cache instance started \n", .{});
    server.startInstance() catch unreachable;
}
