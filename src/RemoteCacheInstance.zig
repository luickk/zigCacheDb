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

        port: u16,
        cache: LocalCache(KeyValGenericMixin, KeyType, ValType),
        server: net.StreamServer,
        a: Allocator,

        pub fn init(a: Allocator, port: u16) Self {
            return Self{ .port = port, .cache = LocalCache(KeyValGenericMixin, KeyType, ValType).init(a), .server = net.StreamServer.init(.{ .reuse_address = true }), .a = a };
        }

        pub fn startInstance(self: *Self) !std.Thread {
            try self.server.listen(try net.Address.parseIp("127.0.0.1", self.port));
            return try std.Thread.spawn(.{}, start, .{ self.a, &self.server, &self.cache });
        }

        fn start(a: Allocator, server: *net.StreamServer, cache: *LocalCache(KeyValGenericMixin, KeyType, ValType)) !void {
            while (true) {
                _ = try std.Thread.spawn(.{}, clientHandle, .{ try server.*.accept(), a, cache });
            }
        }

        pub fn deinit(self: *Self) void {
            for (self.cache.key_val_store.items) |key_val| {
                KeyValGenericMixin.freeKey(self.a, key_val.key);
                KeyValGenericMixin.freeVal(self.a, key_val.val);
            }
            // does not deinit KeyVal pairs!
            self.cache.deinit();
            self.server.deinit();
        }

        fn clientHandle(conn: net.StreamServer.Connection, a: Allocator, cache: *LocalCache(KeyValGenericMixin, KeyType, ValType)) !void {
            var parser = try ProtocolParser.init(test_allocator, conn.stream, 500);
            var parser_state = ProtocolParser.ParserState.parsing;
            while (try parser.buffTcpParse()) {
                while (try parser.parse(&parser_state)) {
                    if (parser_state == ParserState.done) {
                        switch (parser.temp_parsing_prot_msg.op_code) {
                            CacheOperation.pullByKey => {
                                // todo => ensure complete write
                                var deref_val: ?[]u8 = null;
                                var key = try KeyValGenericMixin.deserializeKey(a, parser.temp_parsing_prot_msg.key.?);
                                defer a.free(key);
                                if (cache.getValByKey(key)) |val| {
                                    deref_val = KeyValGenericMixin.serializeKey(val.*);
                                }
                                _ = try parser.conn.write(try ProtocolParser.encode(a, &.{ .op_code = CacheOperation.pullByKeyReply, .key = KeyValGenericMixin.serializeKey(parser.temp_parsing_prot_msg.key.?), .val = deref_val }));
                            },
                            // todo => handle overwrites
                            CacheOperation.pushKeyVal => {
                                try cache.addKeyVal(try KeyValGenericMixin.deserializeKey(a, parser.temp_parsing_prot_msg.key.?), try KeyValGenericMixin.deserializeVal(a, parser.temp_parsing_prot_msg.val.?));
                            },
                            CacheOperation.pullByKeyReply => {
                                return RemoteCacheInstanceErr.OperationNotSupported;
                            },
                        }
                    }
                }
            }
        }

        pub usingnamespace KeyValGenericMixin;
    };
}

test "basic RemoteCacheInstance test" {}
