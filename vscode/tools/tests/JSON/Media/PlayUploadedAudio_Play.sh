#!/bin/sh

. "./../../CameraConfiguration.sh"

JSON=$(
	cat <<DELIMITER
{
	"Mode": "Play"
}
DELIMITER
)
json_test media/PlayUploadedAudio
