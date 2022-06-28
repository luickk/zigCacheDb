const std = @import("std");
const local = @import("LocalCache.zig");
const native_endian = @import("builtin").target.cpu.arch.endian();
const utils = @import("utils.zig");
const testing = std.testing;
const print = std.debug.print;
const ArrayList = std.ArrayList;
const expect = std.testing.expect;
const mem = std.mem;
const net = std.net;

const test_allocator = std.testing.allocator;
const Allocator = std.mem.Allocator;

// state conserving parser
// todo => implement network byte order
pub const ProtocolParser = struct {
    pub const CacheOperation = enum(u8) {
        pullByKey,
        pushKeyVal,
        pullByKeyReply,
    };

    pub const ParserStep = enum(u8) {
        parsingOpCode,
        parsingKey,
        parsingKeySize,
        parsingVal,
        parsingValSize,
        done,
    };

    pub const ParserErr = error{ParserMissingVal};

    pub const ParserState = enum(u8) { mergeNew, parsing, done, waiting };

    // protocol: opCode: u8; keySize: u16; key: []u8; valSize: u16; val: []u8
    // key/val len info contained in slice
    pub const protMsgEnc = struct { op_code: CacheOperation, key: ?[]u8, val: ?[]u8 };
    const protMsgDec = struct { op_code: CacheOperation, key_size: u16, key: ?[]u8, val_size: u16, val: ?[]u8 };

    const buff_size = 500;

    a: Allocator,
    // struct to which newly parsed data is written for temp reuse
    temp_parsing_prot_msg: protMsgDec,

    // relevant for parse fn
    // contains enum at which element the parser currently is
    step: ParserStep,
    // buffer to which msgs are written which couldn't be fully parsed and need to be parsed in the next buffer
    merge_buff: []u8,
    // index always relative to the last read buffer
    // contains index to the last fully (ParseStep: done) msg
    msgs_parsed_index: usize,
    // index to the next element in the msg which will be parsed
    next_step_index: usize,
    // index to last fully parsed msg
    last_msg_index: usize,

    // relevant buffParse fn
    conn: net.Stream,
    buff: [buff_size]u8,
    read_size: usize,
    append_tcp_buff: bool,
    merge_size: usize,

    pub fn init(a: Allocator, conn: net.Stream, merge_buff_size: usize) !ProtocolParser {
        return ProtocolParser{
            .a = a,
            .temp_parsing_prot_msg = .{ .op_code = undefined, .key_size = 0, .key = null, .val_size = 0, .val = null },
            .next_step_index = 1,
            .last_msg_index = 0,
            .msgs_parsed_index = 0,
            .step = ParserStep.parsingOpCode,
            .merge_buff = try a.alloc(u8, merge_buff_size),
            .conn = conn,
            .buff = undefined,
            .read_size = 0,
            .append_tcp_buff = false,
            .merge_size = 0,
        };
    }

    pub fn deinit(self: *ProtocolParser) void {
        self.a.free(self.merge_buff);
    }

    pub fn buffTcpParse(self: *ProtocolParser) !bool {
        if (self.append_tcp_buff) {
            self.merge_size = self.read_size - self.msgs_parsed_index;
            self.read_size = try self.conn.read(self.buff[self.merge_size..]);
            mem.copy(u8, &self.buff, self.merge_buff[0..self.merge_size]);
            self.read_size += self.merge_size;
            self.append_tcp_buff = false;
        } else {
            self.read_size = try self.conn.read(&self.buff);
        }
        if (self.read_size == 0) {
            return false;
        }

        // has to be reset on every new buffer read
        // in order to preserve step in a buffer transition, don't reset those vars (potential speed optimisation)
        self.next_step_index = 1;
        self.msgs_parsed_index = 0;
        self.last_msg_index = 0;
        self.step = ProtocolParser.ParserStep.parsingOpCode;

        // self.temp_parsing_prot_msg.key = null;
        // self.temp_parsing_prot_msg.val = null;

        return true;
    }

    // key/ val are both allocated and need to be freed
    // explicitely considered states:
    // - buffer is read and all msgs could be parsed successfully
    //      - last msg element ends exactly at buffer end
    //      - last msg element ends somewhere within the buffer
    //      - (should always end at read_size)
    // - buffer is read but last msg could not be parsed completely
    //      - bc the buffer is maxed out
    //      - bc of networking issues (delayed tcp packets)
    pub fn parse(self: *ProtocolParser, p_state: *ParserState) !bool {
        if (self.read_size < self.next_step_index - 1) {
            mem.copy(u8, self.merge_buff, self.buff[self.msgs_parsed_index..]);
            self.append_tcp_buff = true;
            p_state.* = ParserState.mergeNew;
            return false;
        } else if (self.msgs_parsed_index == self.read_size) {
            // nothing left to parse; rest of the data can't be a msg since the last has been successfully read
            p_state.* = ParserState.waiting;
            return false;
        }
        switch (self.step) {
            ParserStep.parsingOpCode => {
                self.temp_parsing_prot_msg.op_code = @intToEnum(CacheOperation, self.buff[self.next_step_index - 1]);
                self.step = ParserStep.parsingKeySize;
                self.next_step_index += 2;
            },
            ParserStep.parsingKeySize => {
                self.temp_parsing_prot_msg.key_size = mem.readIntSliceNative(u16, self.buff[self.next_step_index - 2 .. self.next_step_index]);
                self.step = ParserStep.parsingKey;
                self.next_step_index += self.temp_parsing_prot_msg.key_size;
            },
            ParserStep.parsingKey => {
                if (self.temp_parsing_prot_msg.key_size != 0) {
                    self.temp_parsing_prot_msg.key = try self.a.alloc(u8, self.temp_parsing_prot_msg.key_size);
                    mem.copy(u8, self.temp_parsing_prot_msg.key.?, self.buff[self.next_step_index - self.temp_parsing_prot_msg.key_size .. self.next_step_index]);
                    self.step = ParserStep.parsingValSize;
                    self.next_step_index += 2;
                }
            },
            ParserStep.parsingValSize => {
                self.temp_parsing_prot_msg.val_size = mem.readIntSliceNative(u16, self.buff[self.next_step_index - 2 .. self.next_step_index]);
                self.step = ParserStep.parsingVal;
                self.next_step_index += self.temp_parsing_prot_msg.val_size;
            },
            ParserStep.parsingVal => {
                if (self.temp_parsing_prot_msg.val_size != 0) {
                    self.temp_parsing_prot_msg.val = try self.a.alloc(u8, self.temp_parsing_prot_msg.val_size);
                    mem.copy(u8, self.temp_parsing_prot_msg.val.?, self.buff[self.next_step_index - self.temp_parsing_prot_msg.val_size .. self.next_step_index]);
                    self.step = ParserStep.done;
                    self.next_step_index += 1;
                }
            },
            ParserStep.done => {},
        }
        if (self.step == ParserStep.done) {
            self.step = ParserStep.parsingOpCode;
            // substracting 1 bc to get current msg size (+1 is for the next parsing step (which alawys is opCode, so size 1, at step done))
            self.msgs_parsed_index += (self.next_step_index - 1) - self.last_msg_index;
            self.last_msg_index = self.next_step_index - 1;
            p_state.* = ParserState.done;
            return true;
        }
        p_state.* = ParserState.parsing;
        return true;
    }

    pub fn encode(a: Allocator, to_encode: *protMsgEnc) ![]u8 {
        var key_size: usize = 0;
        var val_size: usize = 0;
        if (to_encode.key) |key| {
            key_size = key.len;
        }
        if (to_encode.val) |val| {
            val_size = val.len;
        }
        var encoded_msg = try a.alloc(u8, 1 + 2 + key_size + 2 + val_size);

        mem.writeIntSliceNative(u8, encoded_msg[0..1], @enumToInt(to_encode.op_code));

        if (to_encode.key) |key| {
            mem.writeIntSliceNative(u16, encoded_msg[1..3], @truncate(u16, key.len));
            mem.copy(u8, encoded_msg[3 .. key.len + 3], key);
        } else {
            mem.writeIntSliceNative(u16, encoded_msg[1..3], 0);
        }

        if (to_encode.val) |val| {
            mem.writeIntSliceNative(u16, encoded_msg[3 + key_size .. 3 + key_size + 2], @truncate(u16, val.len));
            mem.copy(u8, encoded_msg[3 + 2 + key_size .. 3 + 2 + key_size + val.len], val);
        } else {
            mem.writeIntSliceNative(u16, encoded_msg[3 + key_size .. 3 + key_size + 2], 0);
        }

        // if (native_endian == .Little) {
        //     mem.reverse(u8, encoded_msg);
        // }

        return encoded_msg;
    }
};

