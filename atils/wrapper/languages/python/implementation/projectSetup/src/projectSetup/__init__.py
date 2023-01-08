from rich import print
from rich.prompt import Prompt

#TODO Get project name and description.
projectName = Prompt.ask("What name would you like to give this project")
projectDescription = Prompt.ask("Please provide a description of the project")

#TODO Get additional dependencies
dependencies = []

print("We will now ask you to list extra dependencies your project may require.")


#TODO Initialize entry file

#TODO Put all this info in a form that can be used by the command executor

#TODO Call out to the command executor