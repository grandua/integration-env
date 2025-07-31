rem Run "docker login ghcr.io -u grandua -p <MyPatHere>" first
docker push ghcr.io/grandua/atera-db:latest
docker push ghcr.io/grandua/atera-mindsdb:latest

docker tag ateracorp/atera-db-sync:latest ghcr.io/grandua/atera-db-sync:latest
docker push ghcr.io/grandua/atera-db-sync:latest