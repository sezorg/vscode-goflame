#!/bin/sh

. "./../../CameraConfiguration.sh"

JSON=$(
	cat <<DELIMITER
{
	"Mode": "Status"
}
DELIMITER
)
json_test media/PlayUploadedAudio
