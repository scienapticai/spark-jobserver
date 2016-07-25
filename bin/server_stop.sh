#!/bin/bash
# Script to stop the job server

get_abs_script_path() {
  pushd . >/dev/null
  cd "$(dirname "$0")"
  appdir=$(pwd)
  popd  >/dev/null
}

get_abs_script_path

if [ -f "$appdir/settings.sh" ]; then
  . "$appdir/settings.sh"
else
  echo "Missing $appdir/settings.sh, exiting"
  exit 1
fi

pidFilePath=$appdir/$PIDFILE

if [ ! -f "$pidFilePath" ] || ! kill -0 "$(cat "$pidFilePath")" >/dev/null 2>&1 ; then
   echo 'Job server not running'
else
  PID="$(cat "$pidFilePath")"
  PGID="$(ps -o pgid= -p $PID | grep -o '[0-9]*' )"

  if [ -n "$PGID" ] ; then
    echo "Stopping Spark job server via SIGTERM to process group $PGID"
    kill -s TERM -- -$PGID && rm "$pidFilePath"
  else
    echo "Could not determine process group of Spark jobserver process $PID. Is it still running."
  fi
fi



