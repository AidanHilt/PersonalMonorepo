let
  hyperion = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC1fOZ3HBZAi3l5BtE5nvccMTDvKkZLzaVoiVfU9P6QsDObcfoKgeMoQlxeJfMxluJOi4hy+FJgmB9Acly9dScMh3sgJv0TaSXiydMEmsR4giwrSfAP23tvLpKiyfTMNGptMYmrUgyvuau2nVbG39DPVdGMv6b5DUEDieu694HwtDIUF+UJsMl8zxVe0ATpzmZnCxd1WOHN0jYaIGa18pW73reIYkiGfrbsjmNSl/W3n0v3mAUhQHrPBS/Tp8zGB2LJ5rIs14hC87gaHL9XIozWpzFK2g0Lde/iaJaulvWYnvZbqxOLEHSi94YrNu8Qlj1gT/TRW9cQwzlkbZdncfCqmSY7rQ8jVTddQcypRAizkczBYeqYvQxEc21x48EVlWZokOrG3f0jZhhgo7T+TsSOaWc5UeYTMtsBCcQSyK7bvaXXLLYN0psmzvaF2w/yH4krPpKHl+3qhEw1IAW8s251gZ1Fu0MtFX+qpMzmJkJU/k2dTRjoCrqqA8MG5ZcFsBM= ahilt@hyperion.lan";
  vm = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDZF1tLDyGrJxhNWtvyFVcifrxg8A14yzsoa/DGwfFUAh3KLFlp+fH4zI0NfEX/egU0At9n9OT7s4i52XTMVMPYg1TroVYYINfcoEUo7s4JZ3JuFzveCy+j4FVJDVLLYu06KAx2KRNROToEcbsqcCakgHw7Oii+m8lk21v2Gh4/i5i1p1RaboHVHL8Px5TD01xtIxK5SfyozONDaJaArfAbyOiMY9pCu+5Bx0N3vJGtIXL/myBNVgUN+SYxEKLgAY1u/ciPFHXUG3PJeV5Onh7NMYGjOm0XxLiGFOTy/wjZkm79x5bttOUnTf1VoV/JKOUDP34s59Rphk7bX+k6Gn2xrhGgctBFIJIA9JOMpNx1oQFXULoqT84isF6P9bMuGKj/TQeqNk0zg7kOzUoknrrapQuTDtGtjvbx3R3PuUyRnOfRf+JHWHw5DirGYuERERVlPFyrsc3cOmeNwODfUoTSl8Ekq/A6S7dJuvHRMyvWC2BHAlWFJ86GTCM2kw02V3c= root@virtual-machine";
in
{
  "smb-mount-config.age".publicKeys = [ hyperion ];
  "rclone-config.age".publicKeys = [ hyperion ];
  "kubeconfig.age".publicKeys = [ hyperion vm ];
}