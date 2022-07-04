# Zig Caching Database

Minimalistic in memory caching key/val database with network interface. The focus of this project was to provide a data caching/ sharing solution that does not require any kind of operating system(except for the std lib) dependet installation or initialisation. Instead this library os threads (one per client/server) to provide fast data exchange with a focus on data that needs to be streamed or distributed at high frequency. This library does not have any dependencies except for the zig std lib.

## Features

- Local key/ val storage
- remote tcp based key/val push pull 
- Continous/ high frequency data exchange
- generic Key/ Val data Types  (The library supports stack based data exchange for small and fast data exchange as well as heap based)

## Benchmarks

For a pull, which includes the pull request and RCI(Remote Cache Instance) reply, takes around `100`us on average.

## Examples

Numerous examples can be found in `ìntegration-tests/`.

### Heap Based Key/Val String Type 

For every client/server the data types and generic functions(zig Mixins for the CC and RCI) mus be declared in the CacheDataTypes, where the last two args represent the Key, Val type
In this example (Heap base), the funtions freeKey/Val, cloneKey/Val need to do what they say. If the data should be copied around on the stack, leave these funtions empty (have them return their input). An example for that can be found in `integration-tests/pushPullOnStackTest.zig`.
``` zig
const CacheTypes = CacheDataTypes(KeyValGenericOperations, []u8, []u8);

fn KeyValGenericOperations(comptime KeyType: type, comptime ValType: type) type {
    return struct {

        // If the data contains a pointer and needs memory allocs, the following fns are required
        pub fn freeKey(a: Allocator, key: KeyType) void {
            a.free(key);
        }

        pub fn freeVal(a: Allocator, val: ValType) void {
            a.free(val);
        }

        pub fn cloneKey(a: Allocator, key: KeyType) !KeyType {
            var key_clone = try a.alloc(u8, key.len);
            mem.copy(u8, key_clone, key);
            return key_clone;
        }

        pub fn cloneVal(a: Allocator, val: ValType) !ValType {
            var val_clone = try a.alloc(u8, val.len);
            mem.copy(u8, val_clone, val);
            return val_clone;
        }

        // for both kinds of data, the fns below are required
        // in this test case, the data does not have to be serialized nor reinterpreted
        pub fn eql(k1: KeyType, k2: KeyType) bool {
            return mem.eql(u8, k1, k2);
        }

        pub fn serializeKey(key: KeyType) ![]u8 {
            return key;
        }

        pub fn deserializeKey(key: []u8) !KeyType {
            return key;
        }

        pub fn serializeVal(val: ValType) ![]u8 {
            return val;
        }

        pub fn deserializeVal(val: []u8) !ValType {
            return val;
        }
    };
}
```

Next the RemoteCacheInstance (Server) has to be inited.
```zig

const gpa_allocator = gpa.allocator();
defer {
    const leaked = gpa.deinit();
    if (leaked) std.testing.expect(false) catch @panic("TEST FAIL");
}

var remote_cache = RemoteCacheInstance(CacheTypes).init(gpa_allocator, 8888);
defer remote_cache.deinit();

```

And last but not least, the CacheClient.
```zig
var addr = try std.net.Address.parseIp("127.0.0.1", 8888);
var client = CacheClient(CacheTypes).init(gpa_allocator, addr);
defer client.deinit();

try client.connectToServer();
var key = "key".*;
var val = "val".*;
try client.pushKeyVal(&key, &val);
```