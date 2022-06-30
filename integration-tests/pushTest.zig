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
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa_allocator = gpa.allocator();
    defer {
        const leaked = gpa.deinit();
        if (leaked) std.testing.expect(false) catch @panic("TEST FAIL");
    }

    const test_data_set_size = 50;

    var remote_cache = RemoteCacheInstance(KeyValGenericOperations([]u8, []u8), []u8, []u8).init(gpa_allocator, 8888);
    defer remote_cache.deinit();

    var remote_cache_thread = try remote_cache.startInstance();
    _ = remote_cache_thread;
    // instance_thread.join();

    time.sleep(time.ns_per_s * 0.1);

    var addr = try std.net.Address.parseIp("127.0.0.1", 8888);
    var client = CacheClient(KeyValGenericOperations([]u8, []u8), []u8, []u8).init(gpa_allocator, addr);
    defer client.deinit();

    try client.connectToServer();

    var data_set = try test_utils.createTestSet(gpa_allocator, test_data_set_size);
    defer data_set.deinit();
    for (data_set.items) |*item, i| {
        try client.pushKeyVal(item[0][0..], item[1][0..]);
        if (i == test_data_set_size - 1) {
            // push twice on last iter
            try client.pushKeyVal(item[0][0..], item[1][0..]);
        }
    }

    time.sleep(time.ns_per_s * 0.5);

    if (remote_cache.cache.getNKeyVal() == test_data_set_size) {
        print("- push test successfull \n", .{});
        return;
    } else {
        print("- push test failed \n", .{});
        return;
    }
    return;
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

        // ! must NOT allocate on heap; free is not invoked !!
        pub fn tempDeserializeKey(key: []u8) KeyType {
            return key;
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
