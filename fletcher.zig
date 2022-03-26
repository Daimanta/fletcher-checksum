const std = @import("std");
const testing = std.testing;
const assert = @import("std").debug.assert;
const mem = std.mem;

const MAX_BYTE = 255;
const MAX_SHORT = 65535;
const MAX_INT = 4294967295;

const Fletcher16 = struct {
    c0: u16,
    c1: u16,
    const Self = @This();

    pub fn init() Self {
        return Self{ .c0 = 0, .c1 = 0 };
    }

    pub fn reset(self: *Self) void {
        self.c0 = 0;
        self.c1 = 0;
    }

    pub fn update(self: *Self, input: []const u8) void {
        for (input) |byte| {
            self.c0 = (self.c0 +% byte) % MAX_BYTE;
            self.c1 = (self.c1 +% self.c0) % MAX_BYTE;
        }
    }

    pub fn final(self: *Self) u16 {
        return self.c1 << 8 | self.c0;
    }
};

const Fletcher32 = struct {
    c0: u32,
    c1: u32,
    cache: u8,
    has_cache: bool,
    const Self = @This();

    pub fn init() Self {
        return Self{ .c0 = 0, .c1 = 0, .cache = 0, .has_cache = false };
    }

    pub fn reset(self: *Self) void {
        self.c0 = 0;
        self.c1 = 0;
        self.cache = 0;
        self.has_cache = false;
    }

    pub fn update(self: *Self, input: []const u8) void {
        if (input.len == 0) {
            return;
        } else if (input.len == 1) {
            if (self.has_cache) {
                const reconstructed = self.cache | @as(u16, input[0]) << 8;
                self.update_internal_unit(reconstructed);
                self.has_cache = false;
            } else {
                self.cache = input[0];
                self.has_cache = true;
            }
        } else {
            if (self.has_cache) {
                const reconstructed = self.cache | @as(u16, input[0]) << 8;
                self.update_internal_unit(reconstructed);
                if (input.len % 2 != 0) {
                    // Even number of elements left, no cache left
                    const cast_array = mem.bytesAsSlice(u16, input[1..]);
                    for (cast_array) |word| {
                        self.update_internal_unit(word);
                    }
                    self.has_cache = false;
                } else {
                    // Odd number of elements left, put last element in cache
                    const cast_array = mem.bytesAsSlice(u16, input[1..(input.len-1)]);
                    for (cast_array) |word| {
                        self.update_internal_unit(word);
                    }
                    self.cache = input[input.len - 1];
                    self.has_cache = true;
                }

            } else {
                const take = (input.len/2)*2;
                var slice = input[0..take];
                const cast_array = mem.bytesAsSlice(u16, slice);
                for (cast_array) |word| {
                   self.update_internal_unit(word);
                }
                if (take != input.len) {
                    self.has_cache = true;
                    self.cache = input[input.len - 1];
                }
            }
        }
    }

    fn update_internal_unit(self: *Self, unit: u16) void {
       self.c0 = (self.c0 +% unit) % MAX_SHORT;
       self.c1 = (self.c1 +% self.c0) % MAX_SHORT;
    }

    pub fn final(self: *Self) u32 {
        if (self.has_cache) {
            const reconstructed = @as(u16, self.cache);
            self.update_internal_unit(reconstructed);
        }
        return self.c1 << 16 | self.c0;
    }
};