test "test protocol parsing" {
    var key = "test".*;
    var val = "123456789".*;
    var msg = ProtocolParser.protMsg{ .op_code = ProtocolParser.CacheOperation.pushKeyVal, .key = &key, .val = &val };

    var en_msg = try ProtocolParser.encode(test_allocator, &msg);
    defer test_allocator.free(en_msg);

    var parser = try ProtocolParser.init(test_allocator, undefined, 500);
    defer parser.deinit();

    mem.copy(u8, &parser.buff, en_msg);
    parser.read_size = en_msg.len;
    var parser_state = ProtocolParser.ParserState.parsing;
    // if (native_endian == .Little) {
    //     mem.reverse(u8, en_msg);
    // }
    var i: usize = 0;
    while ((try parser.parse(&parser_state)) and parser_state != ProtocolParser.ParserState.done) {
        i += 1;
        if (i > 4) {
            try expect(false);
        }
    }

    try expect(parser_state == ProtocolParser.ParserState.done);
    try expect(parser.temp_parsing_prot_msg.op_code == ProtocolParser.CacheOperation.pushKeyVal);
    try expect(mem.eql(u8, parser.temp_parsing_prot_msg.key, &key));
    try expect(mem.eql(u8, parser.temp_parsing_prot_msg.val, &val));
    test_allocator.free(parser.temp_parsing_prot_msg.key);
    test_allocator.free(parser.temp_parsing_prot_msg.val);
}
