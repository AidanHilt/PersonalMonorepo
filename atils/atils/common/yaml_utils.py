import yaml
import logging

from deepdiff import DeepDiff

logging.basicConfig(level=logging.DEBUG)

#TODO I think the yaml library has a function to perform this operation. Maybe we need it for the comparison?
def convert_yaml_to_dict(yaml_file: str) -> dict:
  yaml_dict = {}
  with open(yaml_file, "r") as fp:
    docs = yaml.safe_load_all(fp)
    for doc in docs:
      for key, value in doc.items():
        yaml_dict[key] = value
  return yaml_dict

def compare_yaml_strings(yaml_str_1: str, yaml_str_2: str):
  print(type(yaml_str_1))
  print(type(yaml_str_2))
  yaml_dict_1 = yaml.safe_load(yaml_str_1)
  yaml_dict_2 = yaml.safe_load(yaml_str_2)

  diff = DeepDiff(yaml_dict_1, yaml_dict_2, ignore_order=True)

  if len(diff) > 0:
    return False
  else:
    return True

def compare_yaml_files(yaml1, yaml2) -> bool:
  yaml_dict_1: dict = convert_yaml_to_dict(yaml1)
  yaml_dict_2: dict = convert_yaml_to_dict(yaml2)

  diff = DeepDiff(yaml_dict_1, yaml_dict_2, ignore_order=True)

  if len(diff) > 0:
    return False
  else:
    return True

def find_item_index(top_level: str, item_name: str, yaml_data) -> int:
  # Find the index of the "dev-cluster" definition in kubeconfig2
  for i, item in enumerate(yaml_data[top_level]):
    if item["name"] == item_name:
      return i
  return None

# TODO Make this generic, right now it only does dev-cluster
def merge_kubeconfigs(kubeconfig1: str, kubeconfig2: str) -> str:
  # Load the YAML data from both kubeconfig files
  with open(kubeconfig1, "r") as f1, open(kubeconfig2, "r") as f2:
    kubeconfig_data1 = yaml.safe_load(f1)
    kubeconfig_data2 = yaml.safe_load(f2)

  # Cluster copying section

  data_1_index = find_item_index("clusters", "dev-cluster", kubeconfig_data1)
  data_2_index = find_item_index("clusters", "local", kubeconfig_data2)

  # Copy the "dev-cluster" definition from kubeconfig2 to kubeconfig1
  if data_2_index is not None:
    kubeconfig_data1["clusters"][data_1_index] = kubeconfig_data2["clusters"][
      data_2_index
    ]
    kubeconfig_data1["clusters"][data_1_index]["name"] = "dev-cluster"
  else:
    logging.error(f"Could not find a cluster in {kubeconfig2}")
    exit(1)

  # User copying section

  data_1_index = find_item_index("users", "kube-admin-dev", kubeconfig_data1)
  data_2_index = find_item_index("users", "kube-admin-local", kubeconfig_data2)

  # Copy the "dev-cluster" definition from kubeconfig2 to kubeconfig1
  if data_2_index is not None:
    kubeconfig_data1["users"][data_1_index] = kubeconfig_data2["users"][
      data_2_index
    ]
    kubeconfig_data1["users"][data_1_index]["name"] = "kube-admin-dev"
  else:
    logging.error(f"Could not find a user in {kubeconfig2}")
    exit(1)

  # Serialize the combined kubeconfig data and return it as a string
  return yaml.dump(kubeconfig_data1)
