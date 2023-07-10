import os
from jinja2 import Environment, FileSystemLoader, FunctionLoader
from pkg_resources import resource_string

def load_from_self(filename: str):
   return resource_string('atils.templates', filename).decode('utf-8')

def template_file(template_path: str, output_path: str):
  env = Environment(loader=FunctionLoader(load_from_self))

  template = env.get_template(os.path.basename(template_path))

  substituted_content = template.render(var1='value1', var2='value2')  # Replace var1 and var2 with actual values

  with open(output_path, 'w') as output_file:
      output_file.write(substituted_content)
