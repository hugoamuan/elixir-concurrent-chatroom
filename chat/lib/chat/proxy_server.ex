# Chat.ProxyServer handles the networking
# - listening for client connections
# = spawn Chat.Proxy process for each connection
# - handle networking through loops


defmodule Chat.ProxyServer do
  use GenServer
  require Logger

  # == API Functions ==

  def start_link(port \\ 6666) do
    GenServer.start(__MODULE__, port)
  end

  # == API Callbacks ==

  @impl true
  def init(port) do
    # Options below
    # 1. receives data as binaries (instead of lists)
    # 2. receives data line by line
    # 3. blocks on recv/2 until data is available
    # 4. allows us to reuse the address if the listener crashes
    opts = [:binary, packet: :line, active: false, reuseaddr: true]

    # Open a listening socket
    case :gen_tcp.listen(port, opts) do
      {:ok, listen_socket} ->
        Logger.info("Proxy server listening on port #{port}")

        # begin first accept
        send(self(), :accept)

        # store socket and port in server state
        {:ok, %{socket: listen_socket, port: port}}

      {:error, reason} ->
        Logger.error("Failed to open port #{port}: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  # == Connection Loop ==
  # runs every time we accept a new client
  @impl true
  def handle_info(:accept, %{socket: listen_socket} = state) do

    case :gen_tcp.accept(listen_socket) do

      {:ok, socket} ->
        # spawn proxy
        {:ok, pid} = Chat.Proxy.start(socket)
        :ok = :gen_tcp.controlling_process(socket, pid)

        # continue accepting connections
        send(self(), :accept)
        {:noreply, state}

      {:error, :closed} ->
        Logger.error("Listening socket closed ... Chat.ProxyServer shutting down")
        {:stop, :normal, state}

      {:error, reason} ->
        Logger.error("Accept failed: #{inspect(reason)}")
        :timer.sleep(1000)
        send(self(), :accept)
        {:noreply, state}
    end
  end
end

