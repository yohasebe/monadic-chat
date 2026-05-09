#!/bin/bash

# Navigate to the ruby directory
cd ./docker/services/ruby

# parse command line argument "start", "debug", "stop", or "restart";

if [ "$1" == "start" ]; then
  ./bin/monadic_dev start --daemonize
  echo "Monadic script executed with 'start' argument 🚀"
  echo "Run 'monadic_server.sh stop' to stop the server"
elif [ "$1" == "debug" ]; then
  echo "Starting Monadic server in debug mode 🛑"
  # Export MONADIC_DEV so the docker compose overlay (compose.dev.yml)
  # publishes Qdrant + embeddings host ports. Host-side scripts and
  # specs need them to talk to those containers directly; without this
  # the dev mode pipeline silently keeps containers without published
  # ports and host connections fail.
  export MONADIC_DEV=true
  ./bin/monadic_dev start
elif [ "$1" == "stop" ]; then
  ./bin/monadic_dev stop
  echo "Monadic script executed with 'stop' argument 🛑"
elif [ "$1" == "restart" ]; then
  ./bin/monadic_dev restart --daemonize
  echo "Monadic script executed with 'restart' argument 🔄"
elif [ "$1" == "export" ]; then
  ./bin/monadic_dev export
elif [ "$1" == "import" ]; then
  ./bin/monadic_dev import
elif [ "$1" == "status" ]; then
  ./bin/monadic_dev status
else
  echo "Usage: monadic_server.sh [start|stop|restart|debug|status|export|import]"
  ./bin/monadic_dev status
fi
