// Command cron-sink is a miura test fixture invoked via triggers.schedules:
// it logs every CloudEvent delivered on a Knative PingSource tick. See the
// "schedule" and "events-and-schedule" valid Function fixtures. It shares
// its implementation with event-sink via the internal/eventlog package.
package main

import (
	"log"

	"github.com/AidanHilt/PersonalMonorepo/kubernetes/operators/operators/miura/test/functions/internal/eventlog"
)

func main() {
	if err := eventlog.RunServer("cron-sink"); err != nil {
		log.Fatal(err)
	}
}
