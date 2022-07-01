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
        bc_sync: u8,
        bc_mutex: std.Thread.Mutex,
    };
    return struct {
        const Self = @This();
        const CacheClientErr = error{ OperationNotSupported, TCPWriteErr };

        addr: net.Address,
        conn: net.Stream,
        a: Allocator,
        sync_cache: LocalCache(KeyValGenericMixin, KeyType, SyncCacheVal),

        pub fn init(a: Allocator, addr: net.Address) Self {
            return Self{ .a = a, .addr = addr, .conn = undefined, .sync_cache = LocalCache(KeyValGenericMixin, KeyType, SyncCacheVal).init(a) };
        }

        pub fn deinit(self: *Self) void {
            for (self.sync_cache.key_val_store.items) |key_val| {
                KeyValGenericMixin.freeKey(self.a, key_val.key);
                if (key_val.val.val) |val| {
                    KeyValGenericMixin.freeVal(self.a, val);
                }
            }
            self.sync_cache.deinit();
            self.conn.close();
        }

        pub fn connectToServer(self: *Self) !void {
            self.conn = try net.tcpConnectToAddress(self.addr);
            _ = SyncCacheVal;
            _ = try std.Thread.spawn(.{}, serverHandle, .{ self.conn, self.a, &self.sync_cache });
        }

        pub fn pushKeyVal(self: *Self, key: KeyType, val: ValType) !void {
            var msg = ProtocolParser.protMsgEnc{ .op_code = ProtocolParser.CacheOperation.pushKeyVal, .key = KeyValGenericMixin.keyRawToSlice(&try KeyValGenericMixin.serializeKey(key)), .val = KeyValGenericMixin.keyRawToSlice(&try KeyValGenericMixin.serializeVal(val)) };
            var msg_encoded = try ProtocolParser.encode(self.a, &msg);
            if ((try self.conn.write(msg_encoded)) != msg_encoded.len) {
                return CacheClientErr.TCPWriteErr;
            }
            self.a.free(msg_encoded);
        }

        pub fn pullValByKey(self: *Self, key: KeyType) !?ValType {
            var msg_encoded = try ProtocolParser.encode(self.a, &ProtocolParser.protMsgEnc{ .op_code = ProtocolParser.CacheOperation.pullByKey, .key = KeyValGenericMixin.keyRawToSlice(&try KeyValGenericMixin.serializeKey(key)), .val = null });
            if ((try self.conn.write(msg_encoded)) != msg_encoded.len) {
                return CacheClientErr.TCPWriteErr;
            }
            self.a.free(msg_encoded);

            if (self.sync_cache.getValByKey(key) == null) {
                var key_clone = try KeyValGenericMixin.cloneKey(self.a, key);
                try self.sync_cache.addKeyVal(key_clone, SyncCacheVal{ .val = null, .broadcast = .{}, .bc_sync = 0, .bc_mutex = .{} });
            }
            var val = self.sync_cache.getValByKey(key).?;
            val.bc_mutex.lock();
            while (val.bc_sync == 0) {
                val.broadcast.wait(&val.bc_mutex);
            }
            val.bc_sync = 0;
            val.bc_mutex.unlock();

            var return_val = val.val;
            val.val = null;
            return return_val;
        }

        fn serverHandle(conn: net.Stream, a: Allocator, sync_cache: *LocalCache(KeyValGenericMixin, KeyType, SyncCacheVal)) !void {
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
                                if (sync_cache.getValByKey(try KeyValGenericMixin.deserializeVal(parser.temp_parsing_prot_msg.key.?))) |val| {
                                    val.bc_mutex.lock();
                                    if (parser.temp_parsing_prot_msg.val) |msg_val| {
                                        val.val = try KeyValGenericMixin.cloneVal(a, try KeyValGenericMixin.deserializeVal(msg_val));
                                    } else {
                                        val.val = null;
                                    }
                                    val.bc_sync = 1;
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
