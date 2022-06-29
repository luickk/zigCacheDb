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
        sync_cache: LocalCache(KeyValGenericMixin, KeyType, SyncCacheVal),

        pub fn init(a: Allocator, addr: net.Address) Self {
            return Self{ .a = a, .addr = addr, .conn = undefined, .sync_cache = LocalCache(KeyValGenericMixin, KeyType, SyncCacheVal).init(a) };
        }

        pub fn deinit(self: Self) void {
            for (self.sync_cache.key_val_store.items) |key_val| {
                KeyValGenericMixin.freeKey(self.a, key_val.key);
                if (key_val.val.val) |val| {
                    KeyValGenericMixin.freeVal(self.a, val);
                }
            }
            self.conn.close();
        }

        pub fn connectToServer(self: *Self) !void {
            self.conn = try net.tcpConnectToAddress(self.addr);
            _ = SyncCacheVal;
            _ = try std.Thread.spawn(.{}, serverHandle, .{ self.conn, self.a, &self.sync_cache });
        }

        pub fn pushKeyVal(self: *Self, key: KeyType, val: ValType) !void {
            var msg = ProtocolParser.protMsgEnc{ .op_code = ProtocolParser.CacheOperation.pushKeyVal, .key = KeyValGenericMixin.serializeKey(key), .val = KeyValGenericMixin.serializeVal(val) };
            var msg_encoded = try ProtocolParser.encode(self.a, &msg);
            // todo => check if write is completed...
            _ = try self.conn.write(msg_encoded);
        }

        pub fn pullValByKey(self: *Self, key: KeyType) !?ValType {
            // todo => ensure complete write
            _ = try self.conn.write(try ProtocolParser.encode(self.a, &ProtocolParser.protMsgEnc{ .op_code = ProtocolParser.CacheOperation.pullByKey, .key = KeyValGenericMixin.serializeKey(key), .val = null }));

            if (self.sync_cache.getValByKey(key) == null) {
                var key_clone = try self.a.alloc(u8, key.len);
                mem.copy(u8, key_clone, key);
                try self.sync_cache.addKeyVal(key_clone, SyncCacheVal{ .val = null, .broadcast = .{}, .bc_mutex = .{} });
            }
            var val = self.sync_cache.getValByKey(key).?;
            val.bc_mutex.lock();
            while (val.val == null) {
                val.broadcast.wait(&val.bc_mutex);
            }
            val.bc_mutex.unlock();
            return val.val;
        }

        fn serverHandle(conn: net.Stream, a: Allocator, sync_cache: *LocalCache(KeyValGenericMixin, KeyType, SyncCacheVal)) !void {
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
                            // todo => free key/val if pulled twice
                            CacheOperation.pullByKeyReply => {
                                var key = try KeyValGenericMixin.deserializeKey(a, parser.temp_parsing_prot_msg.key.?);
                                defer a.free(key);
                                if (sync_cache.getValByKey(key)) |val| {
                                    val.bc_mutex.lock();
                                    if (parser.temp_parsing_prot_msg.val) |msg_val| {
                                        val.val = try KeyValGenericMixin.deserializeVal(a, msg_val);
                                    } else {
                                        val.val = null;
                                    }
                                    val.broadcast.broadcast();
                                    val.bc_mutex.unlock();
                                }
                            },
                        }
                    }
                }
            }
        }
    };
}
