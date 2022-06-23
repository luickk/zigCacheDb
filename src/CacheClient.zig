const std = @import("std");
const netProtocol = @import("netProtocol.zig");
const testing = std.testing;
const print = std.debug.print;
const ArrayList = std.ArrayList;
const expect = std.testing.expect;
const mem = std.mem;
const net = std.net;

const test_allocator = std.testing.allocator;
const Allocator = std.mem.Allocator;

pub fn CacheClient(comptime KeyValGenericMixin: type, comptime KeyType: type, comptime ValType: type) type {
    return struct {
        const Self = @This();
        addr: net.Address,
        conn: net.Stream,
        a: Allocator,

        pub fn init(a: Allocator, addr: net.Address) Self {
            _ = KeyValGenericMixin;
            _ = KeyType;
            _ = ValType;
            return Self{ .a = a, .addr = addr, .conn = undefined };
        }

        pub fn deinit(self: Self) void {
            self.conn.close();
        }

        pub fn connectToServer(self: *Self) !void {
            self.conn = try net.tcpConnectToAddress(self.addr);
        }

        pub fn pushKeyVal(self: *Self, key: KeyType, val: ValType) !void {
            var sK = KeyValGenericMixin.serializeKey(key);
            var sV = KeyValGenericMixin.serializeKey(val);
            var msg = netProtocol.protMsg{ .op_code = netProtocol.cacheOperation.pushKeyVal, .key = sK, .key_size = sK.len, .val = sV, .val_size = sV.len };
            var msg_encoded = try netProtocol.ProtocolParser.encode(self.a, &msg);
            _ = try self.conn.write(msg_encoded);
        }
    };
}
