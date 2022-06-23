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

pub const cacheOperation = enum(u8) {
    pullByKey,
    pushKeyVal,
    pullByKeyReply,
};

// protocol: opCode: u8; keySize: u16; key: []u8; valSize: u16; val: []u8
// key/val len info contained in slice
pub const protMsg = struct { op_code: cacheOperation, key: []u8, val: []u8 };

// state conserving parser
pub const ProtocolParser = struct {
    a: Allocator,
    // struct to which newly parsed data is written for temp reuse
    temp_parsing_prot_msg: protMsg,
    // contains at which element the parser currently works
    step: u8,
    // defines at which byte the current step is (has to be reset every new parsing cycle)
    step_size: usize,
    // is the point at which the new tcp read data should be written at
    merge_point: usize,

    pub fn init(a: Allocator) ProtocolParser {
        return ProtocolParser{ .a = a, .temp_parsing_prot_msg = .{ .op_code = undefined, .key = undefined, .val = undefined }, .step_size = 0, .step = 0, .merge_point = 0 };
    }

    // returns 0 if there is nothing left to parse anymore and state information if there is
    // todo: proper error handling
    // todo: endianness; network end
    pub fn parse(self: *ProtocolParser, inp: []u8, read_size: usize) !bool {
        // if (native_endian == .Little) {
        //     utils.sliceSwap(u8, inp);
        // }
        // self.step_size = 0;
        parsing: while (true) {
            switch (self.step) {
                0 => {
                    self.step_size += 1;
                    if (read_size >= self.step_size) {
                        print("-------1 c/n", .{});
                        self.temp_parsing_prot_msg.op_code = @intToEnum(cacheOperation, inp[0]);
                        self.step += 1;
                    } else {
                        self.merge_point = self.step_size - read_size;
                        break :parsing;
                    }
                },
                1 => {
                    self.step_size += 2;
                    print("-------2 c/n", .{});
                    if (read_size >= self.step_size) {
                        print("-------2,2 c/n", .{});
                        self.temp_parsing_prot_msg.key.len = mem.readInt(u16, inp[1..3], native_endian);
                        self.step += 1;
                        print("-------2,4 c/n", .{});
                    } else {
                        self.merge_point = self.step_size - read_size;
                        break :parsing;
                    }
                },
                3 => {
                    self.step_size += self.temp_parsing_prot_msg.key.len;
                    if (read_size >= self.step_size) {
                        print("-------3 /n", .{});
                        self.temp_parsing_prot_msg.key = try self.a.alloc(u8, self.temp_parsing_prot_msg.key.len);
                        mem.copy(u8, self.temp_parsing_prot_msg.key, inp[self.step_size - self.temp_parsing_prot_msg.key.len .. self.step_size]);
                        self.step += 1;
                    } else {
                        self.merge_point = self.step_size - read_size;
                        break :parsing;
                    }
                },
                4 => {
                    self.step_size += 2;
                    if (read_size >= self.step_size) {
                        print("-------4 c/n", .{});
                        self.temp_parsing_prot_msg.val.len = mem.readIntSlice(u16, inp[self.step_size - 2 .. self.step_size], native_endian);
                        self.step += 1;
                    } else {
                        self.merge_point = self.step_size - read_size;
                        break :parsing;
                    }
                },
                5 => {
                    self.step_size += self.temp_parsing_prot_msg.val.len;
                    if (read_size >= self.step_size) {
                        self.temp_parsing_prot_msg.val = try self.a.alloc(u8, self.temp_parsing_prot_msg.val.len);
                        mem.copy(u8, self.temp_parsing_prot_msg.val, inp[self.step_size - self.temp_parsing_prot_msg.val.len .. self.step_size]);
                        self.step += 1;
                        print("-------6 /n", .{});
                    } else {
                        self.merge_point = self.step_size - read_size;
                        break :parsing;
                    }
                },
                else => break,
            }
        }
        if (self.step == 6) {
            self.step = 0;
            self.step_size = 0;
            return true;
        }
        return false;
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
    const msg = protMsg{ .op_code = cacheOperation.pushKeyVal, .key = "test", .val = "123456789" };

    var en_msg = try ProtocolParser.encode(test_allocator, msg);
    defer test_allocator.free(en_msg);

    var parser = ProtocolParser.init(test_allocator);
    _ = parser;
    // todo: fix parser
    // try expect(try parser.parse(en_msg, en_msg.len));

    // try expect(parser.temp_parsing_prot_msg.op_code == 1);
    // try expect(mem.eql(u8, parser.temp_parsing_prot_msg.key, &key));
    // try expect(mem.eql(u8, parser.temp_parsing_prot_msg.val, &val));
}
