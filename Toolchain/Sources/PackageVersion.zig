const std = @import("std");

pub const Constraint = union(enum) {
    exact: std.SemanticVersion,
    caret: Caret,

    pub const Caret = struct {
        minimum: std.SemanticVersion,
        maximum: std.SemanticVersion,
        permits_prerelease: bool,
    };

    pub fn parse(text: []const u8) !Constraint {
        if (text.len < 2) return error.InvalidVersionConstraint;
        return switch (text[0]) {
            '=' => .{ .exact = std.SemanticVersion.parse(text[1..]) catch return error.InvalidVersionConstraint },
            '^' => .{ .caret = try parseCaret(text[1..]) },
            else => error.InvalidVersionConstraint,
        };
    }

    pub fn matches(self: Constraint, version_text: []const u8) bool {
        const version = std.SemanticVersion.parse(version_text) catch return false;
        return switch (self) {
            .exact => |exact| exact.order(version) == .eq,
            .caret => |caret| {
                if (version.pre != null and !caret.permits_prerelease) return false;
                return caret.minimum.order(version) != .gt and caret.maximum.order(version) == .gt;
            },
        };
    }
};

fn parseCaret(text: []const u8) !Constraint.Caret {
    const dash_or_build = std.mem.findAny(u8, text, "-+");
    const numeric = text[0..(dash_or_build orelse text.len)];
    var components = std.mem.splitScalar(u8, numeric, '.');
    const major_text = components.first();
    const minor_text = components.next() orelse return error.InvalidVersionConstraint;
    const patch_text = components.next();
    if (components.next() != null) return error.InvalidVersionConstraint;
    if (dash_or_build != null and patch_text == null) return error.InvalidVersionConstraint;

    const minimum = if (patch_text == null)
        std.SemanticVersion{
            .major = parseComponent(major_text) catch return error.InvalidVersionConstraint,
            .minor = parseComponent(minor_text) catch return error.InvalidVersionConstraint,
            .patch = 0,
        }
    else
        std.SemanticVersion.parse(text) catch return error.InvalidVersionConstraint;
    const maximum: std.SemanticVersion = if (minimum.major != 0)
        .{ .major = try increment(minimum.major), .minor = 0, .patch = 0 }
    else if (minimum.minor != 0)
        .{ .major = 0, .minor = try increment(minimum.minor), .patch = 0 }
    else
        .{ .major = 0, .minor = 0, .patch = try increment(minimum.patch) };
    return .{
        .minimum = minimum,
        .maximum = maximum,
        .permits_prerelease = minimum.pre != null,
    };
}

fn increment(value: usize) !usize {
    return std.math.add(usize, value, 1) catch error.InvalidVersionConstraint;
}

fn parseComponent(text: []const u8) !usize {
    if (text.len == 0 or text.len > 1 and text[0] == '0') return error.InvalidVersionConstraint;
    return std.fmt.parseUnsigned(usize, text, 10) catch return error.InvalidVersionConstraint;
}

test "exact and caret constraints follow the supported Semantic Versioning subset" {
    try std.testing.expect(tryMatches("=1.2.3", "1.2.3"));
    try std.testing.expect(!tryMatches("=1.2.3", "1.2.4"));
    try std.testing.expect(tryMatches("^1.2", "1.9.9"));
    try std.testing.expect(!tryMatches("^1.2", "2.0.0"));
    try std.testing.expect(tryMatches("^0.2", "0.2.9"));
    try std.testing.expect(!tryMatches("^0.2", "0.3.0"));
    try std.testing.expect(tryMatches("^0.0.3", "0.0.3"));
    try std.testing.expect(!tryMatches("^0.0.3", "0.0.4"));
    try std.testing.expect(!tryMatches("^1.2", "1.3.0-beta"));
    try std.testing.expect(tryMatches("^1.2.0-beta", "1.2.0-beta.2"));
    try std.testing.expectError(error.InvalidVersionConstraint, Constraint.parse("1.2.3"));
    try std.testing.expectError(error.InvalidVersionConstraint, Constraint.parse(">=1.2"));
}

fn tryMatches(constraint_text: []const u8, version_text: []const u8) !bool {
    const constraint = try Constraint.parse(constraint_text);
    return constraint.matches(version_text);
}
