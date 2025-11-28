# Chat.Server is the registry and message manager that handles:
#  - keeps track of all connected nicknames and their pids (ets)
#  - sending messages between users

defmodule Chat.Server do

  @name {:global, __MODULE__}
  use GenServer

  # == API Functions ==

  # 1 globally registered  
  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: @name)
  end

  # /NCK command sets the nickname for the user
  def nck(nickname, pid) do
    GenServer.call(@name, {:nck, nickname, pid})
  end

  # /LST command is used to get the list of nicknames in use
  def lst() do
    GenServer.call(@name, :lst)
  end

  # /MSG command is used to send a msg to recipient(s)
  def msg(from, recipients, text) do
    GenServer.call(@name, {:msg, from, recipients, text})
  end

  # == Callbacks ==

  @impl true
  def init(_args) do
    # create public ets table to store {nickname, pid} pairs
    # opts 1 - global name 2 - no dupes 3 - access for proxy
    :ets.new(:nicknames, [:named_table, :set, :public])
    {:ok, %{}}
  end

  # == Handle Calls ==

  @impl true
  def handle_call({:nck, nickname, pid}, _from, state) do

    if String.length(nickname) > 10 do
      {:reply, {:error, :too_long}, state}

    else
      # check if nickname already taken by someone else
      case :ets.lookup(:nicknames, nickname) do
        [{^nickname, existing_pid}] when existing_pid != pid ->
          {:reply, :taken, state}

        _ ->
          # rmove any old nickname owned by this PID
          existing_entries = :ets.tab2list(:nicknames)

          Enum.each(existing_entries, fn {name, existing_pid} ->
            if existing_pid == pid do
              :ets.delete(:nicknames, name)
            end
          end)

          # insert new nickname
          :ets.insert(:nicknames, {nickname, pid})
          {:reply, :ok, state}
      end
    end
  end

  
  @impl true
  def handle_call(:lst, _from, state) do
    entries = :ets.tab2list(:nicknames)
    nicknames = for {nickname, _pid} <- entries, do: nickname
    {:reply, nicknames, state}
  end

  @impl true
  def handle_call({:msg, from, recipients, text}, _from, state) do
    # track how many recipients received the message
    delivered =
      Enum.reduce(recipients, 0, fn recipient, count ->
        case :ets.lookup(:nicknames, recipient) do
          [{^recipient, pid}] ->
            send(pid, {:incoming_msg, from, text})
            count + 1

          # if user not found, skip
          [] ->
            count
        end
      end)

    # success if sent to at least 1 other user
    reply =
      if delivered > 0 do
        :ok
      else
        {:error, :no_recipient}
      end

    {:reply, reply, state}
  end
end

