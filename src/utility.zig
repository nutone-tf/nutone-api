const std = @import("std");
const zqlite = @import("zqlite");
const httpz = @import("httpz");
const queries = @import("queries.zig");
const KillData = @import("types.zig").KillData;

pub fn isValidToken(conn: zqlite.Conn, req: *httpz.Request) !bool {
    if (req.header("token")) |token| {
        if (conn.row(queries.Validate.Token, .{token}) catch return false) |row| {
            defer row.deinit();
            return true;
        }
    }
    return false;
}

pub fn isServerIDChar(c: u8) bool {
    return switch (c) {
        '0'...'9', 'a'...'z', '-', '_' => true,
        else => false,
    };
}

pub fn isValidServer(conn: zqlite.Conn, token: []const u8, server_id: []const u8) !bool {
    if (server_id.len > 30) return false;
    for (server_id) |c| if (!isServerIDChar(c)) return false;
    if (conn.row(queries.Validate.ServerOwnership, .{ server_id, token }) catch return false) |row| {
        defer row.deinit();
        const success = row.boolean(0);
        if (success) {
            return true;
        } else {
            if (try conn.row(queries.Validate.ServerExistence, .{server_id})) |existsRow| {
                defer existsRow.deinit();
                const exists = existsRow.boolean(0);
                if (exists) {
                    return true;
                }
            }
            return false;
        }
    }
    return false;
}

pub fn readKillData(allocator: std.mem.Allocator, data: []const u8) !std.json.Parsed(KillData) {
    return std.json.parseFromSlice(KillData, allocator, data, .{ .allocate = .alloc_always });
}

pub fn processPlayerName(str: []const u8) []const u8 {
    const bracketIndex = std.mem.indexOf(u8, str, ")");
    if (bracketIndex != null) return str[bracketIndex.? + 1 ..] else return str;
}
