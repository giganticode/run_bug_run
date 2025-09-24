podman run -it --rm -v ./db:/home/rbr/rbr/db:rw -v ./data/preds:/home/rbr/rbr/data/preds:ro --userns=keep-id:uid=1001,gid=1001 --privileged $@ # --cap-add=CAP_SYS_ADMIN,CAP_SYS_NICE,CAP_SETFCAP,CAP_SETPCAP,CAP_SETGID,CAP_SETUID  --user 1001:1001 $@

