const std = @import("std");
const netProtocol = @import("netProtocol.zig");
// const is_test = @import("builtin").is_test;
const ProtocolParser = netProtocol.ProtocolParser;
const cacheOperation = netProtocol.cacheOperation;
const testing = std.testing;
const print = std.debug.print;
const ArrayList = std.ArrayList;
const expect = std.testing.expect;
const mem = std.mem;
const net = std.net;

const test_allocator = std.testing.allocator;
const Allocator = std.mem.Allocator;

const LocalCache = @import("LocalCache.zig").LocalCache;

pub fn RemoteCacheInstance(comptime KeyValGenericMixin: type, comptime KeyType: type, comptime ValType: type) type {
    return struct {
        const Self = @This();

        const Client = struct {
            conn: net.StreamServer.Connection,
            handle_frame: @Frame(handle),

            fn handle(self: *Client, cache: *LocalCache(KeyValGenericMixin, KeyType, ValType)) !void {
                _ = cache;
                var parser = ProtocolParser.init(test_allocator);
                var buff: [500]u8 = undefined;
                var read_size: usize = undefined;
                var fully_parsed = true;
                while (true) {
                    if (fully_parsed) {
                        read_size = try self.conn.stream.read(&buff);
                    } else {
                        read_size = try self.conn.stream.read(buff[parser.step_size..]);
                    }
                    if (read_size == 0) {
                        break;
                    }
                    fully_parsed = try parser.parse(&buff, read_size);
                    if (fully_parsed) {
                        switch (parser.temp_parsing_prot_msg.op_code) {
                            cacheOperation.pullByKey => {},
                            cacheOperation.pushKeyVal => {
                                try cache.addKeyVal(KeyValGenericMixin.deserializeKey(parser.temp_parsing_prot_msg.key), KeyValGenericMixin.deserializeVal(parser.temp_parsing_prot_msg.val));
                            },
                            cacheOperation.pullByKeyReply => unreachable,
                        }
                    }
                }
            }
        };

        port: u16,
        cache: LocalCache(KeyValGenericMixin, KeyType, ValType),
        server: net.StreamServer,
        a: Allocator,

        pub fn init(a: Allocator, port: u16) Self {
            // _ = KeyValGenericMixin.serializeKey("dsda");
            return Self{ .port = port, .cache = LocalCache(KeyValGenericMixin, KeyType, ValType).init(a), .server = net.StreamServer.init(.{}), .a = a };
        }

        pub fn startInstance(self: *Self) !void {
            try self.server.listen(try net.Address.parseIp("127.0.0.1", self.port));
            while (true) {
                const client = try self.a.create(Client);

                client.* = Client{
                    .conn = try self.server.accept(),
                    // todo: determine wether async is really the right option for a streaming protocol
                    .handle_frame = async client.handle(&self.cache),
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

test "basic RemoteCacheInstance test" {}
