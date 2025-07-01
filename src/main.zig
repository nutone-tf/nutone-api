const std = @import("std");
const httpz = @import("httpz");
const zqlite = @import("zqlite");

const dbFlags = zqlite.OpenFlags.Create | zqlite.OpenFlags.EXResCode;
var connPtr: *const zqlite.Conn = undefined;
var gpa = std.heap.GeneralPurposeAllocator(.{}){};

pub const KillData = struct {
    match_id: []const u8,
    server_id: []const u8,
    server_name: []const u8,
    game_mode: []const u8,
    game_time: f64,
    map: []const u8,
    attacker_name: []const u8,
    attacker_uid: []const u8,
    attacker_weapon: []const u8,
    attacker_titan: []const u8,
    attacker_x: f64,
    attacker_y: f64,
    attacker_z: f64,
    victim_name: []const u8,
    victim_uid: []const u8,
    victim_weapon: []const u8,
    victim_titan: []const u8,
    victim_x: f64,
    victim_y: f64,
    victim_z: f64,
    cause_of_death: []const u8,
    distance: f64,
};

pub fn main() !void {
    var conn = try zqlite.open("./nutone.db", dbFlags);
    connPtr = &conn;
    const allocator = gpa.allocator();
    var server = try httpz.Server(void).init(allocator, .{ .port = 17274 }, {});
    defer {
        conn.close();
        server.stop();
        server.deinit();
    }
    try initDB();
    var router = try server.router(.{});
    router.get("/v1/player/:id", getPlayerData, .{});
    router.post("/v1/data", insertServerData, .{});

    try server.listen();
}

fn initDB() !void {
    var conn = connPtr.*;
    try conn.exec("create table if not exists tokens (token text primary key, owner text)", .{});
    try conn.exec("create table if not exists players (uid text, name text, timestamp timestamp default current_timestamp, primary key (uid, name))", .{});
    try conn.exec("create table if not exists servers (server_id text primary key, server_name text, owner text, timestamp timestamp default current_timestamp)", .{});
    try conn.exec("create table if not exists matches (match_id text primary key, server_id text, game_mode text, map text, timestamp timestamp default current_timestamp)", .{});
    try conn.exec("create table if not exists kill_data (timestamp timestamp default current_timestamp, match_id text, server_id text, game_time real, attacker_uid text, attacker_weapon text, attacker_titan text, attacker_x real, attacker_y real, attacker_z real, victim_uid text, victim_weapon text, victim_titan text, victim_x real, victim_y real, victim_z real, cause_of_death text, distance real)", .{});

    try conn.exec("create index if not exists kill_data_timestamp_idx on kill_data(timestamp)", .{});
    try conn.exec("create index if not exists kill_data_server_idx on kill_data(server_id)", .{});
    try conn.exec("create index if not exists kill_data_attacker_idx on kill_data(attacker_uid)", .{});
    try conn.exec("create index if not exists kill_data_victim_idx on kill_data(victim_uid)", .{});
}

fn readKillData(allocator: std.mem.Allocator, data: []const u8) !std.json.Parsed(KillData) {
    return std.json.parseFromSlice(KillData, allocator, data, .{ .allocate = .alloc_always });
}

fn insertServerData(req: *httpz.Request, res: *httpz.Response) !void {
    var conn = connPtr.*;
    var serverToken: ?[]const u8 = null;
    const allocator = gpa.allocator();
    var parsedData: ?std.json.Parsed(KillData) = null;
    defer if (parsedData) |pD| pD.deinit();

    if (try isValidServer(conn, req)) {
        serverToken = req.header("token").?;
        if (req.body()) |kill| {
            parsedData = readKillData(allocator, kill) catch {
                res.status = 400;
                res.body = "Bad Request";
                return;
            };
        } else {
            res.status = 418;
            res.body = "I'm a Teapot";
            return;
        }
        if (parsedData) |pD| {
            const data = pD.value;
            if (!try isValidServerOwner(conn, serverToken.?, data.server_id)) {
                res.status = 403;
                res.body = "Forbidden";
                return;
            }
            try conn.exec(
                "insert or replace into servers (server_id, server_name, owner) values (?1, ?2, (select owner from tokens where token = ?3 limit 1))",
                .{ data.server_id, data.server_name, serverToken },
            );
            try conn.exec(
                "insert or replace into players (uid, name) values (?1, ?2), (?3, ?4)",
                .{ data.attacker_uid, data.attacker_name, data.victim_uid, data.victim_name },
            );
            try conn.exec(
                "insert or ignore into matches (match_id, server_id, game_mode, map) values (?1, ?2, ?3, ?4)",
                .{ data.match_id, data.server_id, data.game_mode, data.map },
            );
            try conn.exec(
                "insert into kill_data (match_id, server_id, game_time, attacker_uid, attacker_weapon, attacker_titan, attacker_x, attacker_y, attacker_z, victim_uid, victim_weapon, victim_x, victim_y, victim_z, cause_of_death, distance) values (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16)",
                .{ data.match_id, data.server_id, data.game_time, data.attacker_uid, data.attacker_weapon, data.attacker_titan, data.attacker_x, data.attacker_y, data.attacker_z, data.victim_uid, data.victim_weapon, data.victim_x, data.victim_y, data.victim_z, data.cause_of_death, data.distance },
            );
        } else {
            res.status = 418;
            res.body = "I'm a Teapot";
            return;
        }
        res.status = 200;
        res.body = "OK";
        return;
    } else {
        res.status = 401;
        res.body = "Unauthorized";
        return;
    }
}

