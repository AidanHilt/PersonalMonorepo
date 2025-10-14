FROM jellyfin/jellyfin:10.10.7

RUN apt-get update && apt-get install -y sqlite3 gettext jq

COPY entrypoint.sh /entrypoint.sh

COPY setup_scripts /setup_scripts

# We copy a blank Jellyfin DB in, and then copy it over in our entrypoint.sh script if it doesn't exist yet. The rest should proceed normally
COPY config /config-templates

RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
