#!/bin/sh

. "./../../CameraConfiguration.sh"

echo "Media.GetVideoAnalyticsConfigurations()"
./ipcam_request.py -a 10.113.11.163 -s media -c GetVideoAnalyticsConfigurations -l {} | jq
