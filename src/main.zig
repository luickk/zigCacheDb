const std = @import("std");
const testing = std.testing;
const print = std.debug.print;
const ArrayList = std.ArrayList;
const expect = std.testing.expect;
const mem = std.mem;

const test_allocator = std.testing.allocator;
const Allocator = std.mem.Allocator;

const localCacheErr = error{};

pub fn KeyValPair(comptime KeyType: type, comptime ValType: type) type {
    return struct {
        key: KeyType,
        val: ValType,
    };
}

pub fn LocalCache(comptime EqlMixin: type, comptime KeyType: type, comptime ValType: type) type {
    return struct {
        const Self = @This();

        key_val_store: ArrayList(KeyValPair(KeyType, ValType)),

        fn init(a: Allocator) Self {
            return Self{ .key_val_store = ArrayList(KeyValPair(KeyType, ValType)).init(a) };
        }

        fn deinit(self: *Self) void {
            self.key_val_store.deinit();
        }

        fn addKeyVal(self: *Self, key: KeyType, val: ValType) !void {
            try self.key_val_store.append(KeyValPair(KeyType, ValType){ .key = key, .val = val });
        }

        fn exists(self: *Self, key: KeyType) !bool {
            for (self.key_val_store.items) |key_val| {
                if (EqlMixin.eql(key_val.key, key)) {
                    return true;
                }
            }
            return false;
        }

        fn removeByKey(self: *Self, key: KeyType) !bool {
            for (self.key_val_store.items) |key_val, i| {
                if (EqlMixin.eql(key_val.key, key)) {
                    _ = self.key_val_store.orderedRemove(i);
                    return true;
                }
            }
            return false;
        }

        pub usingnamespace EqlMixin;
    };
}

pub fn RemoteCacheInstance(comptime EqlMixin: type, comptime KeyType: type, comptime ValType: type) type {
    return struct {
        const Self = @This();
        port: u32,
        cache: LocalCache(EqlMixin, KeyType, ValType),

        pub fn init(port: u32) Self {
            return Self{ .port = port, .cache = LocalCache(EqlMixin, KeyType, ValType).init() };
        }
    };
}

fn EqlStr(comptime Ktype: type) type {
    return struct {
        pub fn eql(k1: Ktype, k2: Ktype) bool {
            return mem.eql(u8, k1, k2);
        }
    };
}

test "localCache test" {
    var cache = LocalCache(EqlStr([]const u8), []const u8, []const u8).init(test_allocator);
    defer cache.deinit();

    try expect(!try cache.exists("doesNotExist"));

    try cache.addKeyVal("test1", "testVal");

    try expect(try cache.removeByKey("test1"));

    try expect(!try cache.exists("test1"));
}
