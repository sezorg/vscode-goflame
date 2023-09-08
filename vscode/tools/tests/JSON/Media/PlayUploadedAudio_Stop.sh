#!/bin/sh

. "./../../CameraConfiguration.sh"

JSON=$(
	cat <<DELIMITER
{
	"Mode": "Stop"
}
DELIMITER
)
json_test media/PlayUploadedAudio
