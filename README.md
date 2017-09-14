MythTV backend
==============

Docker container to run a MythTV backend. It also includes MythWeb and HDHomeRun utils.
This container is adapted from an0t8/mythtv-server to get a more recent MythTV version and to add volumes for recordings and video.

## Basic usage

Launch the container via docker:
```
docker run -d --name dropbox thomfab/docker-mythbackend
```
