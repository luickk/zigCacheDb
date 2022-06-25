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
pub const ProtocolParser = struct {
    pub const CacheOperation = enum(u8) {
        pullByKey,
        pushKeyVal,
        pullByKeyReply,
    };

    const ParserStep = enum(u8) {
        parsingOpCode,
        parsingKey,
        parsingKeySize,
        parsingVal,
        parsingValSize,
        done,
    };

    pub const ParserState = enum(u8) { waiting, parsing, done };

    // protocol: opCode: u8; keySize: u16; key: []u8; valSize: u16; val: []u8
    // key/val len info contained in slice
    pub const protMsg = struct { op_code: CacheOperation, key: []u8, val: []u8 };

    a: Allocator,
    // struct to which newly parsed data is written for temp reuse
    temp_parsing_prot_msg: protMsg,
    // contains at which element the parser currently works
    step: ParserStep,
    // defines at which byte the current step is
    step_size: usize,
    // is the point at which the new tcp read data should be written at
    merge_point: usize,

    pub fn init(a: Allocator) ProtocolParser {
        return ProtocolParser{ .a = a, .temp_parsing_prot_msg = .{ .op_code = undefined, .key = undefined, .val = undefined }, .step_size = 1, .step = ParserStep.parsingOpCode, .merge_point = 0 };
    }

    // returns true if there is nothing left to parse
    // todo => proper error handling
    // todo => endianness; network endi.
    // todo => handle alloced memory
    pub fn parse(self: *ProtocolParser, inp: []u8, read_size: usize) !ParserState {
        // if (native_endian == .Little) {
        //     utils.sliceSwap(u8, inp);
        // }

        if (read_size <= self.step_size - 1) {
            self.merge_point = self.step_size - read_size;
            return ParserState.waiting;
        }
        switch (self.step) {
            ParserStep.parsingOpCode => {
                self.temp_parsing_prot_msg.op_code = @intToEnum(CacheOperation, inp[self.step_size - 1]);
                self.step = ParserStep.parsingKeySize;
                self.step_size += 2;
            },
            ParserStep.parsingKeySize => {
                self.temp_parsing_prot_msg.key.len = mem.readIntSlice(u16, inp[self.step_size - 2 .. self.step_size], native_endian);
                self.step = ParserStep.parsingKey;
                self.step_size += self.temp_parsing_prot_msg.key.len;
            },
            ParserStep.parsingKey => {
                self.temp_parsing_prot_msg.key = try self.a.alloc(u8, self.temp_parsing_prot_msg.key.len);
                mem.copy(u8, self.temp_parsing_prot_msg.key, inp[self.step_size - self.temp_parsing_prot_msg.key.len .. self.step_size]);
                self.step = ParserStep.parsingValSize;
                self.step_size += 2;
            },
            ParserStep.parsingValSize => {
                self.temp_parsing_prot_msg.val.len = mem.readIntSlice(u16, inp[self.step_size - 2 .. self.step_size], native_endian);
                self.step = ParserStep.parsingVal;
                self.step_size += self.temp_parsing_prot_msg.val.len;
            },
            ParserStep.parsingVal => {
                self.temp_parsing_prot_msg.val = try self.a.alloc(u8, self.temp_parsing_prot_msg.val.len);
                mem.copy(u8, self.temp_parsing_prot_msg.val, inp[self.step_size - self.temp_parsing_prot_msg.val.len .. self.step_size]);
                self.step = ParserStep.done;
            },
            else => unreachable,
        }
        if (self.step == ParserStep.done) {
            self.step = ParserStep.parsingOpCode;
            // beginning with op_code which is 1 byte in size
            self.step_size = 1;
            return ParserState.done;
        }
        return ParserState.parsing;
    }

    pub fn encode(a: Allocator, to_encode: *protMsg) ![]u8 {
        var mem_size = 1 + 2 + to_encode.key.len + 2 + to_encode.val.len;
        var encoded_msg = try a.alloc(u8, mem_size);

        mem.writeIntSlice(u8, encoded_msg[0..1], @enumToInt(to_encode.op_code), native_endian);

        mem.writeIntSlice(u16, encoded_msg[1..3], @truncate(u16, to_encode.key.len), native_endian);
        mem.copy(u8, encoded_msg[3 .. to_encode.key.len + 3], to_encode.key);

        mem.writeIntSlice(u16, encoded_msg[3 + to_encode.key.len .. 3 + to_encode.key.len + 2], @truncate(u16, to_encode.val.len), native_endian);
        mem.copy(u8, encoded_msg[3 + 2 + to_encode.key.len .. 3 + 2 + to_encode.key.len + to_encode.val.len], to_encode.val);

        // if (native_endian == .Little) {
        //     utils.sliceSwap(u8, encoded_msg);
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

    var parser = ProtocolParser.init(test_allocator);
    _ = parser;
    // todo => fix parser

    var i: usize = 0;
    while ((try parser.parse(en_msg, en_msg.len)) == ProtocolParser.ParserState.parsing) {
        i += 1;
        if (i > 4) {
            try expect(false);
        }
    }

    try expect(parser.temp_parsing_prot_msg.op_code == ProtocolParser.CacheOperation.pushKeyVal);
    try expect(mem.eql(u8, parser.temp_parsing_prot_msg.key, &key));
    try expect(mem.eql(u8, parser.temp_parsing_prot_msg.val, &val));

    test_allocator.free(parser.temp_parsing_prot_msg.key);
    test_allocator.free(parser.temp_parsing_prot_msg.val);
}
