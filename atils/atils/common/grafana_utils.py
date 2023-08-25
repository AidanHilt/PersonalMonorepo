import os
import requests
import json

def install_dashboards(dashboards: list[dict[str, str]]):
  #TODO get this from a more dynamic config
  GRAFANA_USERNAME: str = os.getenv("GRAFANA_USERNAME")
  GRAFANA_PASSWORD: str = os.getenv("GRAFANA_PASSWORD")

  GRAFANA_HOST: str = "http://dev.local/grafana"
  GRAFANA_DATASOURCE = "prometheus"

  for dashboard in dashboards:
    id = dashboard.get('id')
    version = dashboard.get('version')
    response = requests.get(f'https://grafana.com/api/dashboards/{id}/revisions')
    response_json = json.loads(response.text)
    revision = None
    for item in response_json['items']:
      if 'description' in item and version in item['description']:
        revision = item['revision']
        break
    if revision is None:
      print(f'Error: Version {version} not found for dashboard {id}')
      continue

    # Download the dashboard JSON file for the given revision
    response = requests.get(f'https://grafana.com/api/dashboards/{id}/revisions/{revision}/download')
    dashboard_json = json.loads(response.text)

    # Import the dashboard into Grafana
    data = {
      'dashboard': dashboard_json,
      'overwrite': True,
      'inputs': [
        {
          'name': 'DS_PROMETHEUS',
          'type': 'datasource',
          'pluginId': 'prometheus',
          'value': GRAFANA_DATASOURCE
        }
      ]
    }
    response = requests.post(
      f'{GRAFANA_HOST}/api/dashboards/import',
      headers={
          'Accept': 'application/json',
          'Content-Type': 'application/json'
      },
      auth=(GRAFANA_USERNAME, GRAFANA_PASSWORD),
      json=data,
      verify=False
    )

    # Print the result of the import operation
    if response.status_code == 200:
        print(f'Imported {dashboard_json["title"]} (revision {revision}, id {id})')
    else:
        print(f'Error importing {dashboard_json["title"]}: {response.text}')

