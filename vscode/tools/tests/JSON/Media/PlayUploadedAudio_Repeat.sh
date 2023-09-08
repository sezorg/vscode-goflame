#!/bin/sh

. "./../../CameraConfiguration.sh"

JSON=$(
	cat <<DELIMITER
{
	"Mode": "Repeat"
}
DELIMITER
)
json_test media/PlayUploadedAudio
