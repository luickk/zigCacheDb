const std = @import("std");
const testing = std.testing;
const print = std.debug.print;
const ArrayList = std.ArrayList;
const expect = std.testing.expect;
const mem = std.mem;
const net = std.net;

const test_allocator = std.testing.allocator;
const Allocator = std.mem.Allocator;

const local = @import("local.zig");

pub fn RemoteCacheInstance(comptime KeyValGenericMixin: type, comptime KeyType: type, comptime ValType: type) type {
    return struct {
        const Self = @This();

        const Client = struct {
            conn: net.StreamServer.Connection,
            handle_frame: @Frame(handle),

            fn handle(self: *Client) !void {
                // _ = try self.conn.stream.write("\n");
                while (true) {
                    var buf: [100]u8 = undefined;
                    const amt = try self.conn.stream.read(&buf);
                    const msg = buf[0..amt];
                    _ = msg;
                }
            }
        };

        port: u16,
        cache: local.LocalCache(KeyValGenericMixin, KeyType, ValType),
        server: net.StreamServer,
        a: Allocator,

        pub fn init(a: Allocator, port: u16) Self {
            _ = KeyValGenericMixin.serializeKey("dsda");
            return Self{ .port = port, .cache = local.LocalCache(KeyValGenericMixin, KeyType, ValType).init(a), .server = net.StreamServer.init(.{}), .a = a };
        }

        pub fn startInstance(self: *Self) !void {
            try self.server.listen(net.Address.parseIp("127.0.0.1", self.port) catch unreachable);
            while (true) {
                const client = try self.a.create(Client);
                client.* = Client{
                    .conn = try self.server.accept(),
                    .handle_frame = async client.handle(),
                };
            }
        }

        pub fn deinit(self: *Self) void {
            self.cache.deinit();
            self.server.deinit();
        }

        pub usingnamespace KeyValGenericMixin;
    };
}

fn KeyValGenericOperations() type {
    return struct {
        pub fn eql(k1: anytype, k2: anytype) bool {
            return mem.eql(u8, k1, k2);
        }

        pub fn serializeKey(key: anytype) []const u8 {
            return key;
        }

        pub fn deserializeKey(key: anytype) []const u8 {
            return key;
        }

        pub fn serializeVal(val: anytype) []const u8 {
            return val;
        }

        pub fn deserializeVal(val: anytype) []const u8 {
            return val;
        }
    };
}

test "basic RemoteCacheInstance test" {
    var server = RemoteCacheInstance(KeyValGenericOperations(), []const u8, []const u8).init(test_allocator, 8888);
    defer server.deinit();

    // try server.startInstance();
}
