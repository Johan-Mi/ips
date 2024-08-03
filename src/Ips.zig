const std = @import("std");

records: std.ArrayList(Record),

const Offset = u24;
const Size = u16;
const header = "PATCH";
const eof = "EOF";

const RawRecord = packed struct {
    offset: Offset,
    size: Size,
};

const Record = struct {
    offset: Offset,
    data: union(enum) {
        non_rle: []u8,
        rle: struct { size: Size, byte: u8 },
    },

    fn deinit(self: @This(), allocator: std.mem.Allocator) void {
        switch (self.data) {
            .non_rle => |it| allocator.free(it),
            .rle => {},
        }
    }
};

pub fn new(path: []const u8, allocator: std.mem.Allocator) !@This() {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    var reader = std.io.bufferedReader(file.reader());

    var header_buf: [header.len]u8 = undefined;
    const header_len = try reader.read(&header_buf);
    if (!std.mem.eql(u8, header, header_buf[0..header_len])) return error.MissingHeader;

    var self = @This(){ .records = std.ArrayList(Record).init(allocator) };
    errdefer self.deinit();

    while (true) {
        const raw_record_size = @bitSizeOf(RawRecord) / std.mem.byte_size_in_bits;
        var buf = std.BoundedArray(u8, raw_record_size){};
        try reader.reader().readIntoBoundedBytes(raw_record_size, &buf);
        if (std.mem.eql(u8, buf.slice(), eof)) break;
        if (buf.len != buf.capacity()) return error.UnexpectedEof;

        const raw_record = std.mem.bytesAsValue(RawRecord, buf.slice());
        const offset = std.mem.bigToNative(Offset, raw_record.offset);
        const size = std.mem.bigToNative(Size, raw_record.size);
        if (size == 0) {
            const rle_size = try reader.reader().readInt(Size, .big);
            const byte = try reader.reader().readByte();
            try self.records.append(.{
                .offset = offset,
                .data = .{ .rle = .{ .size = rle_size, .byte = byte } },
            });
        } else {
            const data = try allocator.alloc(u8, size);
            errdefer allocator.free(data);
            if (try reader.read(data) != size) return error.UnexpectedEof;
            try self.records.append(.{ .offset = offset, .data = .{ .non_rle = data } });
        }
    }

    return self;
}

pub fn apply(self: *const @This(), buf: []u8) !void {
    for (self.records.items) |record| {
        if (buf.len < record.offset) return error.RecordOutOfBounds;
        switch (record.data) {
            .non_rle => |it| if (buf.len - record.offset < it.len)
                return error.RecordOutOfBounds
            else
                @memcpy(buf[record.offset..][0..it.len], it),
            .rle => |it| if (buf.len - record.offset < it.size)
                return error.RecordOutOfBounds
            else
                @memset(buf[record.offset..][0..it.size], it.byte),
        }
    }
}

pub fn deinit(self: @This()) void {
    for (self.records.items) |record|
        record.deinit(self.records.allocator);
    self.records.deinit();
}
