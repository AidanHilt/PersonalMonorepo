FROM jellyfin/jellyfin

RUN apt-get update && apt-get install -y sqlite3 gettext jq

COPY entrypoint.sh /entrypoint.sh

COPY setup_scripts /setup_scripts

# Not ideal, but I think this is the best way to get a blank database in our env before we run Jellyfin
# This does mean that it may arbitrarily break if the DB setup changes
COPY config /config

RUN chmod +x /entrypoint.sh

ENTRYPOINT ["bash", "/entrypoint.sh"]
