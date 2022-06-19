const std = @import("std");
const testing = std.testing;
const print = std.debug.print;
const ArrayList = std.ArrayList;

const test_allocator = std.testing.allocator;
const Allocator = std.mem.Allocator;

const localCacheErr = error{};

pub fn keyValPair(comptime key_type: type, comptime val_type: type) type {
    return struct {
        key: key_type,
        val: val_type,
    };
}

pub fn localCache(comptime key_type: type, comptime val_type: type) type {
    return struct {
        const Self = @This();

        key_val_store: ArrayList(keyValPair(key_type, val_type)),
        // key_val_store: [*]keyValPair,

        fn init(a: Allocator) Self {
            return Self{ .key_val_store = ArrayList(keyValPair(key_type, val_type)).init(a) };
        }

        fn deinit(self: *Self) void {
            self.key_val_store.deinit();
        }

        fn add_key_val(self: *Self, key: key_type, val: val_type) !void {
            print("dsad: {} {} \n", .{ key.len, val.len });
            try self.key_val_store.append(keyValPair(key_type, val_type){ .key = key, .val = val });
        }
    };
}

test "localCache test" {
    var cache = localCache([]const u8, []const u8).init(test_allocator);
    defer cache.deinit();
    cache.add_key_val("dsad", "dsad") catch unreachable;
}
