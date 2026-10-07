const std = @import("std");

pub fn isValid(value: u32) bool {
    const trail = value & 0xFF;
    return ((value >= 0x8140 and value <= 0x9FFC) or
        (value >= 0xE040 and value <= 0xEBBF)) and
        ((trail >= 0x40 and trail <= 0x7E) or
            (trail >= 0x80 and trail <= 0xFC));
}

test "Kanji byte-pair validity and mapping are exhaustive" {
    for (0..65536) |pair| {
        const lead = pair >> 8;
        const trail = pair & 0xFF;
        const expected = ((lead >= 0x81 and lead <= 0x9F) or
            (lead >= 0xE0 and lead <= 0xEB)) and
            trail >= 0x40 and trail <= 0xFC and trail != 0x7F and
            (lead != 0xEB or trail <= 0xBF);
        try std.testing.expectEqual(expected, isValid(@intCast(pair)));
        if (!expected) continue;

        const adjusted = pair - @as(usize, if (lead <= 0x9F) 0x8140 else 0xC140);
        const encoded = (adjusted >> 8) * 0xC0 + (adjusted & 0xFF);
        const unpacked = ((encoded / 0xC0) << 8) | (encoded % 0xC0);
        const decoded = unpacked + @as(usize, if (unpacked < 0x1F00) 0x8140 else 0xC140);
        try std.testing.expectEqual(pair, decoded);
    }
    try std.testing.expect(!isValid(0x18140));
}
