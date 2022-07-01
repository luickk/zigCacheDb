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

    comptime var KeyType: type = u128;
    comptime var ValType: type = u64;

    const test_data_set_size = 50;

    var remote_cache = RemoteCacheInstance(KeyValGenericOperations(KeyType, ValType), KeyType, ValType).init(gpa_allocator, 8888);
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
    var client = CacheClient(KeyValGenericOperations(KeyType, ValType), KeyType, ValType).init(gpa_allocator, addr);
    defer client.deinit();

    try client.connectToServer();

    var i_c: usize = 0;

    for (data_set.items) |item, i| {
        if (try client.pullValByKey(item[0])) |pull_val| {
            if (pull_val != item[1]) {
                print("- on stack p/pull test failed(val not correct) \n", .{});
                return;
            }
            KeyValGenericOperations(KeyType, ValType).freeVal(client.a, pull_val);
        } else {
            print("- on stack p/pull test failed \n", .{});
            return;
        }

        // pulling same key twice on last iteration
        if (i == test_data_set_size - 1) {
            if (try client.pullValByKey(item[0])) |pull_val| {
                if (pull_val != item[1]) {
                    print("- on stack p/pull test failed(val not correct) \n", .{});
                    return;
                }
                KeyValGenericOperations(KeyType, ValType).freeVal(client.a, pull_val);
            } else {
                print("- on stack p/pull test failed \n", .{});
                return;
            }
        }
        i_c = i;
    }

    if ((try client.pullValByKey(test_data_set_size + 1)) != null) {
        print("- on stack p/pull test failed (key that shouldn't exist, exists) \n", .{});
        return;
    }

    if (i_c == test_data_set_size - 1) {
        print("- on stack p/pull test successfull \n", .{});
        return;
    }
}

fn KeyValGenericOperations(comptime KeyType: type, comptime ValType: type) type {
    return struct {

        // If the data contains a pointer and needs memory management, the following fns is required
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

        // if the data is kept on the stack and copied around, the following fns are required
        pub fn keyRawToSlice(key_arr: *[16]u8) []u8 {
            return key_arr;
        }

        pub fn valRawToSlice(val_arr: *[8]u8) []u8 {
            return val_arr;
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
            return &int_buf;
        }

        pub fn deserializeVal(val: []u8) !ValType {
            return mem.readIntNative(u64, val[0..8]);
        }
    };
}
