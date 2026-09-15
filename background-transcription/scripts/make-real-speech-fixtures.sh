#!/bin/sh
set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
fixture_directory="$script_directory/../fixtures"
source_url="https://upload.wikimedia.org/wikipedia/commons/f/f4/FDR%27s_Speech_to_the_Congress_regarding_the_naval_attack_on_Pearl_Harbor.ogg"
source_sha256="ae3cf3888dbebdb0318d6c3e91c7b4355e37912ac1c41ef48cf197dccc85f6ea"
temporary_directory=$(mktemp -d /tmp/ansight-fdr-fixtures.XXXXXX)
source_file="$temporary_directory/fdr-day-of-infamy.ogg"

cleanup() {
    rm -rf "$temporary_directory"
}
trap cleanup EXIT INT TERM

command -v curl >/dev/null
command -v ffmpeg >/dev/null

mkdir -p "$fixture_directory"
curl --location --fail --silent --show-error "$source_url" --output "$source_file"

actual_sha256=$(shasum -a 256 "$source_file" | awk '{print $1}')
if [ "$actual_sha256" != "$source_sha256" ]; then
    echo "Unexpected source SHA-256: $actual_sha256" >&2
    exit 1
fi

make_fixture() {
    output_name=$1
    start_seconds=$2
    spoken_seconds=$3
    padding_seconds=$4
    final_seconds=$5

    ffmpeg -hide_banner -loglevel error -y \
        -i "$source_file" \
        -af "atrim=start=$start_seconds:duration=$spoken_seconds,asetpts=PTS-STARTPTS,apad=pad_dur=$padding_seconds,atrim=duration=$final_seconds" \
        -ac 1 \
        -ar 16000 \
        -c:a pcm_s16le \
        -map_metadata -1 \
        "$fixture_directory/$output_name"
}

# Natural sentence boundaries are retained; short trailing silence makes the
# container durations exactly 20, 30, and 60 seconds.
make_fixture "fdr-day-of-infamy-20s.wav" 74.00 19.76 0.24 20
make_fixture "fdr-day-of-infamy-30s.wav" 141.76 29.00 1.00 30
make_fixture "fdr-day-of-infamy-60s.wav" 13.60 59.76 0.24 60

shasum -a 256 "$fixture_directory"/*.wav