const Fletcher64 = struct {
    c0: u64,
    c1: u64,
    cache: [3]u8,
    cache_size: usize,
    const Self = @This();

    pub fn init() Self {
        return Self{ .c0 = 0, .c1 = 0, .cache = [3]u8{0, 0, 0}, .cache_size = 0 };
    }

    pub fn reset(self: *Self) void {
        self.c0 = 0;
        self.c1 = 0;
    }

    pub fn update(self: *Self, input: []const u8) void {
        if (self.cache_size > 0) {
            if (self.cache_size + input.len <= 3) {
                // Just append to the cache
                mem.copy(u8, self.cache[self.cache_size..], input[0..]);
                self.cache_size += input.len;
            } else {
                // Flush the cache, process u32's, rebuild cache
                const start = 4 - self.cache_size;
                var word_bytes: [4]u8 = [4]u8{0, 0, 0, 0};
                mem.copy(u8, word_bytes[0..], self.cache[0..self.cache_size]);
                mem.copy(u8, word_bytes[self.cache_size..4], input[0..start]);
                self.update_internal_unit(fourBytesToU32(word_bytes));
                const take = ((input.len - start)/4)*4;
                const end = start + take;
                var slice = input[start..end];
                const cast_array = mem.bytesAsSlice(u32, slice);
                for (cast_array) |dword| {
                    self.update_internal_unit(dword);
                }
                if (end != input.len) {
                    self.cache_size = input.len - end;
                    mem.copy(u8, self.cache[0..], input[end..]);
                } else {
                    self.cache_size = 0;
                }
            }
        } else {
            const take = (input.len/4)*4;
            var slice = input[0..take];
            const cast_array = mem.bytesAsSlice(u32, slice);
            for (cast_array) |dword| {
                self.update_internal_unit(dword);
            }
            if (take != input.len) {
                self.cache_size = input.len - take;
                mem.copy(u8, self.cache[0..], input[take..]);
            }
        }
    }
    
    fn update_internal_unit(self: *Self, unit: u32) void {
        self.c0 = (self.c0 +% unit) % MAX_INT;
        self.c1 = (self.c1 +% self.c0) % MAX_INT;
    }
    
    fn fourBytesToU32(bytes: [4]u8) u32 {
        return mem.bytesAsSlice(u32, bytes[0..])[0];
    }

    pub fn final(self: *Self) u64 {
        if (self.cache_size > 0) {
            var word_bytes: [4]u8 = [4]u8{0, 0, 0, 0};
            mem.copy(u8, word_bytes[0..], self.cache[0..self.cache_size]);
            self.update_internal_unit(fourBytesToU32(word_bytes));
        }
        return self.c1 << 32 | self.c0;
    }
};

test "fletcher 16 empty string" {
    var empty_block: []u8 = &.{};
    var fletcher16 = Fletcher16.init();
    fletcher16.update(empty_block);
    const result = fletcher16.final();
    const expected: u16 = 0;
    try testing.expectEqual(expected, result);
}

test "fletcher 16 string1" {
    const mystring_const: []const u8 = "abcde";

    var fletcher16 = Fletcher16.init();
    fletcher16.update(mystring_const[0..]);
    const result = fletcher16.final();

    const expected: u16 = 51440;
    try testing.expectEqual(expected, result);
}

test "fletcher 16 string2" {
    const mystring_const: []const u8 = "abcdef";

    var fletcher16 = Fletcher16.init();
    fletcher16.update(mystring_const[0..]);
    const result = fletcher16.final();

    const expected: u16 = 8279;
    try testing.expectEqual(expected, result);
}

test "fletcher 16 string3" {
    const mystring_const: []const u8 = "abcdefgh";

    var fletcher16 = Fletcher16.init();
    fletcher16.update(mystring_const[0..]);
    const result = fletcher16.final();

    const expected: u16 = 1575;
    try testing.expectEqual(expected, result);
}

test "fletcher 16 string3 piecewise" {
    const mystring_const1: []const u8 = "abc";
    const mystring_const2: []const u8 = "defgh";

    var fletcher16 = Fletcher16.init();
    fletcher16.update(mystring_const1[0..]);
    fletcher16.update(mystring_const2[0..]);
    const result = fletcher16.final();

    const expected: u16 = 1575;
    try testing.expectEqual(expected, result);
}

test "fletcher 32 empty string" {
    var empty_block: []u8 = &.{};
    var fletcher32 = Fletcher32.init();
    fletcher32.update(empty_block);
    const result = fletcher32.final();

    const expected: u32 = 0;
    try testing.expectEqual(expected, result);
}

test "fletcher 32 string1" {
    const mystring_const: []const u8 = "abcde";

    var fletcher = Fletcher32.init();
    fletcher.update(mystring_const[0..]);
    const result = fletcher.final();

    const expected: u32 = 4031760169;
    try testing.expectEqual(expected, result);
}

test "fletcher 32 string2" {
    const mystring_const: []const u8 = "abcdef";

    var fletcher = Fletcher32.init();
    fletcher.update(mystring_const[0..]);
    const result = fletcher.final();

    const expected: u32 = 1448095018;
    try testing.expectEqual(expected, result);
}

test "fletcher 32 string3" {
    const mystring_const: []const u8 = "abcdefgh";

    var fletcher = Fletcher32.init();
    fletcher.update(mystring_const[0..]);
    const result = fletcher.final();

    const expected: u32 = 3957429649;
    try testing.expectEqual(expected, result);
}

test "fletcher 32 piecewise 1" {
    const mystring_const1: []const u8 = "abc";
    const mystring_const2: []const u8 = "defgh";

    var fletcher = Fletcher32.init();
    fletcher.update(mystring_const1[0..]);
    fletcher.update(mystring_const2[0..]);
    const result = fletcher.final();

    const expected: u32 = 3957429649;
    try testing.expectEqual(expected, result);
}

