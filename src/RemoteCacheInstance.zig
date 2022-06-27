const std = @import("std");
const netProtocol = @import("netProtocol.zig");
const native_endian = @import("builtin").target.cpu.arch.endian();
const ProtocolParser = netProtocol.ProtocolParser;
const ParserState = netProtocol.ProtocolParser.ParserState;
const CacheOperation = netProtocol.ProtocolParser.CacheOperation;
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
    const RemoteCacheInstanceErr = error{OperationNotSupported};

    return struct {
        const Self = @This();

        const Client = struct {
            conn: net.StreamServer.Connection,
            handle_frame: @Frame(handle),

            fn handle(self: *Client, a: Allocator, cache: *LocalCache(KeyValGenericMixin, KeyType, ValType)) !void {
                var parser = try ProtocolParser.init(test_allocator, self.conn, 500);
                var parser_state = ProtocolParser.ParserState.parsing;
                while (try parser.buffTcpParse()) {
                    while (try parser.parse(&parser_state)) {
                        if (parser_state == ParserState.done) {
                            switch (parser.temp_parsing_prot_msg.op_code) {
                                CacheOperation.pullByKey => {
                                    if (cache.getValByKey(parser.temp_parsing_prot_msg.key) != null) {
                                        // todo => ensure complete write
                                        _ = try parser.conn.stream.write(try ProtocolParser.encode(a, &.{ .op_code = CacheOperation.pullByKeyReply, .key = parser.temp_parsing_prot_msg.key, .val = parser.temp_parsing_prot_msg.val }));
                                    } else {
                                        // todo => return key not foudn msg
                                    }
                                },
                                CacheOperation.pushKeyVal => {
                                    try cache.addKeyVal(KeyValGenericMixin.deserializeKey(parser.temp_parsing_prot_msg.key), KeyValGenericMixin.deserializeVal(parser.temp_parsing_prot_msg.val));
                                },
                                CacheOperation.pullByKeyReply => {
                                    return RemoteCacheInstanceErr.OperationNotSupported;
                                },
                            }
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
            return Self{ .port = port, .cache = LocalCache(KeyValGenericMixin, KeyType, ValType).init(a), .server = net.StreamServer.init(.{ .reuse_address = true }), .a = a };
        }

        pub fn debugPrintLocalCache(self: *Self) void {
            self.cache.debugPrintCache();
        }

        pub fn startInstance(self: *Self) !void {
            try self.server.listen(try net.Address.parseIp("127.0.0.1", self.port));
            while (true) {
                const client = try self.a.create(Client);

                client.* = Client{
                    .conn = try self.server.accept(),
                    // todo => determine wether async is really the right option for a streaming protocol
                    .handle_frame = async client.handle(self.a, &self.cache),
                };
            }
        }

        pub fn deinit(self: *Self) void {
            for (self.cache.key_val_store.items) |key_val| {
                KeyValGenericMixin.freeKey(self.a, key_val.key);
                KeyValGenericMixin.freeKey(self.a, key_val.val);
            }
            // does not deinit KeyVal pairs!
            self.cache.deinit();
            self.server.deinit();
        }

        pub usingnamespace KeyValGenericMixin;
    };
}

test "basic RemoteCacheInstance test" {}
