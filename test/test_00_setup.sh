#! /bin/bash

echo "`basename $0 .sh` - Verifying test infrastructure -"

# Check that expect_n works as it should
echo "...checking test.expect_n()..."

# This should fail as 0 is not equal to 1
result=`psql -d vpd 2>&1 <<EOF
\set ON_ERROR_STOP
select test.expect_n('select 0', 1, 'THIS IS CORRECT');
EOF`
status=$?
if [ ${status} = 0 ]; then
    echo "ERROR: expect_n did not cause script to fail" 1>&2
    exit 1
fi

echo "${result}" | grep "ERROR.*THIS IS CORRECT" >/dev/null || (
    echo "ERROR: expect_n did not raise correct message:" 1>&2
    echo "${result}" 1>&2
    exit 1
)

# This should fail as no rows will be returned from query
result=`psql -d vpd 2>&1 <<EOF
\set ON_ERROR_STOP
select test.expect_n('select 1 where false', 1, 'NO ROWS');
EOF`
status=$?
if [ ${status} = 0 ]; then
    echo "ERROR: expect_n should have failed for no rows" 1>&2
    exit ${status}
fi

echo "${result}" | grep "ERROR.*NO ROWS" >/dev/null || (
    echo "ERROR: expect_n raised unexpected message:" 1>&2
    echo "${result}" 1>&2
    exit 1
)

# This should not fail as 1 = 1
result=`psql -d vpd 2>&1 <<EOF
\set ON_ERROR_STOP
select test.expect_n('select 1', 1, 'THIS SHOULD BE QUIET');
EOF`
status=$?
if [ ${status} != 0 ]; then
    echo "ERROR: expect_n should have been successful" 1>&2
    exit ${status}
fi

echo "${result}" | grep "ERROR.*SHOULD" >/dev/null && (
    echo "ERROR: expect_n raised unexpected message:" 1>&2
    echo "${result}" 1>&2
    exit 1
)

exit 0
