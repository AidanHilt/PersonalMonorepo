from dynaconf import Dynaconf

settings = Dynaconf(
    envvar_prefix="ATILS",
    settings_files=["settings.yaml", ".secrets.yaml"],
    core_loaders=["YAML"],
    root_path="/Users/ahilt/PersonalMonorepo/atils/atils/common",
)
