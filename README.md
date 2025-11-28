# Concurrent Chatroom 
- OTP application started from `Chat.Application` with a one-for-one supervisor that boots `Chat.Server` (registry/message router) and `Chat.ProxyServer` (TCP listener on port 6666).
- Each TCP client connection spawns a `Chat.Proxy` process that parses commands and talks to `Chat.Server`.
- State for connected users is stored in the ETS table `:nicknames`, shared across proxies via the globally registered `Chat.Server` GenServer.
- Java `ChatClient.java` demonstrates an external client connecting over TCP and issuing slash commands.

## Key Modules and Responsibilities
- `lib/chat/server.ex`
  - Maintains ETS table of `{nickname, pid}` pairs; enforces nickname uniqueness and length (<= 10 chars).
  - Handles `/nck` via `Chat.Server.nck/2`, `/lst` via `Chat.Server.lst/0`, and `/msg` via `Chat.Server.msg/3` to broadcast to individual users or expanded groups.
  - Replies with `:ok` when at least one recipient receives a message; otherwise returns `{:error, :no_recipient}`.
- `lib/chat/proxy_server.ex`
  - Listens on TCP (default 6666) with `:gen_tcp` options for binary, line-based, blocking reads; restarts accept loop on errors.
  - Spawns `Chat.Proxy` for every accepted socket and hands off ownership with `:gen_tcp.controlling_process/2`.
- `lib/chat/proxy.ex`
  - Parses commands from each client, keeps per-connection state (`socket`, `nickname`, and local `groups` map for aliases like `#friends`).
  - Implements commands:
    - `/nck <name>`: validates and sets nickname through `Chat.Server.nck/2`.
    - `/lst`: retrieves online users.
    - `/msg <recipients> <text>`: expands comma-separated recipients and `#group` aliases before calling `Chat.Server.msg/3`.
    - `/grp <#group> <user1,user2,...>`: stores local group aliases (must start with `#` and be <= 11 chars).
  - For incoming messages, sends `[from] <text>` lines back to the client socket.
- `ChatClient.java`
  - Simple Java console client showcasing how to connect, set nicknames, and exchange messages over TCP.

## Message Flow
1. Client sends a slash command to `Chat.Proxy` via TCP.
2. `Chat.Proxy` validates input; for `/msg`, it expands any group aliases and calls `Chat.Server.msg/3`.
3. `Chat.Server` looks up each recipient in the ETS table and uses `send/2` to deliver `{:incoming_msg, from, text}` to their proxy processes.
4. Recipient `Chat.Proxy` processes render the message back to the respective TCP sockets.

