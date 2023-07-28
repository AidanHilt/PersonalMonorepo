import sys

from atils import atils_kubernetes as kubernetes
from atils import python
from atils import kustomize


def main():
    if len(sys.argv) < 2:
        print("Atils requires at least one subcommand argument.")
        sys.exit(1)

    script_name: str = sys.argv[1]

    # TODO Make this use argparse. We'll get a proper help page up, and error
    # handling for incorrect arguments

    if script_name == "kubernetes":
        kubernetes.main(sys.argv[2:])
    elif script_name == "python":
        python.main(sys.argv[2:])
    elif script_name == "kustomize":
        kustomize.main(sys.argv[2:])
    # Doing it this way because there's no reason to pull it all out of atils_kubernetes
    elif script_name == "argocd":
        full_args = sys.argv[2:]
        full_args.insert(0, "argocd")
        kubernetes.main(full_args)
    else:
        print(f"Unrecognized subcommand: {script_name}")
        print("Valid subcommands are: kubernetes, python, kustomize")
        sys.exit(1)
