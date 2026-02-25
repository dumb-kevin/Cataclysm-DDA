#!/bin/bash

# Script made specifically for running tests on GitHub Actions

echo "Using bash version $BASH_VERSION"
set -exo pipefail

num_jobs=3
parallel_opts="--verbose --linebuffer"
cata_test_opts="--min-duration 20 --use-colour yes --rng-seed time --order lex ${EXTRA_TEST_OPTS}"
[ -z $NUM_TEST_JOBS ] && num_test_jobs=3 || num_test_jobs=$NUM_TEST_JOBS

# We might need binaries installed via pip, so ensure that our personal bin dir is on the PATH
export PATH=$HOME/.local/bin:$PATH
# export so run_test can read it when executed by parallel
export cata_test_opts 

function run_test
{
    set -eo pipefail
    test_exit_code=0 sed_exit_code=0 exit_code=0
    test_bin=$1
    prefix=$2
    shift 2

    $WINE "$test_bin" ${cata_test_opts} "$@" 2>&1 | sed -E 's/^(::(warning|error|debug)[^:]*::)?/\1'"$prefix"'/' || test_exit_code="${PIPESTATUS[0]}" sed_exit_code="${PIPESTATUS[1]}"
    if [ "$test_exit_code" -ne "0" ]
    then
        echo "$3test exited with code $test_exit_code"
        exit_code=1
    fi
    if [ "$sed_exit_code" -ne "0" ]
    then
        echo "$3sed exited with code $sed_exit_code"
        exit_code=1
    fi
    return $exit_code
}
export -f run_test

# TEMP: run only the mayfail pipeline verification test
run_test './tests/cata_test' '=> ' --user-dir=test_user_dir_1 --mayfail-report=mayfail_1.json mayfail_pipeline_test

# vim:tw=0
