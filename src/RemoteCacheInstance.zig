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

pub fn RemoteCacheInstance(comptime CacheDataTypes: type) type {
    return struct {
        const Self = @This();
        const RemoteCacheInstanceErr = error{ OperationNotSupported, TCPWriteErr };

        port: u16,
        cache: LocalCache(CacheDataTypes.KeyValGenericFn, CacheDataTypes.KeyType, CacheDataTypes.ValType),
        server: net.StreamServer,
        a: Allocator,

        pub fn init(a: Allocator, port: u16) Self {
            return Self{ .port = port, .cache = LocalCache(CacheDataTypes.KeyValGenericFn, CacheDataTypes.KeyType, CacheDataTypes.ValType).init(a), .server = net.StreamServer.init(.{ .reuse_address = true }), .a = a };
        }

        pub fn startInstance(self: *Self) !std.Thread {
            try self.server.listen(try net.Address.parseIp("127.0.0.1", self.port));
            return try std.Thread.spawn(.{}, start, .{ self.a, &self.server, &self.cache });
        }

        fn start(a: Allocator, server: *net.StreamServer, cache: *LocalCache(CacheDataTypes.KeyValGenericFn, CacheDataTypes.KeyType, CacheDataTypes.ValType)) !void {
            while (true) {
                _ = try std.Thread.spawn(.{}, clientHandle, .{ try server.*.accept(), a, cache });
            }
        }

        pub fn deinit(self: *Self) void {
            for (self.cache.key_val_store.items) |key_val| {
                CacheDataTypes.KeyValGenericFn.freeKey(self.a, key_val.key);
                CacheDataTypes.KeyValGenericFn.freeVal(self.a, key_val.val);
            }
            // does not deinit KeyVal pairs!
            self.cache.deinit();
            self.server.deinit();
        }

        fn clientHandle(conn: net.StreamServer.Connection, a: Allocator, cache: *LocalCache(CacheDataTypes.KeyValGenericFn, CacheDataTypes.KeyType, CacheDataTypes.ValType)) !void {
            var parser = try ProtocolParser.init(test_allocator, conn.stream, 500);
            var parser_state = ProtocolParser.ParserState.parsing;
            while (try parser.buffTcpParse()) {
                while (try parser.parse(&parser_state)) {
                    if (parser_state == ParserState.done) {
                        switch (parser.temp_parsing_prot_msg.op_code) {
                            CacheOperation.pullByKey => {
                                var deref_val: ?[]u8 = null;
                                var enc_key: ?[]u8 = null;
                                var key = try CacheDataTypes.KeyValGenericFn.deserializeKey(parser.temp_parsing_prot_msg.key.?);
                                if (cache.getValByKey(key)) |val| {
                                    if (CacheDataTypes.val_is_on_stack) {
                                        deref_val = &try CacheDataTypes.KeyValGenericFn.serializeVal(val.*);
                                    } else {
                                        deref_val = try CacheDataTypes.KeyValGenericFn.serializeVal(val.*);
                                    }
                                }
                                if (CacheDataTypes.key_is_on_stack) {
                                    enc_key = &try CacheDataTypes.KeyValGenericFn.serializeKey(key);
                                } else {
                                    enc_key = try CacheDataTypes.KeyValGenericFn.serializeKey(key);
                                }
                                // optional optimisation for .encode possible (use of buffer instead of expensive iterative allocation)
                                var msg_encoded = try ProtocolParser.encode(a, &.{ .op_code = CacheOperation.pullByKeyReply, .key = enc_key, .val = deref_val });
                                if ((try parser.conn.write(msg_encoded)) != msg_encoded.len) {
                                    return RemoteCacheInstanceErr.TCPWriteErr;
                                }
                                a.free(msg_encoded);
                            },
                            CacheOperation.pushKeyVal => {
                                if (cache.getValByKey(try CacheDataTypes.KeyValGenericFn.deserializeKey(parser.temp_parsing_prot_msg.key.?))) |val| {
                                    CacheDataTypes.KeyValGenericFn.freeVal(a, val.*);
                                    val.* = try CacheDataTypes.KeyValGenericFn.cloneVal(a, try CacheDataTypes.KeyValGenericFn.deserializeVal(parser.temp_parsing_prot_msg.val.?));
                                } else {
                                    try cache.addKeyVal(try CacheDataTypes.KeyValGenericFn.cloneKey(a, try CacheDataTypes.KeyValGenericFn.deserializeKey(parser.temp_parsing_prot_msg.key.?)), try CacheDataTypes.KeyValGenericFn.cloneVal(a, try CacheDataTypes.KeyValGenericFn.deserializeVal(parser.temp_parsing_prot_msg.val.?)));
                                }
                            },
                            CacheOperation.pullByKeyReply => {
                                return RemoteCacheInstanceErr.OperationNotSupported;
                            },
                        }
                    }
                }
            }
        }

        pub usingnamespace CacheDataTypes.KeyValGenericFn;
    };
}
