# Build
Commands to run pre-defined build actions. Because we want to be as off-the-shelf as possible, this means we'll use standard-issue package and dependency managers whenever possible. Add in linters, type-checking, and even possibly formatting, and that all adds up to us wanting one interface to manage our builds, testing, and deployments.

## Command Usage

### list
Lists all the actions and action sets available in the specified directory, or in the current directory if none is specified. Fails if there is no `.atils_buildconfig.json` file in the directory.

#### Arguments
`--actions-only`: Only show individual actions, not action sets
`--action-sets-only`: Only show action sets, not individual actions
`--build-directory`: The path to a directory with a `.atils_buildconfig.json` file. That file will be used as the source for the actions and action sets to list

### build
Runs all, or some actions. By default, runs all actions in the selected `.atils_buildconfig.json`. If nothing is specified, all commands are run as commands, rather than in their command sets (in case order matters). In an action set, commands run with the same order they have normally, with any actions in the middle skipped over. This directory will follow the convention of using the same leading digit for an action set. For example, if you had two action sets, the first one's actions would go `11`, `12`, `13`..., while the second action set's actions would go `21`, `22`, `23`.

#### Arguments
`--actions`: A list of actions. All the actions must be defined in `.atils_buildconfig.json`, or the command fails
`--action-set`: An action set. The action set must be defined in `.atils_buildconfig.json`, or the command fails
`--build-directory`: The path to a directory with a `.atils_buildconfig.json` file. That file will be used as the source for the actions and action sets to run

## The .atils_buildconfig.json File
In order to configure the `atils build` command for a given directory, we use a special file called `.atils_buildconfig.json`. This contains a JSON object, that describes a series of `actions`, and `action-sets`. Actions are basically just aliases to shell commands, which all run from the directory in which the `.atils_buildconfig.json` file is located. Actions sets are groups of actions that work for a related purpose, like a linting command and a testing command. See below for an example of the schema of a build config object
```
{
    "actions": [
        {
            "name": "action_name",
            "command": "exec --command --bar-baz",
            "order": 0,
            "description": "Runs an action, to do something"
        },
        {
            "name": "action_name_2",
            "command": "exec --command --foo=bar",
            "order": 1,
            "ci_only": true
        }

    ],
    "action_sets": [
        {
            "name": "action_set_name",
            "actions": [
                "action_name",
                "action_name_2"
            ],
            "description": "This is a set of actions",
            "strict": false
            "default": false
        }
    ]
}
```
### Actions
`name`: The name of the action. This is how we refer to the action when using the `build` command, and what appears when using the `list` command.
`command`: The command the actions aliases. This is literally just a shell command, so it can be whatever you want, but we don't bundle any command-line tools you might use
`order`: The order that all these commands run in. Lower actions run first
`description` (optional): A description of the action
`ci_only` (optional): Whether or not this action is meant to only run in a CI environment. If this flag is set, the command will fail unless the environment variable ATILS_CI_ENV is set

### Action Sets (optional)
`name`: The name of the action set. This is how we refer to the action when using the `build` command, and what appears when using the `list` command.
`actions`: A list of actions, defined in the `actions` section of the `.atils_buildconfig.json` file.
`description` (optional): A description of the action set
`strict` (optional): Whether or not to run the action set in strict mode (which means that each test must succeed before the next one runs). Defaults to true
`default` (optional): Whether or not this action set is marked as the default one, that runs when no arguments are supplied. Defaults to false

## Well-Known Action Set Names
Since the purpose of this entire exercise is to allow us to use one common interface for all our building needs, we should define some action sets that are commonly used. What actually gets run between projects for these varies, but all of these action sets reflect common activities.

`validate`: Runs code-quality checks, type checks, tests, and anything else that looks at the correctness and adherence to a standard of a project
`local-install`: Builds and installs the project locally. Skips any quality checks, as this is assumed to be used for development work
`ci-build-publish`: Validate the correctness and standard adherence of the code, build the code, and then publish the results to a public repo, like pip or a container repository