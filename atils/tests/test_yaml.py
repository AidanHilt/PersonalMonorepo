import yaml
import pytest

from atils.common import yaml_utils

@pytest.fixture
def full_kubeconfig():
  return "/Users/ahilt/PersonalMonorepo/atils/tests/files/yaml/full_kubeconfig_example.yaml"

@pytest.fixture
def dev_kubeconfig():
  return "/Users/ahilt/PersonalMonorepo/atils/tests/files/yaml/dev_kubeconfig_example.yaml"

@pytest.fixture
def combined_kubeconfig():
  return "/Users/ahilt/PersonalMonorepo/atils/tests/files/yaml/merged_kubeconfig_example.yaml"

def test_comparison_function_equal(full_kubeconfig):
  assert yaml_utils.compare_yaml_files(full_kubeconfig, full_kubeconfig)

def test_comparison_function_not_equal(full_kubeconfig, dev_kubeconfig):
  assert not(yaml_utils.compare_yaml_files(full_kubeconfig, dev_kubeconfig))

def test_kubeconfig_merge(full_kubeconfig, dev_kubeconfig, combined_kubeconfig):
  # Merge the kubeconfigs using the yaml_utils library
  merged_kubeconfig = yaml_utils.merge_kubeconfigs(full_kubeconfig, dev_kubeconfig)

  # Load the expected output file using PyYAML
  with open(combined_kubeconfig, 'r') as f3:
    expected_output = yaml.safe_load(f3)

  expected_output_str = yaml.dump(expected_output)

  # Compare the merged kubeconfig to the expected output
  assert yaml_utils.compare_yaml_strings(expected_output_str, merged_kubeconfig)

