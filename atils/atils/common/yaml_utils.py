import logging

import yaml
from deepdiff import DeepDiff

logging.basicConfig(level=logging.DEBUG)


def compare_yaml_strings(yaml_str_1: str, yaml_str_2: str):
    """
    Given two string representing valid yaml, convert them to dictionaries and compare using
    deepdiff. Return false if there are differences, true if there are no differences.
    Args:
        yaml_str_1 (str): A string representing a yaml object
        yaml_str_2 (str): A string representing a yaml object
    Returns:
        bool: True if there are no differences, False if there are differences.
    """
    yaml_dict_1 = yaml.safe_load(yaml_str_1)
    yaml_dict_2 = yaml.safe_load(yaml_str_2)

    return _compare_yaml_dicts(yaml_dict_1, yaml_dict_2)


def compare_yaml_files(yaml_file_1: str, yaml_file_2: str) -> bool:
    """
    Given two strings that represent the paths to yaml files, load their contents as strings,
    convert them to dictionaries and compare using deepdiff. Return false if there are differences,
    true if there are no differences.
    Args:
        yaml_str_1 (str): A string representing a yaml object
        yaml_str_2 (str): A string representing a yaml object
    Returns:
        bool: True if there are no differences, False if there are differences.
    """
    with open(yaml_file_1, "r") as f1, open(yaml_file_2, "r") as f2:
        yaml_file_1_contents = f1.read()
        yaml_file_2_contents = f2.read()

    yaml_dict_1: dict = yaml.safe_load(yaml_file_1_contents)
    yaml_dict_2: dict = yaml.safe_load(yaml_file_2_contents)

    return _compare_yaml_dicts(yaml_dict_1, yaml_dict_2)


def find_item_index(search_level: str, item_name: str, yaml_data: dict) -> int:
    """
    Given a python object representing a kubeconfig file, a search level representing a resource type
    to search in, and an item name, return the index of the item in the yaml_data object.
    Args:
        search_level (str): The resource type to search in
        item_name (str): The name of the item to search for
        yaml_data (object): The python object representing the kubeconfig file
    Returns:
        int: The index of the item in the yaml_data object, or -1 if the item is not found.
    """
    for i, item in enumerate(yaml_data[search_level]):
        if item["name"] == item_name:
            return i
    return -1


def merge_kubeconfigs(
    kubeconfig1: str,
    kubeconfig2: str,
    kubeconfig1_cluster_name: str,
    kubeconfig2_cluster_name: str,
    kubeconfig1_user_name: str,
    kubeconfig2_user_name: str,
    kubeconfig1_context_name: str,
    kubeconfig2_context_name: str,
) -> str:
    """
    Given two kubeconfigs, and the names of the clusters and users to copy, merge the second kubeconfig into the first.
    Args:
        kubeconfig1 (str): The path to the first kubeconfig file
        kubeconfig2 (str): The path to the second kubeconfig file
        kubeconfig1_cluster_name (str): The name of the cluster in the first kubeconfig to copy to
        kubeconfig2_cluster_name (str): The name of the cluster in the second kubeconfig to copy from
        kubeconfig1_user_name (str): The name of the user in the first kubeconfig to copy to
        kubeconfig2_user_name (str): The name of the user in the second kubeconfig to copy from
        kubeconfig1_context_name (str): The name of the context in the first kubeconfig to copy to
        kubeconfig2_context_name (str): The name of the context in the second kubeconfig to copy from
    Returns:
        str: The path to the merged kubeconfig file.
    """
    # Load the YAML data from both kubeconfig files
    with open(kubeconfig1, "r") as f1, open(kubeconfig2, "r") as f2:
        kubeconfig_data1: dict = yaml.safe_load(f1)
        kubeconfig_data2: dict = yaml.safe_load(f2)

    # Cluster copying section
    data_1_index = find_item_index(
        "clusters", kubeconfig1_cluster_name, kubeconfig_data1
    )
    data_2_index = find_item_index(
        "clusters", kubeconfig2_cluster_name, kubeconfig_data2
    )

    kubeconfig_data1 = _replace_item_in_yaml_array(
        kubeconfig_data1,
        "clusters",
        data_1_index,
        kubeconfig_data2,
        "clusters",
        data_2_index,
    )

    # Copy the user section from kubeconfig2 to kubeconfig1
    data_1_index = find_item_index("users", kubeconfig1_user_name, kubeconfig_data1)
    data_2_index = find_item_index("users", kubeconfig2_user_name, kubeconfig_data2)

    kubeconfig_data1 = _replace_item_in_yaml_array(
        kubeconfig_data1, "users", data_1_index, kubeconfig_data2, "users", data_2_index
    )

    # Copy the context section from kubeconfig2 to kubeconfig1
    data_1_index = find_item_index(
        "contexts", kubeconfig1_context_name, kubeconfig_data1
    )

    data_2_index = find_item_index(
        "contexts", kubeconfig2_context_name, kubeconfig_data2
    )

    kubeconfig_data1 = _replace_item_in_yaml_array(
        kubeconfig_data1,
        "contexts",
        data_1_index,
        kubeconfig_data2,
        "contexts",
        data_2_index,
    )

    # Serialize the combined kubeconfig data and return it as a string
    return yaml.dump(kubeconfig_data1)


def _compare_yaml_dicts(yaml_dict_1: dict, yaml_dict_2: dict) -> bool:
    """
    Given two dictionaries representing yaml files, compare them using deepdiff. Return false if there are differences,
    true if there are no differences.
    Args:
        yaml_dict_1 (dict): A dictionary representing a yaml object
        yaml_dict_2 (dict): A dictionary representing a yaml object
    Returns:
        bool: True if there are no differences, False if there are differences.
    """
    diff = DeepDiff(yaml_dict_1, yaml_dict_2, ignore_order=True)

    if len(diff) > 0:
        return False
    else:
        return True


def _replace_item_in_yaml_array(
    yaml_dict_1: dict,
    yaml1_array_name: str,
    yaml1_array_index: int,
    yaml_dict_2: dict,
    yaml2_array_name: str,
    yaml2_array_index: int,
) -> dict:
    """
    Given two dictionaries representing yaml files, replace or append the item at yaml_dict_1[yaml1_array_name]
    [yaml1_array_index] with the item at yaml_dict_2[yaml2_array_name][yaml2_array_index]. Return yaml_dict_1
    with the items replaced, or appended

    Args:
        yaml_dict_1: The dictionary representation of the target yaml file
        yaml1_array_name: The name of the array at the top level of the yaml file to replace
        yaml1_array_index: The index of the item in the array to replace
        yaml_dict_2: The dictionary representation of the source yaml file
        yaml2_array_name: The name of the array at the top level of the yaml file to use as a source
        yaml2_array_index: The index of the item in the array to use as a source

    Returns:
        dict: The dictionary representation of the target yaml file with the items replaced, or appended.
    """
    if yaml1_array_index > -1:
        yaml_dict_1[yaml1_array_name][yaml1_array_index] = yaml_dict_2[
            yaml2_array_name
        ][yaml2_array_index]
    else:
        yaml_dict_1[yaml1_array_name].append(
            yaml_dict_2[yaml2_array_name][yaml2_array_index]
        )
    return yaml_dict_1
