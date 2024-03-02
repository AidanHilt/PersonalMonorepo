import os

from jinja2 import Environment, FileSystemLoader, FunctionLoader
from pkg_resources import resource_string


def load_from_self(filename: str) -> str:
    """
    Given the name of a template file in the atila/templates directory, load the
    contents of the file as a bytes object

    Args:
        filename (str): The name of the file to load

    Returns:
        bytes: The contents of the file as a bytes object
    """
    return resource_string("atils.templates", filename).decode("utf-8")


def template_file(template_path: str, args_dict: dict) -> str:
    """
    Given the path to a template file, load the template and substitute the
    values in the dictionary into the template.

    Args:
        template_path (str): The path to the template file
        args_dict (dict): A dictionary of values to substitute into the template

    Returns:
        str: The substituted template content as a string.
    """
    env = Environment(loader=FunctionLoader(load_from_self))
    template = env.get_template(os.path.basename(template_path))
    substituted_content = template.render(args_dict)

    return substituted_content


def template_external_file(template_path: str, args_dict: dict) -> str:
    """
    Given the path to a template file that is not bundled with atils,load
    the template and substitute the values in the dictionary into the template.

    Args:
        template_path (str): The path to the template file
        args_dict (dict): A dictionary of values to substitute into the template

    Returns:
        str: The substituted template content as a string.
    """
    env = Environment(loader=FileSystemLoader(os.path.dirname(template_path)))
    template = env.get_template(os.path.basename(template_path))
    substituted_content = template.render(args_dict)

    return substituted_content


def template_file_and_output(
    template_path: str, output_path: str, args_dict: dict
) -> None:
    """
    Given a path to a template file, and arguments, template the file and then output
    it to a file

    Args:
        template_path (str): The path to the template file
        output_path (str): The path to the output file
        args_dict (dict, optional): A dictionary of values to substitute into the template. Defaults to None.
    """
    substituted_content = template_file(template_path, args_dict)

    with open(output_path, "w") as output_file:
        output_file.write(substituted_content)
