#!/bin/sh

if [ -n "$BASH_SOURCE" ]; then
    SELF="$BASH_SOURCE"
elif [ -n "$ZSH_VERSION" ]; then
    setopt function_argzero
    SELF="$0"
    SELF="${(%):-%x}"
elif [ -n "$KSH_VERSION" ]; then
    SELF=${.sh.file}
fi

eval `"$(dirname "$SELF")"/wf-config env generate "$@"`
