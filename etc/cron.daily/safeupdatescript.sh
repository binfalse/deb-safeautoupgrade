#!/bin/bash
#
# Copyright 2016  Martin Scharm
#
# This file is part of bf-safeupgrade.
# <https://github.com/binfalse/deb-safeautoupgrade>
#
# bf-safeupgrade is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option) any
# later version.
#
# bf-safeupgrade is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

# You should have received a copy of the GNU General Public License along with
# bf-safeupgrade. If not, see <http://www.gnu.org/licenses/>.

MAILTO=root
FORCEUPDATE=false
HOST=$(hostname)

# read configuration from settings file
[ -e /etc/default/deb-safeupgrade ] && source /etc/default/deb-safeupgrade


# errors will be collected in here:
FAIL=

# no. of updateable packages
UPDATEABLE=0

# some temporary files
simtemp=$(mktemp)
conftemp=$(mktemp)



# update package lists
aptitude update > /dev/null

# simulate a safe upgrade
aptitude --simulate -y -v safe-upgrade | \grep '^Inst' > "$simtemp"

# for every upgradable packeg
while read -r package
do
    let "UPDATEABLE++"
    pkg=$(echo $package | awk '{print $2}')

    # what config files does it have?
    dpkg-query --showformat='${Conffiles}\n' --show $pkg 2>/dev/null | \grep -v "^$" > "$conftemp"

    while read -r conffile
    do
        file=$(echo $conffile | awk '{print $1}')
        exphash=$(echo $conffile | awk '{print $2}')
        seenhash=$(md5sum $file | awk '{print $1}')
        if [ "$exphash" != "$seenhash" ]
        then
            FAIL="$FAIL$pkg configuration has changed: $conffile vs $seenhash\n"
        fi
    done < "$conftemp"
done < "$simtemp"


# check if there are problems that should be fixed manually
if [ -n "$FAIL" ]
then
    if [ "$FORCEUPDATE" = "true" ]
    then
        FAIL="expect problems when updating automatically...\n$FAIL\nwill update nevertheless, as requested."
        echo -e "$FAIL" | mail -s "auto update on $HOST" $MAILTO
        echo "auto update continued even though there are updated configs"
    else
        FAIL="cannot update automatically...\n$FAIL\nplease review manually."
        echo -e "$FAIL" | mail -s "auto update failed on $HOST" $MAILTO
        echo "auto update aborted due to updated configs"
        rm "$conftemp" "$simtemp"
        exit 2
    fi
fi


# is there anything at all?
[ "$UPDATEABLE" -lt 1 ] && exit 0


# now the hot phase starts

# some output for the mail
RESULT="starting auto update:\n"$(cat "$simtemp")

# clean up
rm "$conftemp" "$simtemp"

RESULT="$RESULT\n\n"$(aptitude -y -v -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" safe-upgrade)

echo -e "$RESULT" | mail -s "auto updated system $HOST" $MAILTO


