const std = @import("std");
const ProtocolParser = @import("netProtocol.zig").ProtocolParser;
const testing = std.testing;
const print = std.debug.print;
const ArrayList = std.ArrayList;
const expect = std.testing.expect;
const mem = std.mem;
const net = std.net;

const test_allocator = std.testing.allocator;
const Allocator = std.mem.Allocator;

pub fn CacheClient(comptime KeyValGenericMixin: type, comptime KeyType: type, comptime ValType: type) type {
    return struct {
        const Self = @This();
        const buff_size = 500;
        const CacheClientErr = error{OperationNotSupported};

        // const Server = struct {
        //     conn: net.Stream,
        //     handle_frame: @Frame(handle),

        //     fn handle(self: *Server, a: Allocator, sync_cache: *LocalCache(KeyValGenericMixin, KeyType, ValType)) !void {
        //         _ = sync_cache;
        //         _ = a;
        //         var parser = try ProtocolParser.init(test_allocator, buff_size);
        //         var buff: [buff_size]u8 = undefined;
        //         var read_size: usize = undefined;
        //         var append_tcp_buff = false;
        //         var merge_size: usize = 0;
        //         while (true) {
        //             if (append_tcp_buff) {
        //                 merge_size = read_size - parser.msgs_parsed_index;
        //                 read_size = try self.conn.stream.read(buff[merge_size..]);
        //                 mem.copy(u8, &buff, parser.merge_buff[0..merge_size]);
        //                 read_size += merge_size;
        //                 append_tcp_buff = false;
        //             } else {
        //                 read_size = try self.conn.stream.read(&buff);
        //             }
        //             if (read_size == 0) {
        //                 break;
        //             }

        //             // has to be reset on every new buffer read
        //             // in order to preserve step in a buffer transition, don't reset those vars (potential speed optimisation)
        //             parser.next_step_index = 1;
        //             parser.msgs_parsed_index = 0;
        //             parser.last_msg_index = 0;
        //             parser.step = ProtocolParser.ParserStep.parsingOpCode;
        //             parsing: while (true) {
        //                 switch (try parser.parse(&buff, read_size)) {
        //                     ParserState.done => {
        //                         switch (parser.temp_parsing_prot_msg.op_code) {
        //                             CacheOperation.pullByKey => {
        //                                 return CacheClientErr.OperationNotSupported;
        //                             },
        //                             CacheOperation.pushKeyVal => {
        //                                 return CacheClientErr.OperationNotSupported;
        //                             },
        //                             CacheOperation.pullByKeyReply => {},
        //                         }
        //                     },
        //                     ParserState.mergeNew => {
        //                         append_tcp_buff = true;
        //                         break :parsing;
        //                     },
        //                     ParserState.waiting => break :parsing,
        //                     ParserState.parsing => continue,
        //                 }
        //             }
        //         }
        //     }
        // };
        addr: net.Address,
        conn: net.Stream,
        a: Allocator,

        pub fn init(a: Allocator, addr: net.Address) Self {
            _ = KeyValGenericMixin;
            _ = KeyType;
            _ = ValType;
            return Self{ .a = a, .addr = addr, .conn = undefined };
        }

        pub fn deinit(self: Self) void {
            self.conn.close();
        }

        pub fn connectToServer(self: *Self) !void {
            self.conn = try net.tcpConnectToAddress(self.addr);
        }

        pub fn pushKeyVal(self: *Self, key: KeyType, val: ValType) !void {
            var sK = KeyValGenericMixin.serializeKey(key);
            var sV = KeyValGenericMixin.serializeKey(val);
            var msg = ProtocolParser.protMsg{ .op_code = ProtocolParser.CacheOperation.pushKeyVal, .key = sK, .val = sV };
            var msg_encoded = try ProtocolParser.encode(self.a, &msg);
            // todo => check if write is completed...
            // print("{b} \n", .{msg_encoded});
            _ = try self.conn.write(msg_encoded);
        }
    };
}
