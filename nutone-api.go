package main

import (
	"database/sql"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net/http"
	"strings"
	"sync"

	_ "rsc.io/sqlite"
)

type KillEvent struct {
	MatchID                string  `json:"match_id"`
	ServerID               string  `json:"server_id"`
	ServerName             string  `json:"server_name"`
	GameMode               string  `json:"game_mode"`
	GameTime               float64 `json:"game_time"`
	Map                    string  `json:"map"`
	AttackerName           string  `json:"attacker_name"`
	AttackerId             string  `json:"attacker_id"`
	AttackerCurrentWeapon  string  `json:"attacker_current_weapon"`
	AttackerWeapon1        string  `json:"attacker_weapon_1"`
	AttackerWeapon2        string  `json:"attacker_weapon_2"`
	AttackerWeapon3        string  `json:"attacker_weapon_3"`
	AttackerOffhandWeapon1 string  `json:"attacker_offhand_weapon_1"`
	AttackerOffhandWeapon2 string  `json:"attacker_offhand_weapon_2"`
	AttackerTitan          string  `json:"attacker_titan"`
	AttackerX              float64 `json:"attacker_x"`
	AttackerY              float64 `json:"attacker_y"`
	AttackerZ              float64 `json:"attacker_z"`
	VictimName             string  `json:"victim_name"`
	VictimId               string  `json:"victim_id"`
	VictimCurrentWeapon    string  `json:"victim_current_weapon"`
	VictimWeapon1          string  `json:"victim_weapon_1"`
	VictimWeapon2          string  `json:"victim_weapon_2"`
	VictimWeapon3          string  `json:"victim_weapon_3"`
	VictimOffhandWeapon1   string  `json:"victim_offhand_weapon_1"`
	VictimOffhandWeapon2   string  `json:"victim_offhand_weapon_2"`
	VictimTitan            string  `json:"victim_titan"`
	VictimX                float64 `json:"victim_x"`
	VictimY                float64 `json:"victim_y"`
	VictimZ                float64 `json:"victim_z"`
	CauseOfDeath           string  `json:"cause_of_death"`
	Distance               float64 `json:"distance"`
}

var db *sql.DB
var dbMutex sync.Mutex
var isTest bool

const createTokenTableSQL string = `
CREATE TABLE IF NOT EXISTS tokens (
    token TEXT PRIMARY KEY,
    owner TEXT
);`

const createKillDataTableSQL string = `
CREATE TABLE IF NOT EXISTS kill_data (
    timestamp                 TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    match_id                  TEXT,
    server_id                 TEXT,
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

var indexSQLs []string = []string{
	"CREATE INDEX IF NOT EXISTS kill_data_timestamp_idx     ON kill_data (timestamp);",
	"CREATE INDEX IF NOT EXISTS kill_data_server_id_idx     ON kill_data (server_id);",
	"CREATE INDEX IF NOT EXISTS kill_data_attacker_name_idx ON kill_data (attacker_name);",
	"CREATE INDEX IF NOT EXISTS kill_data_attacker_id_idx   ON kill_data (attacker_id);",
	"CREATE INDEX IF NOT EXISTS kill_data_victim_name_idx   ON kill_data (victim_name);",
	"CREATE INDEX IF NOT EXISTS kill_data_victim_id_idx     ON kill_data (victim_id);",
}

const insertKillEventSQL string = `
INSERT INTO kill_data (
    match_id,                 
    server_id,               
    server_name,               
    game_mode,                
    game_time,                
    map,                      
    attacker_name,             
    attacker_id,              
    attacker_current_weapon,   
    attacker_weapon_1,        
    attacker_weapon_2,        
    attacker_weapon_3,        
    attacker_offhand_weapon_1,
    attacker_offhand_weapon_2,
    attacker_titan,            
    attacker_x,               
    attacker_y,               
    attacker_z,               
    victim_name,               
    victim_id,                
    victim_current_weapon,     
    victim_weapon_1,          
    victim_weapon_2,          
    victim_weapon_3,          
    victim_offhand_weapon_1,   
    victim_offhand_weapon_2,   
    victim_titan,             
    victim_x,                 
    victim_y,                 
    victim_z,                 
    cause_of_death,            
    distance
) VALUES (?, ?, ?, ?, ?, ?, ?, ?,
          ?, ?, ?, ?, ?, ?, ?, ?,
          ?, ?, ?, ?, ?, ?, ?, ?,
          ?, ?, ?, ?, ?, ?, ?, ?);`

const getPlayerStatsSQL string = `
WITH server_kill_data AS (
    SELECT * FROM kill_data
    WHERE CASE WHEN ? = '' THEN 1
               ELSE server_id = ?
          END
), attacker_ids AS (
    SELECT attacker_name AS name,
           attacker_id   AS uid
    FROM server_kill_data
    WHERE ? IN (attacker_name, attacker_id)
    LIMIT 1
), victim_ids AS (
    SELECT victim_name AS name,
           victim_id   AS uid
    FROM server_kill_data
    WHERE ? IN (victim_name, victim_id)
    LIMIT 1
), ids AS (
    SELECT * FROM attacker_ids
    UNION
    SELECT * FROM victim_ids
    LIMIT 1
), nkills AS (
    SELECT COUNT(1) FROM server_kill_data
    WHERE ? IN (attacker_name, attacker_id)
      AND ? NOT IN (victim_name, victim_id)
), ndeaths AS (
    SELECT COUNT(1) FROM server_kill_data
    WHERE ? IN (victim_name, victim_id)
)

