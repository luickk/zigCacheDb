const std = @import("std");
const uitoa = @import("src").utils.uitoa;
const print = std.debug.print;

pub fn createTestSetU8(a: std.mem.Allocator, size: u8) !std.ArrayList([2][25]u8) {
    var key: [25]u8 = "test-00000000000000000000".*;
    var val: [25]u8 = "1234567891011121314151617".*;

    var list = std.ArrayList([2][25]u8).init(a);

    var i: u16 = 0;
    while (i < size) : (i += 1) {
        // std.mem.writeIntSliceNative(u16, key[5..], i);
        std.mem.copy(u8, key[5..], &uitoa(i));
        try list.append([2][25]u8{ key, val });
    }
    return list;
}

pub fn createTestSetInt(a: std.mem.Allocator, size: u64) !std.ArrayList([2]u64) {
    var list = std.ArrayList([2]u64).init(a);
    var i: u64 = 0;
    while (i < size) : (i += 1) {
        try list.append([2]u64{ i, i });
    }
    return list;
}
