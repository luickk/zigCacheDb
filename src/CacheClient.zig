const std = @import("std");
const ProtocolParser = @import("netProtocol.zig").ProtocolParser;
const CacheOperation = @import("netProtocol.zig").ProtocolParser.CacheOperation;
const LocalCache = @import("LocalCache.zig").LocalCache;
const testing = std.testing;
const print = std.debug.print;
const ArrayList = std.ArrayList;
const expect = std.testing.expect;
const mem = std.mem;
const net = std.net;

const test_allocator = std.testing.allocator;
const Allocator = std.mem.Allocator;

pub fn CacheClient(comptime KeyValGenericMixin: type, comptime KeyType: type, comptime ValType: type) type {
    const SyncCacheKey = struct {
        key: KeyType,
        broadcast: std.Thread.Condition,
    };
    return struct {
        const Self = @This();
        const buff_size = 500;
        const CacheClientErr = error{OperationNotSupported};

        addr: net.Address,
        conn: net.Stream,
        a: Allocator,
        sync_cache: LocalCache(SyncCacheGenericOperations(), SyncCacheKey, ValType),

        pub fn init(a: Allocator, addr: net.Address) Self {
            return Self{ .a = a, .addr = addr, .conn = undefined, .sync_cache = LocalCache(SyncCacheGenericOperations(), SyncCacheKey, ValType).init(a) };
        }

        pub fn deinit(self: Self) void {
            self.conn.close();
        }

        pub fn connectToServer(self: *Self) !void {
            self.conn = try net.tcpConnectToAddress(self.addr);
            _ = SyncCacheKey;
            _ = try std.Thread.spawn(.{}, serverHandle, .{ self.conn, self.a, &self.sync_cache });
        }

        pub fn pushKeyVal(self: *Self, key: KeyType, val: ValType) !void {
            var sK = KeyValGenericMixin.serializeKey(key);
            var sV = KeyValGenericMixin.serializeKey(val);
            var msg = ProtocolParser.protMsg{ .op_code = ProtocolParser.CacheOperation.pushKeyVal, .key = sK, .val = sV };
            var msg_encoded = try ProtocolParser.encode(self.a, &msg);
            // todo => check if write is completed...
            _ = try self.conn.write(msg_encoded);
        }

        pub fn pullValByKey(self: *Self, key: KeyType) !ValType {
            // todo => ensure complete write
            _ = try self.conn.write(try ProtocolParser.encode(self.a, &ProtocolParser.protMsg{ .op_code = ProtocolParser.CacheOperation.pullByKey, .key = key, .val = undefined }));
            if (!try self.sync_cache.exists(.{ .key = key, .broadcast = .{} })) {
                try self.sync_cache.addKeyVal(SyncCacheKey{ .key = key, .broadcast = .{} }, undefined);
            }
            var s = "test".*;
            return &s;
        }

        fn serverHandle(conn: net.Stream, a: Allocator, sync_cache: *LocalCache(SyncCacheGenericOperations(), SyncCacheKey, ValType)) !void {
            _ = a;
            var parser = try ProtocolParser.init(test_allocator, conn, 500);
            var parser_state = ProtocolParser.ParserState.parsing;
            while (try parser.buffTcpParse()) {
                while (try parser.parse(&parser_state)) {
                    if (parser_state == ProtocolParser.ParserState.done) {
                        switch (parser.temp_parsing_prot_msg.op_code) {
                            CacheOperation.pullByKey => {
                                return CacheClientErr.OperationNotSupported;
                            },
                            CacheOperation.pushKeyVal => {
                                return CacheClientErr.OperationNotSupported;
                            },
                            CacheOperation.pullByKeyReply => {
                                // try sync_cache.addKeyVal(parser.temp_parsing_prot_msg.key, parser.temp_parsing_prot_msg.val);
                                _ = sync_cache;
                            },
                        }
                    }
                }
            }
        }

        fn SyncCacheGenericOperations() type {
            return struct {
                pub fn eql(k1: SyncCacheKey, k2: SyncCacheKey) bool {
                    return mem.eql(u8, k1.key, k2.key);
                }

                pub fn freeKey(a: Allocator, key: anytype) void {
                    a.free(key);
                }

                pub fn freeVal(a: Allocator, val: anytype) void {
                    a.free(val);
                }

                pub fn serializeKey(key: SyncCacheKey) []u8 {
                    return key.key;
                }

                pub fn deserializeKey(key: SyncCacheKey) []u8 {
                    return key.key;
                }

                pub fn serializeVal(val: anytype) []u8 {
                    return val;
                }

                pub fn deserializeVal(val: anytype) []u8 {
                    return val;
                }
            };
        }
    };
}
