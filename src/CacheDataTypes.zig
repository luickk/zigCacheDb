pub fn CacheDataTypes(comptime ArgKeyValGenericFn: fn (type, type) type, comptime ArgKeyType: type, comptime ArgValType: type) type {
    return struct {
        pub const KeyValGenericFn = ArgKeyValGenericFn(ArgKeyType, ArgValType);
        pub const KeyType: type = ArgKeyType;
        pub const ValType: type = ArgValType;
    };
}
