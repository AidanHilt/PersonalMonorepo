import logging
import os

from atils.common.settings import settings


def get_full_atils_dir(dir_name: str) -> str:
    return os.path.join(settings.INSTALL_DIR, settings[dir_name])


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
