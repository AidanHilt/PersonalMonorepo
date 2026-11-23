// Package eventlog implements the shared behavior of the event-sink and
// cron-sink test fixtures: an HTTP server that logs every request it
// receives as a CloudEvent delivery (Knative Eventing Triggers and
// PingSources both deliver as POST requests carrying a CloudEvent) and
// replies 204 No Content. The two fixtures differ only in which miura
// trigger invokes them (triggers.events vs triggers.schedules), not in
// behavior, so they share this implementation.
package eventlog

import (
	"io"
	"log"
	"net/http"
	"os"
)

// RunServer starts an HTTP server on $PORT (defaulting to 8080, per the
// Knative Serving contract) that logs every received request. name is
// included in every log line so the two fixtures remain distinguishable in
// output (e.g. "event-sink" vs "cron-sink").
func RunServer(name string) error {
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		handle(name, w, r)
	})

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	log.Printf("%s listening on :%s", name, port)
	return http.ListenAndServe(":"+port, nil)
}

func handle(name string, w http.ResponseWriter, r *http.Request) {
	body, err := io.ReadAll(r.Body)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	defer r.Body.Close()

	log.Printf(
		"%s received event: type=%s source=%s id=%s body=%s",
		name,
		r.Header.Get("Ce-Type"),
		r.Header.Get("Ce-Source"),
		r.Header.Get("Ce-Id"),
		body,
	)

	w.WriteHeader(http.StatusNoContent)
}
