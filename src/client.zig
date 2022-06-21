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

pub fn CacheClient() type {
    return struct {
        const Self = @This();
        adr: net.Address,
        conn: net.Connection,

        pub fn init(adr: net.Address) Self {
            return Self{ .adr = adr, .conn = undefined };
        }

        pub fn deinit(self: Self) void {
            _ = self;
        }

        pub fn connectToServer(self: *Self) !void {
            self.conn = try net.tcpConnectToAddress(self.addr);
            defer self.conn.close();
        }
    };
}
