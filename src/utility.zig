const std = @import("std");
const zqlite = @import("zqlite");
const httpz = @import("httpz");
const queries = @import("queries.zig");
const types = @import("types.zig");

pub fn isValidServer(conn: zqlite.Conn, req: *httpz.Request) !bool {
    if (req.header("token")) |token| {
        if (try conn.row(queries.validateToken, .{token})) |row| {
            defer row.deinit();
            return true;
        }
    }
    return false;
}

pub fn isValidServerOwner(conn: zqlite.Conn, token: []const u8, server_id: []const u8) !bool {
    if (try conn.row(queries.validateServerOwnership, .{ server_id, token })) |row| {
        defer row.deinit();
        const success = row.boolean(0);
        if (success) {
            return true;
        } else {
            if (try conn.row(queries.validateServerExistence, .{server_id})) |existsRow| {
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

pub fn readKillData(allocator: std.mem.Allocator, data: []const u8) !std.json.Parsed(types.KillData) {
    return std.json.parseFromSlice(types.KillData, allocator, data, .{ .allocate = .alloc_always });
}
