const std = @import("std");

pub fn createTestSet(a: std.mem.Allocator, size: usize) !std.ArrayList([2][25]u8) {
    var key: [25]u8 = "test-00000000000000000000".*;
    var val: [25]u8 = "1234567891011121314151617".*;

    var list = std.ArrayList([2][25]u8).init(a);

    var i: usize = 0;
    while (i < size) : (i += 1) {
        std.mem.writeIntSliceNative(usize, key[5..], i);
        try list.append([2][25]u8{ key, val });
    }
    return list;
}
