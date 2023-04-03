#!/bin/bash

for application in *.yaml; do
    kubectl apply -f $application
done