```shellsession
$ go build -ldflags='-w -s' && ls -lh pqr
... 1.9M ... pqr

$ nim c -d:release --opt:size --passL:-s pqr.nim && ls -lh pqr
...
... 95K ... pqr
```
