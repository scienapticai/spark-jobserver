#!/bin/bash
# This script is designed to run in the background and acquire
# as well as periodically renew a Kerberos TGT for the user it is run with.
# It is parameterized via environment variables:
# - JOBSERVER_KEYTAB must be set and point to a keytab file
# - JOBSERVER_PRINCIPAL is optional and, if set, must be a valid principal for 
#   the keytab file. If not set, a default value will be guessed.


# first determine the principal
if [ -z "$JOBSERVER_PRINCIPAL" ] ; then  
  DFLT_REALM=$( grep "default_realm" /etc/krb5.conf | sed 's/[[:space:]]//g' | sed 's/default_realm=//' )
  [ -n "$DFLT_REALM" ] || { echo "Could not determine default realm from /etc/krb5.conf. Exiting." ; exit 1 ; }
fi

# then determine that we have a keytab file
[ -n "$JOBSERVER_KEYTAB" ] || { echo "No keytab provided (need to set JOBSERVER_KEYTAB environment variable. Exiting." ; exit 1; } 
[ -r "$JOBSERVER_KEYTAB" ] || { echo "Keytab file $JOBSERVER_KEYTAB does not exist or is not readable. Exiting." ; exit 1; } 

# If LOCKFILE already exists then another kerbereos ticket renewer process must be running
# If not, echo this process's id to LOCKFILE and ensure it is deleted when process exits
LOCKFILE="/tmp/kerberos_ticket_renewer_$UID"
if ( set -o noclobber ; echo $$ > "$LOCKFILE") 2> /dev/null; then
  trap 'rm -f $LOCKFILE' EXIT
else
  echo "Kerberos ticket renewer already running with pid" """$(cat $LOCKFILE)"""
  exit 1
fi

# KOUT is a file that holds temporary data (klist output)
KOUT="$(mktemp)"
[ $? = 0 ] || { echo "Failed to create a temp file. Exiting." ; exit $? ; }
# Make sure we remove LOCKFILE and KOUT when the process exits (replaces previous trap)
trap '{ rm -f $LOCKFILE $KOUT ; echo "$(date) -- Kerberos ticket renewer stopped" ; exit 255 ; }' EXIT

echo "$(date) -- Kerberos ticket renewer started"

# Renew ticket every 60s
while true ; do
  # determine default principal here (important that this is inside the loop due to boot time race conditions
  # with FQDN).
  DFLT_PRINCIPAL="$(whoami)/$(hostname -f)@$DFLT_REALM"
  
  # first grab the current klist output for easier analysis
  klist &>$KOUT

  if [ $? = 0 ] ; then
    # we have a ticket in the cache
    PRINC="$(grep '^Default principal: ' <$KOUT | awk '{print $3}')"
    EXPIRE_TIME=$( date -d "$( grep 'krbtgt/' <$KOUT | awk '{print $3, $4}' )" +%s )
    
    if [ \( $( date +%s ) -ge $EXPIRE_TIME \) -o \( "$PRINC" != "${JOBSERVER_PRINCIPAL:-$DFLT_PRINCIPAL}" \) ] ; then
      # we do have a ticket, but it is expired or the principal does not match (-> destroy and reinit)
      echo "$(date) -- Destroying existing ticket"
      kdestroy &> /dev/null
      echo "$(date) -- Getting ticket with keytab $JOBSERVER_KEYTAB for principal ${JOBSERVER_PRINCIPAL:-$DFLT_PRINCIPAL}"
      kinit -k -t "$JOBSERVER_KEYTAB" "${JOBSERVER_PRINCIPAL:-$DFLT_PRINCIPAL}" || echo "$(date) -- Failed to get ticket."
    elif [ $( expr $EXPIRE_TIME - $( date +%s ) ) -le 300 ] ; then
      # we do have a ticket, and it expires soon (-> renew)
      echo "$(date) -- Ticket has expired. Renewing."
      kinit -R || echo "$(date) -- Failed to renew ticket."
    fi
  else
    echo "$(date) -- Getting ticket with keytab $JOBSERVER_KEYTAB for principal ${JOBSERVER_PRINCIPAL:-$DFLT_PRINCIPAL}"
    kinit -k -t "$JOBSERVER_KEYTAB" "${JOBSERVER_PRINCIPAL:-$DFLT_PRINCIPAL}" || echo "$(date) -- Failed to get ticket."
  fi
  
  sleep 60
done
