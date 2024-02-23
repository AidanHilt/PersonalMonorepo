# Longhorn Setup
To manage our PVs, we use [Longhorn](https://longhorn.io/). However, Longhorn has some [pre-requisites](https://longhorn.io/docs/1.6.0/deploy/install/#installation-requirements) that must be installed and enabled first.

1. Install open-iscsi
2. Using systemd, ensure that iscsid is running and enabled.