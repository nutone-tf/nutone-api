const std = @import("std");
const httpz = @import("httpz");
const zqlite = @import("zqlite");
const queries = @import("queries.zig");
const utility = @import("utility.zig");
const KillData = @import("types.zig").KillData;

const dbFlags = zqlite.OpenFlags.Create | zqlite.OpenFlags.EXResCode;
var connPtr: *const zqlite.Conn = undefined;
var gpa = std.heap.GeneralPurposeAllocator(.{}){};

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
    const cors = try server.middleware(httpz.middleware.Cors, .{
        .origin = "https://nutone.okudai.dev/",
    });
    var router = try server.router(.{ .middlewares = &.{cors} });

    router.get("/v1/players/:id", getPlayerData, .{});
    router.get("/v1/players", getAllPlayerData, .{});
    router.get("/v1/servers", getServerList, .{});
    router.post("/v1/data", insertServerData, .{});

    try server.listen();
}

fn initDB() !void {
    var conn = connPtr.*;
    try conn.exec(queries.createTokensTable, .{});
    try conn.exec(queries.createPlayersTable, .{});
    try conn.exec(queries.createServersTable, .{});
    try conn.exec(queries.createMatchesTable, .{});
    try conn.exec(queries.createKillDataTable, .{});

    try conn.exec(queries.createKillDataTimestampIDX, .{});
    try conn.exec(queries.createKillDataServerIDX, .{});
    try conn.exec(queries.createKillDataAttackerIDX, .{});
    try conn.exec(queries.createKillDataVictimIDX, .{});
}

