D=/var/tmp/tp-pgdata
if ! psql -h /var/tmp -p 55432 -U postgres -Atc "select 1" >/dev/null 2>&1; then
  [ -d $D ] || { mkdir -p $D; chown postgres $D; su postgres -s /bin/bash -c "/usr/lib/postgresql/16/bin/initdb -D $D -E UTF8 --locale=C.UTF-8 -A trust >/dev/null"; }
  su postgres -s /bin/bash -c "rm -f $D/postmaster.pid; /usr/lib/postgresql/16/bin/pg_ctl -D $D -o '-p 55432 -k /var/tmp' -l $D/log start -w" >/dev/null
fi
