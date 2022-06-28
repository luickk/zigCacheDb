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
    const SyncCacheVal = struct {
        val: ?ValType,
        broadcast: std.Thread.Condition,
        bc_mutex: std.Thread.Mutex,
    };
    return struct {
        const Self = @This();
        const buff_size = 500;
        const CacheClientErr = error{OperationNotSupported};

        addr: net.Address,
        conn: net.Stream,
        a: Allocator,
        sync_cache: LocalCache(SyncCacheGenericOperations(), KeyType, SyncCacheVal),

        pub fn init(a: Allocator, addr: net.Address) Self {
            return Self{ .a = a, .addr = addr, .conn = undefined, .sync_cache = LocalCache(SyncCacheGenericOperations(), KeyType, SyncCacheVal).init(a) };
        }

        pub fn deinit(self: Self) void {
            self.conn.close();
        }

        pub fn connectToServer(self: *Self) !void {
            self.conn = try net.tcpConnectToAddress(self.addr);
            _ = SyncCacheVal;
            _ = try std.Thread.spawn(.{}, serverHandle, .{ self.conn, self.a, &self.sync_cache });
        }

        pub fn pushKeyVal(self: *Self, key: KeyType, val: ValType) !void {
            var sK = KeyValGenericMixin.serializeKey(key);
            var sV = KeyValGenericMixin.serializeKey(val);
            var msg = ProtocolParser.protMsgEnc{ .op_code = ProtocolParser.CacheOperation.pushKeyVal, .key = sK, .val = sV };
            var msg_encoded = try ProtocolParser.encode(self.a, &msg);
            // todo => check if write is completed...
            _ = try self.conn.write(msg_encoded);
        }

        pub fn pullValByKey(self: *Self, key: KeyType) !?ValType {
            // todo => ensure complete write
            _ = try self.conn.write(try ProtocolParser.encode(self.a, &ProtocolParser.protMsgEnc{ .op_code = ProtocolParser.CacheOperation.pullByKey, .key = key, .val = undefined }));

            if (self.sync_cache.getValByKey(key)) |*val| {
                val.broadcast.wait(&val.bc_mutex);
                return val.val;
            } else {
                try self.sync_cache.addKeyVal(key, SyncCacheVal{ .val = null, .broadcast = .{}, .bc_mutex = .{} });
            }
            return null;
        }

        fn serverHandle(conn: net.Stream, a: Allocator, sync_cache: *LocalCache(SyncCacheGenericOperations(), KeyType, SyncCacheVal)) !void {
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
                                if (try sync_cache.exists(parser.temp_parsing_prot_msg.key.?)) {}
                            },
                        }
                    }
                }
            }
        }

        fn SyncCacheGenericOperations() type {
            return struct {
                pub fn eql(k1: anytype, k2: anytype) bool {
                    return mem.eql(u8, k1, k2);
                }

                pub fn freeKey(a: Allocator, key: anytype) void {
                    a.free(key);
                }

                pub fn freeVal(a: Allocator, val: anytype) void {
                    a.free(val);
                }

                pub fn serializeKey(key: anytype) []u8 {
                    return key.key;
                }

                pub fn deserializeKey(key: anytype) []u8 {
                    return key.key;
                }

                pub fn serializeVal(val: anytype) []u8 {
                    return val.val;
                }

                pub fn deserializeVal(val: anytype) []u8 {
                    return val.val;
                }
            };
        }
    };
}