SELECT (SELECT name FROM ids) AS name,
       (SELECT uid FROM ids) AS uid,
       (SELECT * FROM nkills) AS kills,
       (SELECT * FROM ndeaths) AS deaths,
       (1.0*(SELECT * FROM nkills)) / (max(1.0*(SELECT * FROM ndeaths), 1.0)) AS kd;`

const getPlayerStatsAllSQL string = `
WITH kills AS (
	SELECT attacker_name AS name, COUNT(1) AS kills
	FROM kill_data WHERE attacker_name <> victim_name
	GROUP BY attacker_name
  ), deaths AS (
	SELECT victim_name AS name, COUNT(1) AS deaths
	FROM kill_data
	GROUP BY victim_name
  )
  
  SELECT k.name, k.kills, d.deaths
  FROM kills k, deaths d
  WHERE k.name = d.name
`

type PlayerStatsSQLResult struct {
	Name   sql.NullString
	UID    sql.NullString
	Kills  int
	Deaths int
	KD     sql.NullFloat64
}

func dbInit() {
	_, err := db.Exec(createTokenTableSQL)
	if err != nil {
		log.Fatal(err)
	}

	_, err = db.Exec(createKillDataTableSQL)
	if err != nil {
		log.Fatal(err)
	}

	for _, indexSQL := range indexSQLs {
		_, err = db.Exec(indexSQL)
		if err != nil {
			log.Fatal(err)
		}
	}
}

func dbHasToken(token string) bool {
	dbMutex.Lock()
	defer dbMutex.Unlock()

	if db == nil {
		log.Fatal("Database unopened, exiting")
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

	log.Printf("Found token '%s' for '%s'\n", foundToken, foundOwner)
	return true
}

func dbInsertKillEvent(k KillEvent) error {
	dbMutex.Lock()
	defer dbMutex.Unlock()

	statement, err := db.Prepare(insertKillEventSQL)
	if err != nil {
		log.Print(err)
		return err
	}

	defer statement.Close()

	_, err = statement.Exec(
		k.MatchID,
		k.ServerID,
		k.ServerName,
		k.GameMode,
		k.GameTime,
		k.Map,
		k.AttackerName,
		k.AttackerId,
		k.AttackerCurrentWeapon,
		k.AttackerWeapon1,
		k.AttackerWeapon2,
		k.AttackerWeapon3,
		k.AttackerOffhandWeapon1,
		k.AttackerOffhandWeapon2,
		k.AttackerTitan,
		k.AttackerX,
		k.AttackerY,
		k.AttackerZ,
		k.VictimName,
		k.VictimId,
		k.VictimCurrentWeapon,
		k.VictimWeapon1,
		k.VictimWeapon2,
		k.VictimWeapon3,
		k.VictimOffhandWeapon1,
		k.VictimOffhandWeapon2,
		k.VictimTitan,
		k.VictimX,
		k.VictimY,
		k.VictimZ,
		k.CauseOfDeath,
		k.Distance,
	)

	return err
}

func dbGetPlayerStats(serverID string, playerNameOrUID string) *PlayerStatsSQLResult {
	dbMutex.Lock()
	defer dbMutex.Unlock()

	var ps PlayerStatsSQLResult
	row := db.QueryRow(
		getPlayerStatsSQL,
		serverID,
		serverID,
		playerNameOrUID,
		playerNameOrUID,
		playerNameOrUID,
		playerNameOrUID,
		playerNameOrUID,
	)

	err := row.Scan(&ps.Name, &ps.UID, &ps.Kills, &ps.Deaths, &ps.KD)
	// TODO: figure out why this doesn't work
	if err == sql.ErrNoRows {
		log.Print("no rows found")
		return nil
	}

	if err != nil {
		log.Print(err)
		return nil
	}

	return &ps
}

func logRequest(r *http.Request) {
	log.Printf("%s: %s %s", r.RemoteAddr, r.Method, r.URL.Path)
}

func sendJSONResponse(w http.ResponseWriter, resp map[string]interface{}) {
	w.Header().Set("Content-Type", "application/json")
	jsonResp, _ := json.Marshal(resp)
	w.Write(jsonResp)
}

func isValidRequest(r *http.Request) bool {
	if isTest {
		return true
	}

	isValid := false
	for name, headers := range r.Header {
		for _, v := range headers {
			if name == "Token" {
				isValid = dbHasToken(v)
			}
		}
	}

	return isValid
}

func sendInvalidTokenResponse(w http.ResponseWriter) {
	w.WriteHeader(http.StatusUnauthorized)
	resp := make(map[string]interface{})
	resp["message"] = "invalid token"
	sendJSONResponse(w, resp)
}

// Returns 200 if request has a valid token in 'Bearer' header
func authHandler(w http.ResponseWriter, r *http.Request) {
	logRequest(r)

	isValid := isValidRequest(r)
	if !isValid {
		sendInvalidTokenResponse(w)
		return
	}

	w.WriteHeader(http.StatusOK)
}

func dataHandler(w http.ResponseWriter, r *http.Request) {
	logRequest(r)

	isValid := isValidRequest(r)
	if !isValid {
		sendInvalidTokenResponse(w)
		return
	}

	var killEvent KillEvent
	err := json.NewDecoder(r.Body).Decode(&killEvent)
	if err != nil {
		log.Print(err)
		http.Error(w, "JSON error", http.StatusBadRequest)
		return
	}

	err = dbInsertKillEvent(killEvent)
	if err != nil {
		log.Print(err)
		http.Error(w, "database error", http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusOK)
}

func playerHandler(w http.ResponseWriter, r *http.Request) {
	logRequest(r)

	serverID := r.URL.Query().Get("server_id")
	playerNameOrUID := strings.TrimPrefix(r.URL.Path, "/players/")

	if playerNameOrUID == "" {
		dbMutex.Lock()
		rows, err := db.Query(getPlayerStatsAllSQL)
		if err != nil {
			log.Print(err)
			return
		}
		resp := make([]map[string]interface{}, 0, 100000)
		var counter int
		for rows.Next() {
			var ps PlayerStatsSQLResult
			if resp[counter] == nil {
				resp[counter] = make(map[string]interface{})
			}
			rows.Scan(&ps.Name, &ps.Kills, &ps.Deaths)
			resp[counter]["name"] = ps.Name.String
			resp[counter]["kills"] = ps.Kills
			resp[counter]["deaths"] = ps.Deaths
			counter++
		}
		w.Header().Set("Content-Type", "application/json")
		jsonResp, _ := json.Marshal(resp)
		w.Write(jsonResp)
	} else {
		ps := dbGetPlayerStats(serverID, playerNameOrUID)
		// TODO: make ErrNoRows work
		if !ps.Name.Valid {
			w.WriteHeader(http.StatusNotFound)
			return
		}

		resp := make(map[string]interface{})
		resp["name"] = ps.Name.String
		resp["uid"] = ps.UID.String
		resp["kills"] = ps.Kills
		resp["deaths"] = ps.Deaths
		resp["kd"] = ps.KD.Float64

		sendJSONResponse(w, resp)
	}
}

//	{
//	    "name": "fvnkhead",
//	    "uid": "1234",
//	    "total": {
//	        "kills": 10,
//	        "deaths": 5,
//	        "kd": 2.0
//	    },
//	    "servers": [
//	        {
//	            "name": "fvnkhead's sticks",
//	            "id": "fvnkhead_sticks", # server_id to be added into convars later
//	            "kills": 5,
//	            "deaths": 0,
//	            "kd": 5.0 # if deaths = 0, calculate kd as if 1
//	        }, {
//	        "name": "fvnkhead's 8v8",
//	        "id": "fvnkhead_big_pvp",
//	        "kills": 5,
//	        "deaths": 5,
//	        "kd": 1.0
//	        }
//	    ]
//	}
//
// GET /players # returns all players
// GET /players/<playername> # returns object like in A
// GET /servers # returns all servers
// GET /servers/<server_id>, e.g. `GET /servers/fvnkhead%27s%20sticks` (can use either URL-encoded server name or server_id) =>
//
//	{
//	      "name": "fvnkhead's sticks",
//	      "id": "fvnkhead_sticks",
//	      "players" [
//	        {
//	         "name": "fvnkhead",
//	         "uid": "1234",
//	          ...
//	        },
//	      ..
//	      ]
//	}
func main() {
	var isTestFlag = flag.Bool("t", false, "enable test mode (bypasses token authentication)")
	var portFlag = flag.Int("p", 8080, "port to listen for HTTP requests")
	var dbFlag = flag.String("d", "nutone.db", "path to SQLite3 database")
	flag.Parse()

	isTest = *isTestFlag

	log.Printf("Starting Nutone API on port %d with database '%s'...\n", *portFlag, *dbFlag)

	var err error
	db, err = sql.Open("sqlite3", *dbFlag)
	if err != nil {
		log.Fatal(err)
	}

	dbInit()

	http.HandleFunc("/auth", authHandler)
	http.HandleFunc("/data", dataHandler)
	http.HandleFunc("/players/", playerHandler)

	host := fmt.Sprintf(":%d", *portFlag)
	http.ListenAndServe(host, nil)
}
