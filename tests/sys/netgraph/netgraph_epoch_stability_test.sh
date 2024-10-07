#!/bin/sh
#
# SPDX-License-Identifier: BSD-3-Clause
#
# Copyright 2024 I-Hsuan Huang
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above
#    copyright notice, this list of conditions and the following disclaimer
#    in the documentation and/or other materials provided with the distribution.
# 3. Neither the name of the copyright holder nor the names of its
#    contributors may be used to endorse or promote products derived
#    from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.
#

set -e

################################################################################
# Script Parameters (Can be overridden by environment variables)
NUM_PEERS=${NUM_PEERS:-50}         # Number of peer nodes to create
HOOKSADD=${HOOKSADD:-42}           # Number of additional hooks to add/remove
ITERATIONS=${ITERATIONS:-7}         # Number of iterations for MAC operations
SUBITERATIONS=${SUBITERATIONS:-71} # Number of sub-iterations per iteration
MESSAGE_SIZE=${MESSAGE_SIZE:-256}   # Size of each message in bytes
MAX_QUEUE=${MAX_QUEUE:-1000}       # Maximum number of queued items allowed
EPOCH_TEST_ITERATIONS=${EPOCH_TEST_ITERATIONS:-10} # Number of epoch stability test iterations

# Temporary Files
progname="$(basename "$0" .sh)"
entries_lst="/tmp/${progname}.entries.lst"
entries2_lst="/tmp/${progname}.entries2.lst"

# Global Variables
eth=""
loaded_modules=""
created_hooks=""
rc=0

# Initialize Test Counters
TSTNR=0
TSTFAILS=0
TSTSUCCS=0

# Initialize Random Number Generator
srand() {
    RANDOM_SEED=$(date +%s)
    export RANDOM_SEED
}

# Verbose Logging
VERBOSE=${VERBOSE:-0}

log() {
    if [ "$VERBOSE" -eq 1 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
    fi
}

# Load Kernel Modules
load_modules () {
    for kmod in "$@"; do
        if ! kldstat -q -m "$kmod"; then
            log "Loading module: $kmod..."
            kldload "$kmod" || { echo "Failed to load module: $kmod"; exit 1; }
            loaded_modules="$loaded_modules $kmod"
        else
            log "Module already loaded: $kmod"
        fi
    done
}

# Unload Kernel Modules
unload_modules () {
    for kmod in $loaded_modules; do
        # These modules cannot be unloaded
        case "$kmod" in
            ng_ether|ng_socket)
                continue
                ;;
        esac
        log "Unloading module: $kmod..."
        kldunload "$kmod" || { echo "Failed to unload module: $kmod"; }
    done
    loaded_modules=''
}

# Find the First Active Ethernet Interface
find_iface () {
    # Figure out the first active Ethernet interface
    iface=$(ifconfig -u -l ether | awk '{print $1}' | head -1)
    if [ -z "$iface" ]; then
        echo "Error: No active Ethernet interface found."
        exit 1
    fi
    echo "$iface"
}

# Configure Netgraph Nodes
configure_nodes () {
    log "Configuring Netgraph nodes..."

    # Create and name macfilter (MF) node
    ngctl mkpeer "$eth": macfilter lower ether
    ngctl name "$eth":lower MF
    test_ok "Created and named macfilter node (MF)"

    # Create and name one2many (O2M) node
    ngctl mkpeer "$eth": one2many upper one
    ngctl name "$eth":upper O2M
    test_ok "Created and named one2many node (O2M)"

    # Configure O2M node
    ngctl msg O2M: setconfig "{ xmitAlg=3 failAlg=1 enabledLinks=[ 1 1 ] }"
    test_ok "Configured O2M node"

    # Connect macfilter to one2many
    ngctl connect MF: O2M: default many0
    test_ok "Connected MF:default to O2M:many0"

    # Connect additional hooks
    for i in $(seq 1 "$NUM_PEERS"); do
        ngctl connect MF: O2M: "out$i" "many$i" &
    done
    wait
    log "Connected $NUM_PEERS additional hooks"
    created_hooks=$(gethooks)
    test_ok "Added $NUM_PEERS hooks"
}