fn insertServerData(req: *httpz.Request, res: *httpz.Response) !void {
    var conn = connPtr.*;
    var serverToken: ?[]const u8 = null;
    const allocator = gpa.allocator();
    var parsedData: ?std.json.Parsed(KillData) = null;
    defer if (parsedData) |pD| pD.deinit();

    if (try utility.isValidToken(conn, req)) {
        serverToken = req.header("token").?;
        if (req.body()) |kill| {
            parsedData = utility.readKillData(allocator, kill) catch {
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
            if (!try utility.isValidServer(conn, serverToken.?, data.server_id)) {
                res.status = 403;
                res.body = "Forbidden";
                return;
            }
            try conn.exec(
                queries.insertServerData,
                .{ data.server_id, data.server_name, serverToken },
            );
            try conn.exec(
                queries.insertPlayerData,
                .{ data.attacker_uid, data.attacker_name, data.victim_uid, data.victim_name },
            );
            try conn.exec(
                queries.insertMatchData,
                .{ data.match_id, data.server_id, data.game_mode, data.map },
            );
            try conn.exec(
                queries.insertKillData,
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

fn getPlayerData(req: *httpz.Request, res: *httpz.Response) !void {
    var conn = connPtr.*;
    var uid: ?[]const u8 = null;
    var writeStream = std.json.writeStream(res.writer(), .{});
    var queryParameters = try req.query();
    const weapon = queryParameters.get("weapon");
    const server = queryParameters.get("server");

    defer writeStream.deinit();
    if (req.param("id")) |id| {
        var row: ?zqlite.Row = null;
        defer if (row) |r| r.deinit();

        if (try conn.row(queries.getPlayerUID, .{id})) |r| {
            row = r;
        }

        if (row) |r| {
            uid = r.text(0);
        }

        if (uid) |player| {
            var currentNameRow = try conn.rows(queries.getPlayerNameFromUID, .{player});
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
            if (weapon != null and server != null) {
                const weaponRow = try conn.row(queries.getPlayerSpecificWeaponForServerData, .{ player, weapon, server });
                defer if (weaponRow) |r| r.deinit();
                var kills: i64 = 0;
                var distance: f64 = 0;
                if (weaponRow) |r| {
                    kills = r.int(0);
                    distance = r.float(1);
                }
                try writeStream.objectField("kills");
                try writeStream.write(kills);
                try writeStream.objectField("avg_distance");
                try writeStream.print("{d}", .{distance});
            } else if (weapon != null) {
                const weaponRow = try conn.row(queries.getPlayerSpecificWeaponData, .{ player, weapon });
                defer if (weaponRow) |r| r.deinit();
                var kills: i64 = 0;
                var distance: f64 = 0;
                if (weaponRow) |r| {
                    kills = r.int(0);
                    distance = r.float(1);
                }
                try writeStream.objectField("kills");
                try writeStream.write(kills);
                try writeStream.objectField("avg_distance");
                try writeStream.print("{d}", .{distance});
            } else if (server != null) {
                const currentKillsRow = try conn.row(queries.getPlayerKillsForServer, .{ player, server });
                var kills: i64 = 0;
                defer if (currentKillsRow) |r| r.deinit();

                const currentDeathsRow = try conn.row(queries.getPlayerDeathsForServer, .{ player, server });
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

                var weaponRow = try conn.rows(queries.getPlayerAllWeaponForServerData, .{ player, server });
                defer weaponRow.deinit();

                try writeStream.objectField("weapon_stats");
                try writeStream.beginObject();
                while (weaponRow.next()) |r| {
                    try writeStream.objectField(r.text(0));
                    try writeStream.beginObject();
                    try writeStream.objectField("kills");
                    try writeStream.write(r.int(1));
                    try writeStream.objectField("avg_distance");
                    try writeStream.print("{d}", .{r.float(2)});
                    try writeStream.endObject();
                }
                try writeStream.endObject();
            } else {
                const currentKillsRow = try conn.row(queries.getPlayerKills, .{player});
                var kills: i64 = 0;
                defer if (currentKillsRow) |r| r.deinit();

                const currentDeathsRow = try conn.row(queries.getPlayerDeaths, .{player});
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

                var weaponRow = try conn.rows(queries.getPlayerAllWeaponData, .{player});
                defer weaponRow.deinit();

                try writeStream.objectField("weapon_stats");
                try writeStream.beginObject();
                while (weaponRow.next()) |r| {
                    try writeStream.objectField(r.text(0));
                    try writeStream.beginObject();
                    try writeStream.objectField("kills");
                    try writeStream.write(r.int(1));
                    try writeStream.objectField("avg_distance");
                    try writeStream.print("{d}", .{r.float(2)});
                    try writeStream.endObject();
                }
                try writeStream.endObject();
            }
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

fn getAllPlayerData(req: *httpz.Request, res: *httpz.Response) !void {
    var conn = connPtr.*;
    var writeStream = std.json.writeStream(res.writer(), .{});

    defer writeStream.deinit();

    var queryParameters = try req.query();
    var page = std.fmt.parseInt(u32, queryParameters.get("page") orelse "1", 10) catch 1;
    if (page < 1) {
        page = 1;
    }
    const weapon = queryParameters.get("weapon");
    const server = queryParameters.get("server");
    var allPlayersRow: zqlite.Rows = undefined;
    var resultsRow: ?zqlite.Row = undefined;
    var results: i64 = 0;
    var pages: i64 = 0;

    if (weapon != null and server != null) {
        allPlayersRow = try conn.rows(queries.getAllPlayerDataForWeaponAndServer, .{ weapon, server, 25, 25 * (page - 1) });
        resultsRow = try conn.row(queries.getAllPlayerDataForWeaponAndServerResultCount, .{ weapon, server });
    } else if (weapon != null) {
        allPlayersRow = try conn.rows(queries.getAllPlayerDataForWeapon, .{ weapon, 25, 25 * (page - 1) });
        resultsRow = try conn.row(queries.getAllPlayerDataForWeaponResultCount, .{weapon});
    } else if (server != null) {
        allPlayersRow = try conn.rows(queries.getAllPlayerDataForServer, .{ server, 25, 25 * (page - 1) });
        resultsRow = try conn.row(queries.getAllPlayerDataForServerResultCount, .{server});
    } else {
        allPlayersRow = try conn.rows(queries.getAllPlayerData, .{ 25, 25 * (page - 1) });
        resultsRow = try conn.row(queries.getAllPlayerDataResultCount, .{});
    }

    if (resultsRow) |r| {
        results = r.int(0);
    }

    pages = switch (results) {
        0 => 0,
        else => std.math.divCeil(i64, results, 25) catch 0,
    };

    defer allPlayersRow.deinit();
    defer if (resultsRow) |r| r.deinit();

    try writeStream.beginObject();
    try writeStream.objectField("players");
    try writeStream.beginObject();
    if (weapon) |_| {
        while (allPlayersRow.next()) |r| {
            try writeStream.objectField(r.text(0));
            try writeStream.beginObject();
            try writeStream.objectField("name");
            try writeStream.write(r.text(1));
            try writeStream.objectField("kills");
            try writeStream.write(r.int(2));
            try writeStream.objectField("avg_distance");
            try writeStream.print("{d}", .{r.float(3)});
            try writeStream.endObject();
        }
    } else {
        while (allPlayersRow.next()) |r| {
            try writeStream.objectField(r.text(0));
            try writeStream.beginObject();
            try writeStream.objectField("name");
            try writeStream.write(r.text(1));
            try writeStream.objectField("kills");
            try writeStream.write(r.int(2));
            try writeStream.objectField("deaths");
            try writeStream.write(r.int(3));
            try writeStream.endObject();
        }
    }

    try writeStream.endObject();
    try writeStream.objectField("info");
    try writeStream.beginObject();
    try writeStream.objectField("currentPage");
    try writeStream.write(page);
    try writeStream.objectField("allResults");
    try writeStream.write(results);
    try writeStream.objectField("maxPages");
    try writeStream.write(pages);
    try writeStream.endObject();
    try writeStream.endObject();
    res.status = 200;
    res.content_type = httpz.ContentType.JSON;
    return;
}

fn getServerList(req: *httpz.Request, res: *httpz.Response) !void {
    var conn = connPtr.*;
    var writeStream = std.json.writeStream(res.writer(), .{});

    defer writeStream.deinit();

    var queryParameters = try req.query();
    var page = std.fmt.parseInt(u32, queryParameters.get("page") orelse "1", 10) catch 1;
    if (page < 1) {
        page = 1;
    }
    var resultsRow: ?zqlite.Row = undefined;
    var results: i64 = 0;
    var pages: i64 = 0;

    resultsRow = try conn.row(queries.getServerCount, .{});
    defer if (resultsRow) |r| r.deinit();

    if (resultsRow) |r| {
        results = r.int(0);
    }

    pages = switch (results) {
        0 => 0,
        else => std.math.divCeil(i64, results, 25) catch 0,
    };

    var serversRow = try conn.rows(queries.getServerList, .{});
    defer serversRow.deinit();

    try writeStream.beginObject();
    try writeStream.objectField("servers");
    try writeStream.beginObject();
    while (serversRow.next()) |r| {
        try writeStream.objectField(r.text(0));
        try writeStream.beginObject();
        try writeStream.objectField("server_name");
        try writeStream.write(r.text(1));
        try writeStream.objectField("owner");
        try writeStream.write(r.text(2));
        try writeStream.endObject();
    }
    try writeStream.endObject();
    try writeStream.objectField("info");
    try writeStream.beginObject();
    try writeStream.objectField("currentPage");
    try writeStream.write(page);
    try writeStream.objectField("allResults");
    try writeStream.write(results);
    try writeStream.objectField("maxPages");
    try writeStream.write(pages);
    try writeStream.endObject();
    try writeStream.endObject();
    res.status = 200;
    res.content_type = httpz.ContentType.JSON;
    return;
}
