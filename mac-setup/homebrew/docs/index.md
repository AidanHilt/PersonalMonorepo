# Homebrew Configuration

This directory stores a [brewfile](https://github.com/Homebrew/homebrew-bundle) that we use to automatically install all software for a Mac. This just uses [Homebrew](https://brew.sh/) and [Homebrew Cask](https://github.com/Homebrew/homebrew-cask). This is also where documentation on anything manual that needs to be done to finish installing items. Most of that should be handled in .zshrc, but there may be one-time things.

# Notes and Installation Requirements

## Java Installation
Once Java is installed, run `java --version`. If you get a result like this:

```
The operation couldn’t be completed. Unable to locate a Java Runtime.
Please visit http://www.java.com for information on installing Java.
```

run this command to link everything:

```
sudo ln -sfn /opt/homebrew/opt/openjdk/libexec/openjdk.jdk /Library/Java/JavaVirtualMachines/openjdk.jdk
```