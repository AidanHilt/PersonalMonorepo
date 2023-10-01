from dynaconf import Dynaconf
import logging

settings = Dynaconf(
    envvar_prefix="ATILS",
    settings_files=["settings.yaml", ".secrets.yaml"],
)


def get_logging_level():
    if settings.LOG_LEVEL == "DEBUG":
        return logging.DEBUG
    elif settings.LOG_LEVEL == "INFO":
        return logging.INFO
    elif settings.LOG_LEVEL == "WARNING":
        return logging.WARNING
    elif settings.LOG_LEVEL == "ERROR":
        return logging.ERROR
    elif settings.LOG_LEVEL == "CRITICAL":
        return logging.CRITICAL
    else:
        logging.warning("Could not find a proper log level, defaulting to INFO")
        return logging.INFO


# `envvar_prefix` = export envvars with `export DYNACONF_FOO=bar`.
# `settings_files` = Load these files in the order.
