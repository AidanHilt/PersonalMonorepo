{ pkgs, ... }:

{
  defaultValues = "laptop-cluster";

  k8s = {
    primaryNode = true;
  };
}