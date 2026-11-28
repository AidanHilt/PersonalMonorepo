// Command hello is the simplest possible miura test fixture: a plain HTTP
// server that follows the Knative Serving contract (listen on $PORT) and
// replies to every request. Used by the "minimal" and "http-jwt" valid
// Function fixtures, both of which only exercise triggers.http.
package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
)

func main() {
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintln(w, "hello from miura")
	})

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	log.Printf("hello listening on :%s", port)
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatal(err)
	}
}
