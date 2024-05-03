import sys

from atils import argocd
from atils import atils_kubernetes as kubernetes
from atils import build, helm, jobs, test


def main():
    if len(sys.argv) < 2:
        print("Atils requires at least one subcommand argument.")
        sys.exit(1)

    script_name: str = sys.argv[1]

    if script_name == "kubernetes":
        kubernetes.main(sys.argv[2:])
    elif script_name == "argocd":
        argocd.main(sys.argv[2:])
    elif script_name == "build":
        build.main(sys.argv[2:])
    elif script_name == "job" or script_name == "jobs":
        jobs.main(sys.argv[2:])
    elif script_name == "helm":
        helm.main(sys.argv[2:])
    elif script_name == "test":
        test.main(sys.argv[2:])
    elif script_name == "help" or script_name == "--help":
        print(
            "Collection of utility scripts. For more information, call one of the subcommands with '--help'"
        )
        print("Usage: atils <subcommand> [options]")
        print("Subcommands:")
        print("  kubernetes: Manage Kubernetes resources")
        print("  argocd: Manage Argo CD resources")
        print("  build: Manage build resources")
        print("  job: Manage job resources")
        print("  helm: Manage Helm resources")
        sys.exit(0)
    else:
        print(f"Unrecognized subcommand: {script_name}")
        print("Valid subcommands are: kubernetes, argocd, build, job, helm")
        sys.exit(1)
