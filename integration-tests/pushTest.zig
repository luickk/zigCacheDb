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

    const CacheTypes = CacheDataTypes(KeyValGenericOperations, []u8, []u8, false, false);

    const test_data_set_size = 50;

    var remote_cache = RemoteCacheInstance(CacheTypes).init(gpa_allocator, 8888);
    defer remote_cache.deinit();

    var remote_cache_thread = try remote_cache.startInstance();
    _ = remote_cache_thread;
    // instance_thread.join();

    time.sleep(time.ns_per_s * 0.1);

    var addr = try std.net.Address.parseIp("127.0.0.1", 8888);
    var client = CacheClient(CacheTypes).init(gpa_allocator, addr);
    defer client.deinit();

    try client.connectToServer();

    var data_set = try test_utils.createTestSetU8(gpa_allocator, test_data_set_size);
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

        // If the data contains a pointer and needs memory management, the following fns is required
        pub fn freeKey(a: Allocator, key: KeyType) void {
            a.free(key);
        }

        pub fn freeVal(a: Allocator, val: ValType) void {
            a.free(val);
        }

        pub fn cloneKey(a: Allocator, key: KeyType) !KeyType {
            var key_clone = try a.alloc(u8, key.len);
            mem.copy(u8, key_clone, key);
            return key_clone;
        }

        pub fn cloneVal(a: Allocator, val: ValType) !ValType {
            var val_clone = try a.alloc(u8, val.len);
            mem.copy(u8, val_clone, val);
            return val_clone;
        }

        // for both kinds of data, the fns below are required
        pub fn eql(k1: KeyType, k2: KeyType) bool {
            return mem.eql(u8, k1, k2);
        }

        pub fn serializeKey(key: KeyType) ![]u8 {
            return key;
        }

        pub fn deserializeKey(key: []u8) !KeyType {
            return key;
        }

        pub fn serializeVal(val: ValType) ![]u8 {
            return val;
        }

        pub fn deserializeVal(val: []u8) !ValType {
            return val;
        }
    };
}
