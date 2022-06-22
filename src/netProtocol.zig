const std = @import("std");
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

const local = @import("local.zig");

// todo: make it extern or mem consistent of some kind
const cacheOperation = enum(u8) {
    pullByKey,
    pushKeyVal,
    pullByKeyReply,
};

// protocol: opCode: u8; keySize: u16; key: []u8; valSize: u16; val: []u8
// key/val len info contained in slice
const protMsg = struct { op_code: u8, key: []u8, val: []u8 };

// state conserving parser
pub const ProtocolParser = struct {
    // struct to which newly parsed data is written for temp reuse
    temp_parsing_prot_msg: protMsg,
    // contains at which element the parser currently works
    step: u8,
    // defines at which byte the current step is (has to be reset every new parsing cycle)
    step_size: u32,

    // returns 0 if there is nothing left to parse anymore and state information if there is
    pub fn parse(self: *ProtocolParser, inp: []u8) ?struct { step: u8, step_size: u32 } {
        if (native_endian == .Little) {
            mem.swap(u8, inp);
        }
        self.step_size = 0;
        parsing: while (true) {
            switch (self.step) {
                0 => {
                    self.step_size += 1;
                    if (inp.len >= self.step_size) {
                        self.temp_parsing_prot_msg.op_code = mem.readInt(u8, inp[0], .Little);
                        self.step += 1;
                    } else {
                        break :parsing;
                    }
                },
                1 => {
                    self.step_size += 2;
                    if (inp.len >= self.step_size) {
                        self.temp_parsing_prot_msg.key.len = mem.readInt(u16, inp[1..2], .Little);
                        self.step += 1;
                    } else {
                        break :parsing;
                    }
                },
                3 => {
                    self.step_size += self.temp_parsing_prot_msg.key.len;
                    if (inp.len >= self.step_size) {
                        // todo => endianness!
                        self.temp_parsing_prot_msg.key = inp[self.step_size - self.temp_parsing_prot_msg.key.len .. self.step_size];
                        self.step += 1;
                    } else {
                        break :parsing;
                    }
                },
                4 => {
                    self.step_size += 2;
                    if (inp.len >= self.step_size) {
                        // todo => endianness!
                        self.temp_parsing_prot_msg.val.len = mem.readInt(u16, inp[self.step_size - 2 .. self.step_size], .Little);
                        self.step += 1;
                    } else {
                        break :parsing;
                    }
                },
                5 => {
                    self.step_size += self.temp_parsing_prot_msg.val.len;
                    if (inp.len >= self.step_size) {
                        self.temp_parsing_prot_msg.val = inp[self.step_size - self.temp_parsing_prot_msg.val.len .. self.step_size];
                        self.step += 1;
                    } else {
                        break :parsing;
                    }
                },
            }
        }
        if (self.step == 5) {
            return null;
        }
        return .{ .step = self.step, .step_size = self.step_size };
    }

    // todo: encode in big endian!!
    pub fn encode(a: Allocator, to_encode: protMsg) ![]u8 {
        const mem_size = 1 + 2 + to_encode.key.len + 2 + to_encode.val.len;
        const encoded_msg = try a.alloc(u8, mem_size);

        mem.writeIntSlice(u8, encoded_msg[0..1], to_encode.op_code, .Little);

        mem.writeIntSlice(u16, encoded_msg[1..3], @truncate(u16, to_encode.key.len), .Little);
        mem.copy(u8, encoded_msg[3 .. to_encode.key.len + 3], to_encode.key);

        mem.writeIntSlice(u16, encoded_msg[3 + to_encode.key.len .. 3 + to_encode.key.len + 2], @truncate(u16, to_encode.val.len), .Little);
        mem.copy(u8, encoded_msg[3 + 2 + to_encode.key.len .. 3 + 2 + to_encode.key.len + to_encode.val.len], to_encode.val);

        if (native_endian == .Little) {
            mem.swap(u8, encoded_msg);
        }

        return encoded_msg;
    }
};

test "test protocol encoding" {
    var key = "test".*;
    var val = "123456789".*;

    const msg = protMsg{ .op_code = 1, .key = &key, .val = &val };
    var en_msg = try ProtocolParser.encode(test_allocator, msg);
    defer test_allocator.free(en_msg);

    print("encoded msg: {b} \n", .{en_msg});
}

test "test protocol parsing" {}
