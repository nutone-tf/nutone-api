package main

import (
    "encoding/json"
    "fmt"
    "net/http"
)

// Returns 200 if request has a valid token in 'Bearer' header
func authHandler(w http.ResponseWriter, r *http.Request) {
    var valid bool = false
    for name, headers := range r.Header {
        for _, v := range headers {
            // TODO: function for checking token (eg. from database)
            if name == "Bearer" && v == "1234" {
                valid = true
            }
        }
    }

    if valid {
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
    // TODO
    // fmt.Fprintf(w, "Url path: %q", r.URL.Path)
}

func main() {
    fmt.Println("Starting Nutone API...")

    http.HandleFunc("/auth", authHandler)
    http.HandleFunc("/data", dataHandler)

    http.ListenAndServe(":8080", nil)
}
