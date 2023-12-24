To get any of your dotfiles setup, run "stow \<service\>." In order to set Stow up, since by default it'll pull from your current directory, just cp the .stowrc in here under stow/, so that it will pull from this repo and go to your (my) home directory

Using fingerprint for sudo is awesome, so we want to be able to do that at all times. However, /etc/pam.d/sudo can be overriden when we run an update. However, we can run this command to make it immutable:

```sudo chflags simmutable /etc/pam.d/sudo```

and then this one if we need to change it

```sudo chflags nosimmutable /etc/pam.d/sudo```