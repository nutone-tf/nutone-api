package main

import (
    "database/sql"
    "encoding/json"
    "flag"
    "fmt"
    "log"
    "net/http"

    _ "rsc.io/sqlite"
)

var db *sql.DB

const createTokenTableSQL string = `
CREATE TABLE IF NOT EXISTS tokens (
    token TEXT PRIMARY KEY,
    owner TEXT
);`

const createKillDataTableSQL string = `
CREATE TABLE IF NOT EXISTS kill_data (
    match_id                  TEXT PRIMARY KEY,
    server_name               TEXT,
    game_mode                 TEXT,
    game_time                 REAL,
    map                       TEXT,
    attacker_name             TEXT,
    attacker_id               TEXT,
    attacker_current_weapon   TEXT,
    attacker_weapon_1         TEXT,
    attacker_weapon_2         TEXT,
    attacker_weapon_3         TEXT,
    attacker_offhand_weapon_1 TEXT,
    attacker_offhand_weapon_2 TEXT,
    attacker_titan            TEXT,
    attacker_x                REAL,
    attacker_y                REAL,
    attacker_z                REAL,
    victim_name               TEXT,
    victim_id                 TEXT,
    victim_current_weapon     TEXT,
    victim_weapon_1           TEXT,
    victim_weapon_2           TEXT,
    victim_weapon_3           TEXT,
    victim_offhand_weapon_1   TEXT,
    victim_offhand_weapon_2   TEXT,
    victim_titan              TEXT,
    victim_x                  REAL,
    victim_y                  REAL,
    victim_z                  REAL,
    cause_of_death            TEXT,
    distance                  REAL
);`

func dbInit() {
    _, err := db.Exec(createTokenTableSQL)
    if err != nil {
        log.Fatal(err)
    }

    _, err = db.Exec(createKillDataTableSQL)
    if err != nil {
        log.Fatal(err)
    }
}

func dbHasToken(token string) bool {
    if (db == nil) {
        fmt.Println("Database handler is nil")
        return false
    }

    var foundToken string
    var foundOwner string

    row := db.QueryRow("SELECT token, owner FROM tokens WHERE token = ?", token)
    err := row.Scan(&foundToken, &foundOwner)
    if err == sql.ErrNoRows {
        return false
    } else if err != nil {
        log.Fatal(err)
    }

    fmt.Printf("Found token '%s' for '%s'\n", foundToken, foundOwner)
    return true
}

func isValidRequest(r *http.Request) bool {
    isValid := false
    for name, headers := range r.Header {
        for _, v := range headers {
            if name == "Token"{
                isValid = dbHasToken(v)
            }
        }
    }

    return isValid
}

// Returns 200 if request has a valid token in 'Bearer' header
func authHandler(w http.ResponseWriter, r *http.Request) {
    isValid := isValidRequest(r)
    if isValid {
        w.WriteHeader(http.StatusOK)
    } else {
        w.WriteHeader(http.StatusUnauthorized)
        w.Header().Set("Content-Type", "application/json")
        resp := make(map[string]string)
        resp["message"] = "Invalid token"
        jsonResp, _ := json.Marshal(resp)
        w.Write(jsonResp)
    }
}

func dataHandler(w http.ResponseWriter, r *http.Request) {
    isValid := isValidRequest(r)
    if isValid {
        // TODO: 2. parse JSON, 3. insert into DB
        w.WriteHeader(http.StatusOK)
    } else {
        w.WriteHeader(http.StatusUnauthorized)
        w.Header().Set("Content-Type", "application/json")
        resp := make(map[string]string)
        resp["message"] = "Invalid token"
        jsonResp, _ := json.Marshal(resp)
        w.Write(jsonResp)
    }
}

func main() {

    var portFlag = flag.Int("p", 8080, "port to listen for HTTP requests")
    var dbFlag = flag.String("d", "nutone.db", "path to SQLite3 database")
    flag.Parse()

    fmt.Printf("Starting Nutone API on port %d with database '%s'...\n", *portFlag, *dbFlag)

    var err error
    db, err = sql.Open("sqlite3", *dbFlag)
    if err != nil {
        log.Fatal(err)
    }

    dbInit()

    http.HandleFunc("/auth", authHandler)
    http.HandleFunc("/data", dataHandler)

    http.ListenAndServe(":8080", nil)
}
