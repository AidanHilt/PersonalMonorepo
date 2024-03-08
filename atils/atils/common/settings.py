from dynaconf import Dynaconf

# We're just setting up a dynaconf settings object, nothing super complex
settings = Dynaconf(
    envvar_prefix="ATILS",
    settings_files=["settings.yaml", ".secrets.yaml"],
    core_loaders=["YAML"],
)
