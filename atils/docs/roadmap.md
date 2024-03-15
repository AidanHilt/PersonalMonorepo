# Roadmap

## Tests
We want to create tests for all of our testable functions. By testable functions, we mean either functions that have a return value that we can check, or tests where we can easily mock the calls it makes. We'll get into specifics more as we take up that project

## Better PVC Management
We have a PVC manager job, but its hideous. It creates a job that just runs for a while, then creates an exec command that you have to paste in. Let's fix it with a different hideous solution, that does the job if the PVC is unattached, and otherwise creates an ephemeral container that mounts the volume, then lets you mess with stuff.

### Create a working exec function
### Patch the pod

## Parallel Build
Let certain build steps run in parallel. No idea how that'll work.

## Docker Compose Stacks
We have some fun little Docker compose stacks, for dependencies we might have like a postgres DB or the like. Let's figure out a way to manage the startup and teardown from atils