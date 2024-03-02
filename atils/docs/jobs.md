# Job
Commands to run and manage Kubernetes jobs. The jobs that are managed are in the JOBS_DIR directory.

## list
Lists all the jobs available in JOBS_DIR, along with a description if provided. This will also eventually list all the valid arguments for a job

### Arguments
None

## manage-pvc
Launches a special job that mounts a given PVC, and provides tools to interact with the files on the pvc.

### Arguments
`--pvc-name PVC_NAME, -pn PVC_NAME`: The name of the PVC to launch a management pod for
`--namespace NAMESPACE, -n NAMESPACE`: The namespace the PVC is located in. Defaults to current namespace

## run
Runs a job in the JOBS_DIR directory.

### Arguments
`--set`: Can be used multiple times. Sets a value for a key in the job template. Not currently working
`--tag`: Special case for setting a value. Sets the image tag to use