fn isValidServer(conn: zqlite.Conn, req: *httpz.Request) !bool {
    if (req.header("token")) |token| {
        if (try conn.row("select owner from tokens where token = ?1", .{token})) |row| {
            defer row.deinit();
            return true;
        }
    }
    return false;
}

fn isValidServerOwner(conn: zqlite.Conn, token: []const u8, server_id: []const u8) !bool {
    if (try conn.row("select case when exists (select * from servers where server_id = ?1 and owner = (select owner from tokens where token = ?2)) then cast(1 as bit) else cast(0 as bit) end", .{ server_id, token })) |row| {
        defer row.deinit();
        const success = row.boolean(0);
        if (success) {
            return true;
        } else {
            if (try conn.row("select case when exists (select * from servers where server_id = ?1) then cast (0 as bit) else cast (1 as bit) end", .{server_id})) |existsRow| {
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

fn getPlayerData(req: *httpz.Request, res: *httpz.Response) !void {
    var conn = connPtr.*;
    var uid: ?[]const u8 = null;
    var writeStream = std.json.writeStream(res.writer(), .{});

    defer writeStream.deinit();
    if (req.param("id")) |id| {
        var row: ?zqlite.Row = null;
        defer if (row) |r| r.deinit();

        if (try conn.row("select uid from players where uid = ?1 or name = ?1 order by timestamp desc limit 1", .{id})) |r| {
            row = r;
        }

        if (row) |r| {
            uid = r.text(0);
        }

        if (uid) |player| {
            var currentNameRow = try conn.rows("select name from players where uid = ?1 order by timestamp desc", .{player});
            defer currentNameRow.deinit();
            try writeStream.beginObject();
            if (currentNameRow.next()) |r| {
                try writeStream.objectField("name");
                try writeStream.write(r.text(0));
            }
            try writeStream.objectField("uid");
            try writeStream.write(player);
            try writeStream.objectField("aliases");
            try writeStream.beginArray();
            while (currentNameRow.next()) |r| {
                try writeStream.write(r.text(0));
            }
            try writeStream.endArray();

            const currentKillsRow = try conn.row("select count(1) from kill_data where attacker_uid = ?1 and attacker_uid <> victim_uid", .{player});
            var kills: i64 = 0;
            defer if (currentKillsRow) |r| r.deinit();

            const currentDeathsRow = try conn.row("select count(1) from kill_data where victim_uid = ?1", .{player});
            var deaths: i64 = 0;
            defer if (currentDeathsRow) |r| r.deinit();

            if (currentKillsRow) |r| {
                kills = r.int(0);
            }
            if (currentDeathsRow) |r| {
                deaths = r.int(0);
            }

            try writeStream.objectField("kills");
            try writeStream.write(kills);
            try writeStream.objectField("deaths");
            try writeStream.write(deaths);

            try writeStream.objectField("kd");
            if (deaths == 0) {
                try writeStream.write(kills);
            } else {
                try writeStream.print("{d}", .{@as(f64, @floatFromInt(kills)) / @as(f64, @floatFromInt(deaths))});
            }

            var weaponRow = try conn.rows("select attacker_weapon, count(1) as kills, avg(distance) as avg_distance from kill_data where attacker_uid = ?1 group by attacker_weapon", .{player});
            defer weaponRow.deinit();

            try writeStream.objectField("weapon_stats");
            try writeStream.beginArray();
            while (weaponRow.next()) |r| {
                try writeStream.beginObject();
                try writeStream.objectField("weapon");
                try writeStream.write(r.text(0));
                try writeStream.objectField("kills");
                try writeStream.write(r.int(1));
                try writeStream.objectField("avg_distance");
                try writeStream.print("{d}", .{r.float(2)});
                try writeStream.endObject();
            }
            try writeStream.endArray();
            try writeStream.endObject();
            res.status = 200;
            res.content_type = httpz.ContentType.JSON;
            return;
        } else {
            res.status = 404;
            res.body = "Not Found";
            return;
        }
    } else {
        res.status = 501;
        res.body = "Not Implemented";
        return;
    }
}
