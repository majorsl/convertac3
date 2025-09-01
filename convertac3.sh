#!/usr/bin/env bash
# Version 2.6.1 - Fix 2.0 downmix bug when there are multiple tracks.

FFMPEG="/usr/bin"
LOCKFILE="/tmp/eac3_convert.lock"
LANG_OVERRIDE="eng"
MAX_EAC3_BITRATE=960  # maximum allowed kbps for E-AC3

# Acquire lock
exec 200>"$LOCKFILE"
flock -w 600 200 || { echo "⏳ Timeout waiting for lock (10 minutes). Another instance may be stuck. Exiting."; exit 1; }

# Working directory
if [ -n "$1" ]; then
  WORKINGDIRECTORY="$1"
else
  echo "⚠️  Please call the script with a trailing directory part to process."
  exit 1
fi

if [ ! -d "$WORKINGDIRECTORY" ]; then
  echo "❌ $WORKINGDIRECTORY doesn't exist, aborting."
  exit 1
fi

# Counters
converted=0
skipped=0
failed=0
metadata_only=0

# Process MKVs using process substitution (avoids subshell)
while IFS= read -r -d '' file; do
  base_name="${file%.*}"
  echo "🎬 Processing \"$file\""

  # Probe audio streams
  streams_json=$("$FFMPEG/ffprobe" -v error -select_streams a \
                   -show_entries stream=index,codec_name,channels:stream_tags=language,bit_rate \
                   -of json "$file") || { echo "❌ ffprobe failed on \"$file\""; ((failed++)); continue; }

  # Parse via jq
  mapfile -t indexes   < <(echo "$streams_json" | jq -r '.streams[].index')
  mapfile -t codecs    < <(echo "$streams_json" | jq -r '.streams[].codec_name')
  mapfile -t channels  < <(echo "$streams_json" | jq -r '.streams[].channels // 2')
  mapfile -t languages < <(echo "$streams_json" | jq -r '.streams[].tags.language // "und"')
  mapfile -t bitrates  < <(echo "$streams_json" | jq -r '.streams[].bit_rate // 0')

  map_str=("-map" "0")
  codec_args=()
  encoded_any=0
  metadata_changed=0

  for ((track_num=0; track_num<${#indexes[@]}; track_num++)); do
    codec="${codecs[$track_num]}"
    ch="${channels[$track_num]}"
    lang="${languages[$track_num]}"
    src_bitrate="${bitrates[$track_num]}"

    # Determine target bitrate dynamically
    if [ "$src_bitrate" -gt 0 ]; then
        src_bitrate_k=$((src_bitrate / 1000))
    else
        src_bitrate_k=192  # default if not reported
    fi

    if [ "$ch" -eq 1 ]; then
        target_bitrate=$src_bitrate_k
    elif [ "$ch" -le 6 ]; then
        target_bitrate=$((src_bitrate_k * 3))  # 5.1
    elif [ "$ch" -eq 8 ]; then
        target_bitrate=$((src_bitrate_k * 4))  # 7.1
    else
        target_bitrate=$((src_bitrate_k * ch / 2))  # generic scaling
    fi

    [ "$target_bitrate" -gt "$MAX_EAC3_BITRATE" ] && target_bitrate=$MAX_EAC3_BITRATE
    target_bitrate="${target_bitrate}k"

    if [[ "$codec" == "eac3" ]]; then
        codec_args+=("-c:a:$track_num" "copy")
    else
        echo "🎧 Track $track_num has $ch channels — converting to E-AC3 at ${target_bitrate}."
        codec_args+=(
            "-c:a:$track_num" "eac3"
            "-b:a:$track_num" "$target_bitrate"
        )
        # Explicitly set layout for 5.1 or 7.1
        if [ "$ch" -eq 8 ]; then
            codec_args+=("-channel_layout:$track_num" "7.1")
        elif [ "$ch" -eq 6 ]; then
            codec_args+=("-channel_layout:$track_num" "5.1")
        fi
        encoded_any=1
    fi

    # Language fix
    if [[ "$lang" == "und" ]]; then
        echo "🌐 Track $track_num language is undefined — setting to $LANG_OVERRIDE."
        codec_args+=("-metadata:s:a:$track_num" "language=$LANG_OVERRIDE")
        metadata_changed=1
    fi
  done

  # Decide if we need to run ffmpeg
  if [ "$encoded_any" -eq 1 ] || [ "$metadata_changed" -eq 1 ]; then
    newfile="${base_name}-tmp.mkv"
    echo "🔄 Writing updated file..."
    "$FFMPEG/ffmpeg" -nostdin -i "$file" "${map_str[@]}" -c:v copy -c:s copy "${codec_args[@]}" "$newfile"

    if [ $? -eq 0 ]; then
      mv -f "$newfile" "$file"
      echo "✅ Updated \"$file\"."
      ((encoded_any)) && ((converted++))
      ((metadata_changed)) && ((metadata_only++))
    else
      echo "❌ Error: Processing \"$file\" failed. Keeping original."
      rm -f "$newfile"
      ((failed++))
    fi
  else
    echo "✅ Skipping \"$file\" — nothing to change."
    ((skipped++))
  fi
done < <(find "$WORKINGDIRECTORY" -type f -name "*.mkv" -print0)

# Print final summary
echo "📊 Summary: Converted=$converted  Metadata-only=$metadata_only  Skipped=$skipped  Failed=$failed"