# Deconfigure Netgraph Nodes
deconfigure_nodes () {
    log "Deconfiguring Netgraph nodes..."
    ngctl shutdown MF: || log "Failed to shutdown MF:"
    ngctl shutdown O2M: || log "Failed to shutdown O2M:"
    test_ok "Deconfigured Netgraph nodes"
}

# Cleanup Function
cleanup () {
    log "Starting cleanup..."
    deconfigure_nodes
    unload_modules
    rm -f "$entries_lst" "$entries2_lst"
    log "Cleanup completed."
}

# Test Assertion Helpers
_test_next () { TSTNR=$((TSTNR + 1)); }
_test_succ () { TSTSUCCS=$((TSTSUCCS + 1)); }
_test_fail () { TSTFAILS=$((TSTFAILS + 1)); }

test_cnt () { echo "1..${1:-$TSTNR}"; }

test_title () {
    local msg="$1"
    printf '### %s ' "$msg"
    printf '#%.0s' $(seq $((80 - ${#msg} - 5)))
    printf "\n"
}

test_comment () { echo "# $1"; }

test_bailout () { echo "Bail out!${1:+ # $1}"; exit 1; }

test_bail_on_fail () { [ "$TSTFAILS" -eq 0 ] || test_bailout "Tests failed"; }

test_ok () {
    local msg="$1"
    _test_next
    _test_succ
    echo "ok $TSTNR - $msg"
}

test_not_ok () {
    local msg="$1"
    _test_next
    _test_fail
    echo "not ok $TSTNR - $msg"
}

test_eq () {
    local v1="$1" v2="$2" msg="$3"
    if [ "$v1" = "$v2" ]; then
        test_ok "$v1 $msg"
    else
        test_not_ok "$v1 vs $v2 $msg"
    fi
}

test_ne () {
    local v1="$1" v2="$2" msg="$3"
    if [ "$v1" != "$v2" ]; then
        test_ok "$v1 $msg"
    else
        test_not_ok "$v1 vs $v2 $msg"
    fi
}

test_failure () {
    local msg="$1"
    shift
    if ! "$@"; then
        test_ok "$msg - \"$@\" failed as expected"
    else
        test_not_ok "$msg - expected \"$@\" to fail but succeeded"
    fi
}

test_success () {
    local msg="$1"
    shift
    if ! "$@"; then
        test_not_ok "$msg - \"$@\" failed unexpectedly"
    else
        test_ok "$msg - \"$@\" succeeded"
    fi
}

# Function to Get Current Hooks
gethooks () {
    ngctl msg MF: 'gethooks' \
        | perl -ne 'while (/hookname="([^"]+)"/g) { push @h, $1 } END { print join(":", sort @h), "\n" }'
}

# Function to Count MACs in a Specific Hook
countmacs () {
    local hookname=${1:-'[^"]*'}

    ngctl msg MF: 'gethooks' \
        | perl -ne 'while (/hookname="'$hookname'" hookid=\d+ maccnt=(\d+)/g) { $c += $1 } END { print "$c\n" }'
}

# Function to Generate Unique MAC Addresses
genmac () {
    echo "00:00:00:00:$(printf "%02x" "$1"):$(printf "%02x" "$2")"
}

# Function to Select a Random Hook
randomedge () {
    local edge="out$(seq 0 "$NUM_PEERS" | sort -R | head -1)"
    [ "$edge" = "out0" ] && echo "default" || echo "$edge"
}

# Trap Signals for Cleanup
trap 'cleanup' EXIT
trap 'exit 99' 1 2 3 13 14 15

################################################################################
### Test Framework Functions ####################################################
################################################################################

# Function to Retrieve Epoch of a Node
get_node_epoch() {
    local node="$1"
    local epoch
    epoch=$(ngctl info "${node}:" | awk '/Epoch:/ {print $2}')
    log "Retrieved epoch for $node: $epoch"
    echo "$epoch"
}

# Test Epoch Stability - No Change Scenario
test_epoch_stability_no_change() {
    local node="$1"
    local initial_epoch final_epoch

    initial_epoch=$(get_node_epoch "$node")
    if [ -z "$initial_epoch" ]; then
        test_not_ok "Failed to retrieve initial epoch for $node"
        return
    fi
    test_comment "Initial epoch for $node: $initial_epoch"

    # Perform no-operation or benign operations
    for i in $(seq 1 10); do
        ngctl cmd "$node:" "stat" >/dev/null 2>&1
    done

    final_epoch=$(get_node_epoch "$node")
    if [ -z "$final_epoch" ]; then
        test_not_ok "Failed to retrieve final epoch for $node"
        return
    fi
    test_comment "Final epoch for $node: $final_epoch"

    if [ "$initial_epoch" -eq "$final_epoch" ]; then
        test_ok "Epoch stability for $node after no-op operations"
    else
        test_not_ok "Epoch changed for $node after no-op operations (Initial: $initial_epoch, Final: $final_epoch)"
    fi
}

# Test Epoch Stability - Change Scenario
test_epoch_stability_change() {
    local node="$1"
    local initial_epoch final_epoch

    initial_epoch=$(get_node_epoch "$node")
    if [ -z "$initial_epoch" ]; then
        test_not_ok "Failed to retrieve initial epoch for $node"
        return
    fi
    test_comment "Initial epoch for $node: $initial_epoch"

    # Perform operations that change configuration
    for i in $(seq 1 5); do
        local hook_name="test_change_$i"
        ngctl connect MF: O2M: "$hook_name" "many$((NUM_PEERS + i))" >/dev/null 2>&1
        ngctl rmhook MF: "$hook_name" >/dev/null 2>&1
    done

    final_epoch=$(get_node_epoch "$node")
    if [ -z "$final_epoch" ]; then
        test_not_ok "Failed to retrieve final epoch for $node"
        return
    fi
    test_comment "Final epoch for $node: $final_epoch"

    if [ "$initial_epoch" -lt "$final_epoch" ]; then
        test_ok "Epoch incremented for $node after configuration changes (Initial: $initial_epoch, Final: $final_epoch)"
    else
        test_not_ok "Epoch did not increment for $node after configuration changes (Initial: $initial_epoch, Final: $final_epoch)"
    fi
}

# Function to Run Epoch Stability Tests Multiple Times
run_epoch_stability_tests() {
    local iterations="$1"
    local node="$2"

    for i in $(seq 1 "$iterations"); do
        log "Epoch Stability Test Iteration $i for $node - No Change Scenario"
        test_epoch_stability_no_change "$node"

        log "Epoch Stability Test Iteration $i for $node - Change Scenario"
        test_epoch_stability_change "$node"
    done
}

################################################################################
### Start ######################################################################
################################################################################

log "Setting up system..."
load_modules netgraph ng_socket ng_ether ng_macfilter ng_one2many
eth=$(find_iface)
test_comment "Using Ethernet interface: $eth"

test_title "Configuring Netgraph nodes..."
configure_nodes

# Update this number when adding new tests
# Each test_ok and test_not_ok counts as one test
# Existing tests count towards the total
# Adding epoch stability tests: 2 tests per iteration per node
# Total epoch tests: EPOCH_TEST_ITERATIONS * 2 * 2 (nodes: MF and O2M)
EPOCH_TEST_TOTAL=$(( EPOCH_TEST_ITERATIONS * 2 * 2 ))
# Calculate total tests: existing 46 + EPOCH_TEST_TOTAL
TOTAL_TESTS=$((46 + EPOCH_TEST_TOTAL))
test_cnt "$TOTAL_TESTS"

################################################################################
### Tests ######################################################################
################################################################################

################################################################################
test_title "Test: Duplicate default hook"
test_failure "Duplicate connect of default hook" ngctl connect MF: O2M: default many99

################################################################################
test_title "Test: Add and remove hooks"
# Add hooks xxx1, xxx2, xxx3
for i in 1 2 3; do
    ngctl connect MF: O2M: "xxx$i" "many$((NUM_PEERS + i))" &
done
wait
hooks=$(gethooks)
test_eq "$created_hooks:xxx1:xxx2:xxx3" "$hooks" "Hooks after adding xxx1-3"

# Remove hooks xxx1, xxx2, xxx3
for i in 1 2 3; do
    ngctl rmhook MF: "xxx$i" &
done
wait
hooks=$(gethooks)
test_eq "$created_hooks" "$hooks" "Hooks after removing xxx1-3"

test_bail_on_fail

################################################################################
test_title "Test: Add many hooks"
added_hooks=""
for i in $(seq 10 1 "$HOOKSADD"); do
    added_hooks="$added_hooks:xxx$i"
    ngctl connect MF: O2M: "xxx$i" "many$((NUM_PEERS + i))" &
done
wait
hooks=$(gethooks)
test_eq "$created_hooks$added_hooks" "$hooks" "Hooks after adding many hooks"

# Remove all added hooks
for h in $(echo "$added_hooks" | tr ':' '\n'); do
    ngctl rmhook MF: "$h" &
done
wait
hooks=$(gethooks)
test_eq "$created_hooks" "$hooks" "Hooks after removing many hooks"

test_bail_on_fail

################################################################################
test_title "Test: Adding many MACs..."
# Add many MACs to out1 and out2
for i in $(seq 1 "$ITERATIONS"); do
    for j in $(seq 0 1 "$SUBITERATIONS"); do
        # Alternate between out1 and out2
        if [ $((i % 2)) -eq 0 ]; then
            edge="out2"
        else
            edge="out1"
        fi
        ether=$(genmac "$j" "$i")
        ngctl msg MF: 'direct' "{ hookname=\"$edge\" ether=\"$ether\" }" &
    done
done
wait

# Verify MAC counts
n=$(countmacs "out1")
n2=$(( (ITERATIONS / 2 ) * (SUBITERATIONS + 1) ))
test_eq "$n" "$n2" "MACs in table for out1"

n=$(countmacs "out2")
n2=$(( ((ITERATIONS + 1) / 2 ) * (SUBITERATIONS + 1) ))
test_eq "$n" "$n2" "MACs in table for out2"

n=$(countmacs "out3")
n2=0
test_eq "$n" "$n2" "MACs in table for out3"

test_bail_on_fail

################################################################################
test_title "Test: Changing hooks for MACs..."
# Move MACs from out1/out2 to out3
for i in $(seq 1 "$ITERATIONS"); do
    ether=$(genmac "$i" 0)
    ngctl msg MF: 'direct' "{ hookname=\"out3\" ether=\"$ether\" }" &
done
wait

# Verify MAC counts after reassignment
n=$(countmacs "out1")
n2=$(( (ITERATIONS / 2 ) * SUBITERATIONS ))  # One less per iteration
test_eq "$n" "$n2" "MACs in table for out1 after reassignment"

n=$(countmacs "out2")
n2=$(( ((ITERATIONS + 1) / 2 ) * SUBITERATIONS ))  # One less per iteration
test_eq "$n" "$n2" "MACs in table for out2 after reassignment"

n=$(countmacs "out3")
n2=$ITERATIONS
test_eq "$n" "$n2" "MACs in table for out3 after reassignment"

test_bail_on_fail

################################################################################
test_title "Test: Removing all MACs one by one..."
# Remove all MACs by assigning them to default hook
for i in $(seq 1 "$ITERATIONS"); do
    for j in $(seq 0 1 "$SUBITERATIONS"); do
        ether=$(genmac "$j" "$i")
        ngctl msg MF: 'direct' "{ hookname=\"default\" ether=\"$ether\" }" &
    done
done
wait

# Verify that all MACs are removed
n=$(countmacs "default")
test_eq "$n" 0 "MACs in table after removing all MACs"

test_bail_on_fail

################################################################################
test_title "Test: Randomly adding MACs on random hooks..."
rm -f "$entries_lst"
for i in $(seq 1 "$ITERATIONS"); do
    for j in $(seq 0 1 "$SUBITERATIONS"); do
        edge=$(randomedge)
        ether=$(genmac "$j" "$i")
        ngctl msg MF: 'direct' "{ hookname=\"$edge\" ether=\"$ether\" }" &
        echo "$ether $edge" >> "$entries_lst"
    done
done
wait

# Verify MAC counts per hook
n=$(countmacs "out1")
n2=$(grep -c ' out1$' "$entries_lst")
test_eq "$n" "$n2" "MACs in table for out1 after random additions"

n=$(countmacs "out2")
n2=$(grep -c ' out2$' "$entries_lst")
test_eq "$n" "$n2" "MACs in table for out2 after random additions"

n=$(countmacs "out3")
n2=$(grep -c ' out3$' "$entries_lst")
test_eq "$n" "$n2" "MACs in table for out3 after random additions"

test_bail_on_fail

################################################################################
test_title "Test: Randomly changing MAC assignments..."
rm -f "$entries2_lst"
for i in $(seq 1 "$ITERATIONS"); do
    while read -r ether edge; do
        edge2=$(randomedge)
        ngctl msg MF: 'direct' "{ hookname=\"$edge2\" ether=\"$ether\" }" &
        echo "$ether $edge2" >> "$entries2_lst"
    done < "$entries_lst"
done
wait

# Verify MAC counts after random assignments
n=$(countmacs "out1")
n2=$(grep -c ' out1$' "$entries2_lst")
test_eq "$n" "$n2" "MACs in table for out1 after random assignments"

n=$(countmacs "out2")
n2=$(grep -c ' out2$' "$entries2_lst")
test_eq "$n" "$n2" "MACs in table for out2 after random assignments"

n=$(countmacs "out3")
n2=$(grep -c ' out3$' "$entries2_lst")
test_eq "$n" "$n2" "MACs in table for out3 after random assignments"

test_bail_on_fail

################################################################################
test_title "Test: Resetting macfilter..."
# Reset macfilter
ngctl msg MF: reset
test_ok "Reset macfilter"

# Verify that all MACs are removed
n=$(countmacs "out1")
n2=0
test_eq "$n" "$n2" "MACs in table after resetting macfilter for out1"

n=$(countmacs "out2")
n2=0
test_eq "$n" "$n2" "MACs in table after resetting macfilter for out2"

n=$(countmacs "out3")
n2=0
test_eq "$n" "$n2" "MACs in table after resetting macfilter for out3"

test_bail_on_fail

################################################################################
### Epoch Stability Tests ######################################################
################################################################################

test_title "Test: Epoch Stability - No Change Scenario for MF"
run_epoch_stability_tests "$EPOCH_TEST_ITERATIONS" "MF"

test_title "Test: Epoch Stability - No Change Scenario for O2M"
run_epoch_stability_tests "$EPOCH_TEST_ITERATIONS" "O2M"

################################################################################

exit 0

################################################################################
### Register Test Cases #########################################################
################################################################################

# Since this is a standalone shell script, registration is handled via TAP outputs.
# The 'test_cnt' at the beginning sets the total number of expected tests.
# Each 'test_ok' or 'test_not_ok' corresponds to a TAP test result.

################################################################################
