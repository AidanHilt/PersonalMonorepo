let
  hyperion = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC1fOZ3HBZAi3l5BtE5nvccMTDvKkZLzaVoiVfU9P6QsDObcfoKgeMoQlxeJfMxluJOi4hy+FJgmB9Acly9dScMh3sgJv0TaSXiydMEmsR4giwrSfAP23tvLpKiyfTMNGptMYmrUgyvuau2nVbG39DPVdGMv6b5DUEDieu694HwtDIUF+UJsMl8zxVe0ATpzmZnCxd1WOHN0jYaIGa18pW73reIYkiGfrbsjmNSl/W3n0v3mAUhQHrPBS/Tp8zGB2LJ5rIs14hC87gaHL9XIozWpzFK2g0Lde/iaJaulvWYnvZbqxOLEHSi94YrNu8Qlj1gT/TRW9cQwzlkbZdncfCqmSY7rQ8jVTddQcypRAizkczBYeqYvQxEc21x48EVlWZokOrG3f0jZhhgo7T+TsSOaWc5UeYTMtsBCcQSyK7bvaXXLLYN0psmzvaF2w/yH4krPpKHl+3qhEw1IAW8s251gZ1Fu0MtFX+qpMzmJkJU/k2dTRjoCrqqA8MG5ZcFsBM= ahilt@hyperion.lan";
in
{
  "smb-mount-config.age".publicKeys = [ hyperion ];
  "rclone-config.age".publicKeys = [ hyperion ];
  "kubeconfig.age".publicKeys = [ hyperion ];
}