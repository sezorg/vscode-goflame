#!/bin/sh

. "./../../CameraConfiguration.sh"

JSON=$(
	cat <<DELIMITER
{
	"Configuration": {
		"Name": "AEC",
		"UseCount": 2,
		"Token": "aec-1",
		"Encoding": "G711",
		"Bitrate": 64,
		"SampleRate": 8,
		"Multicast": {
		"Address": {
			"Type": "IPv4",
			"IPv4Address": "224.1.1.1"
		},
		"Port": 5000,
		"TTL": 1,
		"AutoStart": false
		},
		"SessionTimeout": "PT0S"
	},
	"ForcePersistence": true
}
DELIMITER
)
json_test media/SetAudioEncoderConfiguration
