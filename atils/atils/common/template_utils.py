import os

from jinja2 import Environment, FileSystemLoader, FunctionLoader
from pkg_resources import resource_string


def load_from_self(filename: str):
    return resource_string("atils.templates", filename).decode("utf-8")


def template_file(template_path: str, args_dict: dict):
    env = Environment(loader=FunctionLoader(load_from_self))
    template = env.get_template(os.path.basename(template_path))
    substituted_content = template.render(args_dict)

    return substituted_content


def template_external_file(template_path: str, args_dict: dict):
    env = Environment(loader=FileSystemLoader(os.path.dirname(template_path)))
    template = env.get_template(os.path.basename(template_path))
    substituted_content = template.render(args_dict)

    return substituted_content


# TODO This is going to need to use a dictionary for all the values we may template. Hasn't come up yet though!
def template_file_and_output(
    template_path: str, output_path: str, args_dict: dict = None
):
    substituted_content = template_file(template_path, args_dict)

    with open(output_path, "w") as output_file:
        output_file.write(substituted_content)
