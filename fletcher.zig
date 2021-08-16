const std = @import("std");
const testing = std.testing;
const assert = @import("std").debug.assert;

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

    pub fn update(self: *Self, input: []u8) void {
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
    const Self = @This();

    pub fn init() Self {
        return Self{ .c0 = 0, .c1 = 0 };
    }

    pub fn reset(self: *Self) void {
        self.c0 = 0;
        self.c1 = 0;
    }

    pub fn update(self: *Self, input: []u16) void {
        for (input) |word| {
            self.c0 = (self.c0 +% word) % MAX_SHORT;
            self.c1 = (self.c1 +% self.c0) % MAX_SHORT;
        }
    }

    pub fn final(self: *Self) u32 {
        return self.c1 << 16 | self.c0;
    }
};

const Fletcher64 = struct {
    c0: u64,
    c1: u64,
    const Self = @This();

    pub fn init() Self {
        return Self{ .c0 = 0, .c1 = 0 };
    }

    pub fn reset(self: *Self) void {
        self.c0 = 0;
        self.c1 = 0;
    }

    pub fn update(self: *Self, input: []u32) void {
        for (input) |dword| {
            self.c0 = (self.c0 +% dword) % MAX_INT;
            self.c1 = (self.c1 +% self.c0) % MAX_INT;
        }
    }

    pub fn final(self: *Self) u64 {
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
    var mystring: [mystring_const.len]u8 = undefined;
    for (mystring_const) |elem, i| {
        mystring[i] = elem;
    }

    var fletcher16 = Fletcher16.init();
    fletcher16.update(mystring[0..]);
    const result = fletcher16.final();
    const expected: u16 = 51440;
    try testing.expectEqual(expected, result);
}

test "fletcher 16 string2" {
    const mystring_const: []const u8 = "abcdef";
    var mystring: [mystring_const.len]u8 = undefined;
    for (mystring_const) |elem, i| {
        mystring[i] = elem;
    }

    var fletcher16 = Fletcher16.init();
    fletcher16.update(mystring[0..]);
    const result = fletcher16.final();
    const expected: u16 = 8279;
    try testing.expectEqual(expected, result);
}

test "fletcher 16 string3" {
    const mystring_const: []const u8 = "abcdefgh";
    var mystring: [mystring_const.len]u8 = undefined;
    for (mystring_const) |elem, i| {
        mystring[i] = elem;
    }

    var fletcher16 = Fletcher16.init();
    fletcher16.update(mystring[0..]);
    const result = fletcher16.final();
    const expected: u16 = 1575;
    try testing.expectEqual(expected, result);
}

test "fletcher 16 string3 piecewise" {
    const mystring_const1: []const u8 = "abc";
    var mystring1: [mystring_const1.len]u8 = undefined;
    for (mystring_const1) |elem, i| {
        mystring1[i] = elem;
    }

    const mystring_const2: []const u8 = "defgh";
    var mystring2: [mystring_const2.len]u8 = undefined;
    for (mystring_const2) |elem, i| {
        mystring2[i] = elem;
    }

    var fletcher16 = Fletcher16.init();
    fletcher16.update(mystring1[0..]);
    fletcher16.update(mystring2[0..]);
    const result = fletcher16.final();
    const expected: u16 = 1575;
    try testing.expectEqual(expected, result);
}

test "fletcher 32 empty string" {
    var empty_block: []u16 = &.{};
    var fletcher32 = Fletcher32.init();
    fletcher32.update(empty_block);
    const result = fletcher32.final();
    const expected: u32 = 0;
    try testing.expectEqual(expected, result);
}
