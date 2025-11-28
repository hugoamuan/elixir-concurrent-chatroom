# Each connected TCP client gets a proxy process.
# This module handles 
#   Reading user input (commands)
#   Validating and parsing commands
#   Communicate with Chat.Server to send/receive messages
#   Keep track of groups made by the specific user.

defmodule Chat.Proxy do
  use GenServer
  require Logger

  # == API ==
  def start(socket) do
    GenServer.start(__MODULE__, socket)
  end

  # == Callbacks ==

  @impl true
  def init(socket) do
    Logger.info("Client connected: #{inspect(socket)}")

    # Set socket to active mode (non-blocking async I/O)
    :inet.setopts(socket, active: true)

    # state holds socket, nickname and map of local gorup names to user lists
    {:ok, %{socket: socket, nickname: nil, groups: %{}}}
  end

  # == TCP == 
  # TCP socket incoming data handlers


  @impl true
  def handle_info({:tcp, socket, data}, %{socket: socket} = state) do
    trimmed = String.trim(data)
    new_state = handle_command(trimmed, state)
    {:noreply, new_state}
  end

  # when client closes connection
  @impl true
  def handle_info({:tcp_closed, socket}, %{socket: socket, nickname: nickname} = state) do
    Logger.info("Client disconnected #{inspect(socket)}")
    if nickname, do: :ets.delete(:nicknames, nickname)
    {:stop, :normal, state}
  end

  # network errors
  @impl true
  def handle_info({:tcp_error, socket, reason}, %{socket: socket} = state) do
    Logger.error("Socket error: #{inspect(reason)}")
    {:stop, reason, state}
  end

  # == Chat.Server messages ==
  @impl true
  def handle_info({:incoming_msg, from, text}, %{socket: socket} = state) do
    # [user_name] <text>
    :gen_tcp.send(socket, "[#{from}] #{text}\n")
    {:noreply, state}
  end

  # == Command Parser ==
  # Handle /commands

  # set nickname for the user (/nck <name>)
  defp handle_command("/nck " <> nickname, %{socket: socket} = state) do
    nickname = String.trim(nickname)

    case Chat.Server.nck(nickname, self()) do
      :ok ->
        :gen_tcp.send(socket, "Nickname set to #{nickname}\n")
        %{state | nickname: nickname}

      :taken ->
        :gen_tcp.send(socket, "Nickname already in use\n")
        state

      {:error, :too_long} ->
        :gen_tcp.send(socket, "Nickname too long (max 10 chars)\n")
        state
    end
  end

  # list all connected users
  defp handle_command("/lst" <> _rest, %{socket: socket} = state) do
    list = Chat.Server.lst()
    :gen_tcp.send(socket, Enum.join(list, ", ") <> "\n")
    state
  end

  # send a message to one or more users (/msg <recipients> <text>)
  defp handle_command("/msg " <> rest, %{socket: socket, nickname: from, groups: groups} = state) do
    if from == nil do
      :gen_tcp.send(socket, "You must set a nickname first (/nck <name>)\n")
      state
    else
      # split input for parsing
      case String.split(rest, " ", parts: 2) do
        [recipients_str, message] ->

          raw_recipients = String.split(recipients_str, ",", trim: true)

          # expand group names into lists of usernames
          expanded_recipients =
            Enum.flat_map(raw_recipients, fn name ->
              cond do
                String.starts_with?(name, "#") ->
                  Map.get(groups, name, [])

                true ->
                  [name]
              end
            end)

          # ask Chat.Server to deliver the message
          case Chat.Server.msg(from, expanded_recipients, message) do
            :ok ->
              :gen_tcp.send(socket, "Message sent\n")
              state

            {:error, :no_recipient} ->
              :gen_tcp.send(socket, "No valid recipients online\n")
              state
          end

        _ ->
        :gen_tcp.send(socket, "Usage: /msg <recipient(s)> <message>\n")
          state
      end
    end
  end

  # creates a group name for this proxy only
  defp handle_command("/grp " <> rest, %{socket: socket, groups: groups} = state) do
    case String.split(rest, " ", parts: 2) do
      [group_name, users_str] ->
        group_name = String.trim(group_name)
        users = String.split(users_str, ",", trim: true)

        # validate group name
        if String.starts_with?(group_name, "#") and String.length(group_name) <= 11 do
          new_groups = Map.put(groups, group_name, users)
          :gen_tcp.send(socket, "Group #{group_name} created.\n")
          %{state | groups: new_groups}
        else
          :gen_tcp.send(socket, "Invalid group name. Must start with # and be <= 11 chars.\n")
          state
        end

      _ ->
        :gen_tcp.send(socket, "Usage: /grp <#groupname> <user1,user2,...>\n")
        state
    end
  end

  # for commands to be case insensitive
  defp handle_command(command, state) when is_binary(command) do
    handle_command(String.downcase(command), state)
  end

  # ignore empty input
  defp handle_command("", state), do: state

  # undefined commands
  defp handle_command(unknown, %{socket: socket} = state) do
    :gen_tcp.send(socket, "Unknown command: #{unknown}\n")
    state
  end
end

