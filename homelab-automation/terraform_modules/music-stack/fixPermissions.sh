#!/bin/bash

#This script is used to fix permission issues that seem to crop up with lidarr. This script will guide you through the fix.
#You will need to make sure that the terraform is already-installed. 
echo "=============================================================="
echo "You will need to edit the deployment to set the replicas to 0."
echo "=============================================================="
echo "Press any key to continue"
while [ true ] ; do
read -t 3 -n 1
if [ $? = 0 ] ; then
break
fi
done

kubectl -n music edit deployment lidarr

echo "=============================================================================="
echo "Now, you will need to edit the permissions of /config (This one takes a while)" 
echo "=============================================================================="

kubectl run -i --rm --tty ubuntu --overrides='
{
  "kind": "Pod",
  "apiVersion": "v1",
  "metadata": {
    "name": "permissions-fix",
    "namespace": "music"
  },
  "spec": {
    "containers": [
    {
      "name": "ubuntu",
      "image": "ubuntu:22.04",
      "args": ["bash"],
      "stdin": true,
      "stdinOnce": true,
      "tty": true,
      "volumeMounts": [{
        "mountPath": "/config",
        "name": "store"
      }]
    }
    ],
    "volumes": [{
      "name":"store",
      "persistentVolumeClaim": {
        "claimName": "lidarr-config"
      }
    }]
  }
}
'  --image=ubuntu:22.04 --restart=Never --namespace=music -- bash

#This script is used to fix permission issues that seem to crop up with lidarr. This script will guide you through the fix.
#You will need to make sure that the terraform is already-installed. 
echo "=============================================================="
echo "You will need to edit the deployment to set the replicas to 1."
echo "=============================================================="

kubectl -n music edit deployment lidarr