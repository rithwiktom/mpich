#!/bin/bash

export name=$1
export workspace=$2
export testfile=$3
export username=$4

set -ex

# Find the list of warnings
grep warning ${workspace}/m.txt | sort | uniq | grep -v hwloc > ${workspace}/warnings.${name}.txt

# Add the xml format to the test results
echo '<?xml version="1.0" encoding="UTF-8"?>' | cat - ${testfile} > ${testfile}.tmp
mv ${testfile}.tmp ${testfile}

# Strip the last line of the file (should be </testsuites>)
sed \$d ${testfile} > ${testfile}.tmp
mv ${testfile}.tmp ${testfile}

prev_file="/home/${username}/nightly-warnings/warnings.${name}.txt"
curr_file="${workspace}/warnings.${name}.txt"

# Add the warning output
echo '  <testsuite tests="1" name="Warnings">' >> ${testfile}
echo '    <testcase name="Warning Output">' >> ${testfile}
if [ `wc -l < ${curr_file}` -gt `wc -l < ${prev_file}` ]; then
    echo "===== WARNINGS WORSE THAN PREVIOUS NIGHTLY ====="
    echo '      <failure type="Too Many Warnings">' >> ${testfile}
    echo "        Nightly warnings: `wc -l < ${prev_file}`" >> ${testfile}
    echo "        New Job warnings: `wc -l < ${curr_file}`" >> ${testfile}
    echo "        First lines of the new warnings (see m.txt in Jenkins job output for details):" >> ${testfile}
    lines=$(comm -23 ${curr_file} ${prev_file})
    for line in "$lines"; do
       line=${line//\</&lt;}
       echo "${line//\>/&gt;}" >> ${testfile}
    done
    echo '      </failure>' >> ${testfile}
fi
echo '    </testcase>' >> ${testfile}
echo '  </testsuite>' >> ${testfile}
echo '</testsuites>' >> ${testfile}