test "fletcher 32 piecewise 2" {
    const mystring_const1: []const u8 = "abcd";
    const mystring_const2: []const u8 = "efgh";

    var fletcher = Fletcher32.init();
    fletcher.update(mystring_const1[0..]);
    fletcher.update(mystring_const2[0..]);
    const result = fletcher.final();

    const expected: u32 = 3957429649;
    try testing.expectEqual(expected, result);
}

test "fletcher 32 piecewise 3" {
    const mystring_const1: []const u8 = "abcdefg";
    const mystring_const2: []const u8 = "h";

    var fletcher = Fletcher32.init();
    fletcher.update(mystring_const1[0..]);
    try testing.expectEqual(true, fletcher.has_cache);
    try testing.expectEqual(@as(u8, 'g'), fletcher.cache);
    fletcher.update(mystring_const2[0..]);
    const result = fletcher.final();

    const expected: u32 = 3957429649;
    try testing.expectEqual(expected, result);
}

test "fletcher 32 piecewise 4" {
    const mystring_const1: []const u8 = "abcd";
    const mystring_const2: []const u8 = "e";

    var fletcher = Fletcher32.init();
    fletcher.update(mystring_const1[0..]);
    fletcher.update(mystring_const2[0..]);
    const result = fletcher.final();

    const expected: u32 = 4031760169;
    try testing.expectEqual(expected, result);
}

test "fletcher 64 empty string" {
    var empty_block: []u8 = &.{};
    var fletcher64 = Fletcher64.init();
    fletcher64.update(empty_block);
    const result = fletcher64.final();

    const expected: u64 = 0;
    try testing.expectEqual(expected, result);
}

test "fletcher 64 string1" {
    const mystring_const: []const u8 = "abcde";

    var fletcher = Fletcher64.init();
    fletcher.update(mystring_const[0..]);
    const result = fletcher.final();

    const expected: u64 = 14467467625952928454;
    try testing.expectEqual(expected, result);
}

test "fletcher 64 string2" {
    const mystring_const: []const u8 = "abcdef";

    var fletcher = Fletcher64.init();
    fletcher.update(mystring_const[0..]);
    const result = fletcher.final();

    const expected: u64 = 14467579776138987718;
    try testing.expectEqual(expected, result);
}

test "fletcher 64 string3" {
    const mystring_const: []const u8 = "abcdefgh";

    var fletcher = Fletcher64.init();
    fletcher.update(mystring_const[0..]);
    const result = fletcher.final();

    const expected: u64 = 3543817411021686982;
    try testing.expectEqual(expected, result);
}

test "fletcher 64 piecewise 1" {
    const mystring_const1: []const u8 = "abc";
    const mystring_const2: []const u8 = "defgh";

    var fletcher = Fletcher64.init();
    fletcher.update(mystring_const1[0..]);
    fletcher.update(mystring_const2[0..]);
    const result = fletcher.final();

    const expected: u64 = 3543817411021686982;
    try testing.expectEqual(expected, result);
}

test "fletcher 64 piecewise 2" {
    const mystring_const1: []const u8 = "abcd";
    const mystring_const2: []const u8 = "efgh";

    var fletcher = Fletcher64.init();
    fletcher.update(mystring_const1[0..]);
    fletcher.update(mystring_const2[0..]);
    const result = fletcher.final();

    const expected: u64 = 3543817411021686982;
    try testing.expectEqual(expected, result);
}

test "fletcher 64 piecewise 3" {
    const mystring_const1: []const u8 = "abcdefg";
    const mystring_const2: []const u8 = "h";

    var fletcher = Fletcher64.init();
    fletcher.update(mystring_const1[0..]);
    try testing.expectEqual(@as(usize, 3), fletcher.cache_size);
    try testing.expectEqual([_]u8{'e', 'f', 'g'}, fletcher.cache);
    fletcher.update(mystring_const2[0..]);
    const result = fletcher.final();

    const expected: u64 = 3543817411021686982;
    try testing.expectEqual(expected, result);
}

test "fletcher 64 piecewise 4" {
    const mystring_const1: []const u8 = "abcd";
    const mystring_const2: []const u8 = "e";

    var fletcher = Fletcher64.init();
    fletcher.update(mystring_const1[0..]);
    fletcher.update(mystring_const2[0..]);
    const result = fletcher.final();

    const expected: u64 = 14467467625952928454;
    try testing.expectEqual(expected, result);
}