// Command event-sink is a miura test fixture invoked via triggers.events: it
// logs every CloudEvent it receives from a Knative Trigger. See the
// "events" and "events-and-schedule" valid Function fixtures.
package main

import (
	"log"

	"github.com/AidanHilt/PersonalMonorepo/kubernetes/operators/operators/miura/test/functions/internal/eventlog"
)

func main() {
	if err := eventlog.RunServer("event-sink"); err != nil {
		log.Fatal(err)
	}
}
