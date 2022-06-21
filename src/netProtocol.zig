const std = @import("std");
const testing = std.testing;
const print = std.debug.print;
const ArrayList = std.ArrayList;
const expect = std.testing.expect;
const mem = std.mem;
const net = std.net;

const test_allocator = std.testing.allocator;
const Allocator = std.mem.Allocator;

const local = @import("local.zig");

const cacheOperation = enum(u8) {
    pullByKey,
    pushKeyVal,
    pullByKeyReply,
};

// protocol: opCode: u8; keySize: u16; key: []u8; valSize: u16; val: []u8
const protMsg = extern struct { op_code: u8, key_size: u16, key: []const u8, val_size: u16, val: []const u8 };

// state conserving parser
pub const ProtocolParser = struct {
    // struct to which newly parsed data is written for temp reuse
    temp_parsing_prot_msg: protMsg,
    // contains at which element the parser currently works
    step: u8,
    // defines at which byte the current step is (has to be reset every new parsing cycle)
    step_size: u32,

    // returns 0 if there is nothing left to parse anymore and state information if there is
    pub fn parse(self: *ProtocolParser, inp: *const []u8) ?struct { step: u8, step_size: u32 } {
        self.step_size = 0;
        parsing: while (true) {
            switch (self.step) {
                0 => {
                    self.step_size += 1;
                    if (inp.len >= self.step_size) {
                        self.temp_parsing_prot_msg.op_code = mem.readInt(u8, inp[0], .bigEndian);
                        self.step += 1;
                    } else {
                        break :parsing;
                    }
                },
                1 => {
                    self.step_size += 2;
                    if (inp.len >= self.step_size) {
                        self.temp_parsing_prot_msg.key_size = mem.readInt(u16, inp[1..2], .bigEndian);
                        self.step += 1;
                    } else {
                        break :parsing;
                    }
                },
                3 => {
                    self.step_size += self.temp_parsing_prot_msg.key_size;
                    if (inp.len >= self.step_size) {
                        // todo => endianness!
                        self.temp_parsing_prot_msg.key = inp[self.step_size - self.temp_parsing_prot_msg.key_size .. self.step_size];
                        self.step += 1;
                    } else {
                        break :parsing;
                    }
                },
                4 => {
                    self.step_size += 2;
                    if (inp.len >= self.step_size) {
                        // todo => endianness!
                        self.temp_parsing_prot_msg.val_size = mem.readInt(u16, inp[self.step_size - 2 .. self.step_size], .bigEndian);
                        self.step += 1;
                    } else {
                        break :parsing;
                    }
                },
                5 => {
                    self.step_size += self.temp_parsing_prot_msg.val_size;
                    if (inp.len >= self.step_size) {
                        self.temp_parsing_prot_msg.val = inp[self.step_size - self.temp_parsing_prot_msg.val_size .. self.step_size];
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

    pub fn encode(a: Allocator, to_encode: protMsg) !struct { data: [*]u8, size: u32 } {
        const mem_size = 1 + 2 + to_encode.key_size + 2 + to_encode.val_size;
        const encoded_msg = try a.alloc(u8, mem_size);

        mem.writeInt(u8, &encoded_msg[0], to_encode.op_code, .bigEndian);

        mem.writeInt(u16, &encoded_msg[1], to_encode.key_size, .bigEndian);
        mem.writeIntSliceBig(u8, &encoded_msg[3], to_encode.key, .bigEndian);

        mem.writeInt(u16, &encoded_msg[3 + to_encode.key_size + 1], to_encode.val_size, .bigEndian);
        mem.writeIntSliceBig(u8, &encoded_msg[3 + to_encode.key_size + 2 + to_encode.val_size + 1], to_encode.val, .bigEndian);

        return .{ mem, mem_size };
    }
};

test "test protocol encoding" {
    const msg = protMsg {.op_code=1,.key_size=4,.key="test",.val_size=9,.val="123456789"}};
}

test "test protocol parsing" {

}