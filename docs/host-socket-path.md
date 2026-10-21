# Unexpected entries at the host socket path

The host listens on a Unix-domain socket. Before binding, it inspects the requested path with
`lstat`, which examines a symlink itself instead of following its target. An absent path is allowed;
an existing socket is removed and replaced. The resulting socket keeps owner-only mode `0600`.

A regular file, directory, symlink (including a dangling one), or any other non-socket entry causes
`UnixSocket.Failure.nonSocketPath`. The entry and any symlink target are left intact. Inspection
and socket-removal errors are reported with their system error, and an overlong socket path is
rejected before any filesystem mutation.

If startup reports this refusal:

1. Inspect the exact path named in the error, its entry type, and any symlink destination. Work out
   what owns it and whether the host was configured with the intended socket path.
2. If the path is correct, move the unexpected entry to a safe location after checking that doing
   so will not disrupt its owner. Preserve its contents; for a symlink, move the link itself.
3. Retry starting the host once the socket path is absent, or correct the configured path.

Do not delete an unexpected entry automatically. Replacing existing sockets retains the current
behavior; this check does not determine whether another listener owns a socket.
