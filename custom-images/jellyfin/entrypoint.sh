#!/bin/bash

# Turning on Bash's job control, so we can run the configuration processes, then put Jellyfin back to the foreground
set -m

set -e

export ADD_TIME=$(date +"%Y-%m-%d %H:%M:%S.%N")

if [[ ! -z "${JELLYFIN__API_KEY}" ]]; then
  apiKeyExists=$(sqlite3 /config/data/jellyfin.db "SELECT COUNT(*) FROM ApiKeys WHERE AccessToken='$JELLYFIN__API_KEY' and Id=1")

  if [[ $apiKeyExists -eq 0 ]]; then
    (cat /setup_scripts/api_key.sql | envsubst) > api_key_filled.sql
    sqlite3 /config/data/jellyfin.db < api_key_filled.sql
    rm api_key_filled.sql
  fi
fi

if [[ ! -z "${JELLYFIN__USERNAME}" ]]; then
  if [[ ! -z "${JELLYFIN__PASSWORD}" ]]; then
    # The whole point of this exercise is to not have to go through the setup wizard, so let's set that config. This needs to be set
    # before the app starts
    sed -i 's/<IsStartupWizardCompleted>false<\/IsStartupWizardCompleted>/<IsStartupWizardCompleted>true<\/IsStartupWizardCompleted>/' /config/config/system.xml
  fi
fi

baseUrl=""

if [[ ! -z "${JELLYFIN__BASE_URL}" ]]; then
  baseUrl="$JELLYFIN__BASE_URL"
  sed -i "s@<BaseUrl>*<\/BaseUrl>@<BaseUrl>$JELLYFIN__BASE_URL<\/BaseUrl>@g" /config/config/network.xml
fi

/jellyfin/jellyfin --ffmpeg /usr/lib/jellyfin-ffmpeg/ffmpeg &

sleep 5

if [[ ! -z "${JELLYFIN__USERNAME}" ]]; then
  if [[ -z "$(curl 'http://localhost:8096/Users' -H 'Authorization: MediaBrowser Token="'"$JELLYFIN__API_KEY"'"' | jq '.[] | select(.Name | contains("'"$JELLYFIN__USERNAME"'")) | .Name')" ]]; then
    if [[ ! -z "${JELLYFIN__PASSWORD}" ]]; then
      user_body=$(curl "http://localhost:8096$baseUrl/Users/New" -H 'accept: application/json' -H 'Content-Type: application/json' -H 'Authorization: MediaBrowser Token="'"$JELLYFIN__API_KEY"'"' -d '{ "Name": "'"$JELLYFIN__USERNAME"'", "Password": "'"$JELLYFIN__PASSWORD"'"}')
      user_id=$(echo $user_body | jq -r '.Id' | tr -d '"')
      modified_user_policy=$(echo $user_body | jq -r '.Policy' | jq -r '.IsAdministrator=true')
      curl "http://localhost:8096$baseUrl/Users/$user_id/Policy" -H 'accept: application/json' -H 'Content-Type: application/json' -H 'Authorization: MediaBrowser Token="'"$JELLYFIN__API_KEY"'"' -d "$modified_user_policy"
    else
      echo "JELLYFIN__USERNAME was set, but JELLYFIN__PASSWORD was not. Skipping user configuration"
    fi
  fi
fi

# This is how we push jellyfin back to the front
fg %1