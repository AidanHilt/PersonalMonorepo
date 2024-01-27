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
