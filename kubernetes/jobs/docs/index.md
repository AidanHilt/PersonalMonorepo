# Jobs Definitions
These are where our Kubernetes [jobs](https://kubernetes.io/docs/concepts/workloads/controllers/job/), small units of work that we want to be repeatable. These are meant to be called with the [atils](TODO put link to documentation for jobs setup), and most of these definitions contain templates that make them unsuitable for being applied directly. You'll notice that these are all set up in a specific way, with the following structure:
```
<job-name>
|____job.yaml
|____description.txt
```
`job-name` is the name that the command `atils job run` recognizes. Job.yaml, unsurprisingly, is the job definition, and `description.txt` contains a small description used when displaying jobs with the `atils job list` command. For the full documentation of each job, look in the `docs` directory.