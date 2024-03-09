import sys

from atils import argocd
from atils import atils_kubernetes as kubernetes
from atils import build, helm, jobs


def main():
    if len(sys.argv) < 2:
        print("Atils requires at least one subcommand argument.")
        sys.exit(1)

    script_name: str = sys.argv[1]

    # TODO Make this use argparse. We'll get a proper help page up, and error
    # handling for incorrect arguments

    if script_name == "kubernetes":
        kubernetes.main(sys.argv[2:])
    elif script_name == "argocd":
        argocd.main(sys.argv[2:])
    elif script_name == "build":
        build.main(sys.argv[2:])
    elif script_name == "job":
        jobs.main(sys.argv[2:])
    elif script_name == "helm":
        helm.main(sys.argv[2:])
    else:
        print(f"Unrecognized subcommand: {script_name}")
        print("Valid subcommands are: kubernetes, argocd, build, job, helm")
        sys.exit(1)
