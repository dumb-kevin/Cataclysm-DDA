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

# Retry [retry]-tagged tests that failed in the initial run.
# Reads retry_failed_*.txt files (one test name per line) produced by the
# test binary, re-runs each with a new RNG seed up to 2 more times.
# Writes retry_summary.txt for the comment formatter.
function retry_failed_tests
{
    local test_bin="$1"
    local pattern="$2"
    shift 2
    local extra_args=("$@")
    local max_retries=2

    local failed_tests
    failed_tests=$(cat $pattern 2>/dev/null | sort -u)
    rm -f $pattern
    if [ -z "$failed_tests" ]; then
        # No [retry] failures found. If we were called after a test failure,
        # it means non-[retry] tests failed.
        return 1
    fi

    echo "--- Retrying failed [retry]-tagged tests ---"

    local any_still_failing=false
    true > retry_summary.txt

    while IFS= read -r test_name; do
        [ -z "$test_name" ] && continue
        local passed=false
        local attempts=1

        for attempt in $(seq 2 $((max_retries + 1))); do
            attempts=$attempt
            echo "Retry attempt $attempt for: $test_name"
            if $WINE "$test_bin" ${cata_test_opts} "$test_name" \
                --user-dir=retry_user_dir/ \
                "${extra_args[@]}" 2>&1; then
                passed=true
                echo "  -> passed on attempt $attempt"
                break
            fi
        done

        if $passed; then
            printf 'passed\t%s\t%s\n' "$attempts" "$test_name" >> retry_summary.txt
        else
            printf 'failed\t%s\t%s\n' "$attempts" "$test_name" >> retry_summary.txt
            any_still_failing=true
        fi
    done <<< "$failed_tests"

    echo "--- Retry summary ---"
    cat retry_summary.txt

    if $any_still_failing; then
        echo "Some tests still failing after all retries"
        return 1
    fi
    return 0
}

if [ "$CMAKE" = "1" ]
then
    bin_path="./"
    if [ "$RELEASE" = "1" ]
    then
        build_type=MinSizeRel
        bin_path="build/tests/"
    else
        build_type=Debug
    fi

    # Run regular tests; capture exit code so retry_failed_tests can run under set -e
    test_result=0
    if [ -f "${bin_path}cata_test" ]; then
        parallel ${parallel_opts} "run_test $(printf %q "${bin_path}")'/cata_test' '('{}')=> ' --user-dir=test_user_dir_{#} --retry-failed=retry_failed_cmake_{#}.txt {}" ::: "[slow] ~starting_items" "~[slow] ~[.],starting_items" || test_result=$?
        if [ $test_result -ne 0 ]; then
            retry_failed_tests "${bin_path}cata_test" 'retry_failed_cmake_*.txt' || exit 1
        fi
    fi
    test_result=0
    if [ -f "${bin_path}cata_test-tiles" ]; then
        parallel ${parallel_opts} "run_test $(printf %q "${bin_path}")'/cata_test-tiles' '('{}')=> ' --user-dir=test_user_dir_{#} --retry-failed=retry_failed_cmake_tiles_{#}.txt {}" ::: "[slow] ~starting_items" "~[slow] ~[.],starting_items" || test_result=$?
        if [ $test_result -ne 0 ]; then
            retry_failed_tests "${bin_path}cata_test-tiles" 'retry_failed_cmake_tiles_*.txt' || exit 1
        fi
    fi
else
    export ASAN_OPTIONS=detect_odr_violation=1
    export UBSAN_OPTIONS=print_stacktrace=1
    test_result=0
    parallel -j "$num_test_jobs" ${parallel_opts} "run_test './tests/cata_test' '('{}')=> ' --user-dir=test_user_dir_{#} --retry-failed=retry_failed_{#}.txt {}" ::: "[slow] ~starting_items" "~[slow] ~[.],starting_items" || test_result=$?
    if [ $test_result -ne 0 ]; then
        retry_failed_tests './tests/cata_test' 'retry_failed_*.txt' || exit 1
    fi
    if [ -n "$MODS" ]
    then
        test_result=0
        parallel -j "$num_test_jobs" ${parallel_opts} "run_test './tests/cata_test' 'Mods-('{}')=> ' $(printf %q "${MODS}") --user-dir=modded_{#} --retry-failed=retry_failed_mods_{#}.txt {}" ::: "[slow] ~starting_items" "~[slow] ~[.],starting_items" || test_result=$?
        if [ $test_result -ne 0 ]; then
            retry_failed_tests './tests/cata_test' 'retry_failed_mods_*.txt' ${MODS} || exit 1
        fi
    fi

    if [ -n "$TEST_STAGE" ]
    then
        # Run the tests with all the mods, without actually running any tests,
        # just to verify that all the mod data can be successfully loaded.
        # Because some mods might be mutually incompatible we might need to run a few times.

        ./build-scripts/get_all_mods.py | \
            while read mods
            do
                run_test ./tests/cata_test '(all_mods)=> ' '[force_load_game]' --user-dir=all_modded --mods="${mods}"
            done
    fi
fi

# vim:tw=0
