#!/bin/sh
docker-compose down

rm -rf ~/apps/postgresql

docker-compose up -d