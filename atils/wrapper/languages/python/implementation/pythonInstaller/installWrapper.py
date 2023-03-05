#===========================
#Imports
#===========================
#This allows us to flexibly run commands
import subprocess

'''
Note: This one will need to be simple. This is the script that walks so our
opinionated Python setup can run. It's a bootstrap, and this script should be the
bottom of that ladder.
'''

def buildAndReturnBoundaryString(message, input=False):
    if(message):
        boundaryString = ""
        boundaryStringLength = 0

        for i in range(0, len(message)):
            boundaryStringLength += 1

        if input:
            for i in range(0, len(message) // 3):
                boundaryStringLength += 1
        else:
            for i in range(0, len(message) // 5):
                boundaryStringLength += 1

        if boundaryStringLength > 93:
            boundaryStringLength = 93

        for i in range(0, boundaryStringLength):
            boundaryString += "="

        return boundaryString

    else:
        return "\n==================\n"

def printBlockedMessage(message):
    boundaryString = buildAndReturnBoundaryString(message)

    print(boundaryString)
    print(message)
    print(boundaryString + "\n")


def waitForEnterKey(message):
    boundaryString = buildAndReturnBoundaryString(message, True)

    print(boundaryString)
    input(message + ": ")
    print(boundaryString + "\n")

def runCommand(command):
    commandResult = subprocess.run(["sh", "-c", command], capture_output=True, text=True)
    printBlockedMessage(commandResult.stdout)
    if(commandResult.stderr):
        printBlockedMessage(commandResult.stderr)

#TODO This is a good base to pick up on automating the install process... we'll call
#the steps "install" and "verify"
def installPoetry():
    printBlockedMessage("We'll start by installing Poetry. This is a package manager"
    + " that will enable easier dependency management. By installing and configuring"
    + " just the way we like, it'll help us without being in the way.")
    waitForEnterKey("Ready to install Poetry?: ")

    runCommand("curl -sSL https://install.python-poetry.org | python3 -")

    runCommand("poetry --version")

'''
This should be treated like the main function. Makes it easier to conceptualize what
of this can be imported.
'''
if __name__ == "__main__":
    # printBlockedMessage("Hello Aidan")
    # waitForEnterKey("Ready to get started?")

    installPoetry()
