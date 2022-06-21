const std = @import("std");
const testing = std.testing;
const print = std.debug.print;
const ArrayList = std.ArrayList;
const expect = std.testing.expect;
const mem = std.mem;
const Mutex = std.Thread.Mutex;
const net = std.net;

const test_allocator = std.testing.allocator;
const Allocator = std.mem.Allocator;

const localCacheErr = error{};

pub fn KeyValPair(KeyType: anytype, ValType: anytype) type {
    return struct {
        key: KeyType,
        val: ValType,
    };
}

pub fn LocalCache(comptime KeyValGenericMixin: type, comptime KeyType: type, comptime ValType: type) type {
    return struct {
        const Self = @This();

        key_val_store: ArrayList(KeyValPair(KeyType, ValType)),
        key_val_store_mutex: Mutex,

        pub fn init(a: Allocator) Self {
            return Self{ .key_val_store = ArrayList(KeyValPair(KeyType, ValType)).init(a), .key_val_store_mutex = .{} };
        }

        pub fn deinit(self: *Self) void {
            self.key_val_store.deinit();
        }

        pub fn addKeyVal(self: *Self, key: KeyType, val: ValType) !void {
            self.key_val_store_mutex.lock();
            defer self.key_val_store_mutex.unlock();

            try self.key_val_store.append(KeyValPair(KeyType, ValType){ .key = key, .val = val });
            self.key_val_store_mutex.unlock();
        }

        pub fn exists(self: *Self, key: KeyType) !bool {
            self.key_val_store_mutex.lock();
            defer self.key_val_store_mutex.unlock();

            for (self.key_val_store.items) |key_val| {
                if (KeyValGenericMixin.eql(key_val.key, key)) {
                    return true;
                }
            }
            return false;
        }

        pub fn removeByKey(self: *Self, key: KeyType) !bool {
            self.key_val_store_mutex.lock();
            defer self.key_val_store_mutex.unlock();

            for (self.key_val_store.items) |key_val, i| {
                if (KeyValGenericMixin.eql(key_val.key, key)) {
                    _ = self.key_val_store.orderedRemove(i);
                    return true;
                }
            }
            return false;
        }

        pub usingnamespace KeyValGenericMixin;
    };
}

fn KeyValGenericOperations() type {
    return struct {
        pub fn eql(k1: anytype, k2: anytype) bool {
            return mem.eql(u8, k1, k2);
        }
    };
}

test "basic LocalCache test" {
    var cache = LocalCache(KeyValGenericOperations(), []const u8, []const u8).init(test_allocator);
    defer cache.deinit();

    try expect(!try cache.exists("doesNotExist"));

    try cache.addKeyVal("test1", "testVal");

    try expect(try cache.removeByKey("test1"));

    try expect(!try cache.exists("test1"));
}
