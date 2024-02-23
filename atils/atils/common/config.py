import logging
import os

from atils.common.settings import settings


def get_full_atils_dir(dir_name: str) -> str:
    """
    Given the name of a subdirectory, return the result of using os.join
    on that directory and the directory where our monorepo is installed
    Args:
        dir_name (str): The name of the subdirectory to join
    Returns:
        str: The full path to the subdirectory
    """
    return os.path.join(settings.INSTALL_DIR, settings[dir_name])


def get_logging_level() -> int:
    """
    Return the logging level configured. We use this function so we return the
    constants in the logging module, rather than a string we need to parse anyway
    """
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
        logging.warning("No log level set, defaulting to INFO")
        return logging.INFO
