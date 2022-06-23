pub fn memToSlice(comptime T: type, ptr: [*]T, len: usize) []T {
    return @ptrCast(*[]T, &.{ .ptr = ptr, .len = len }).*;
}

pub fn sliceSwap(comptime T: type, inp: []T) void {
    for (inp) |*c| {
        c.* = @byteSwap(T, c.*);
    }
}
