defmodule GenServer do
  @moduledoc """
  A behaviour module for implementing the server of a client-server relation.

  A GenServer is a process like any other Elixir process and it can be used
  to keep state, execute code asynchronously and so on. The advantage of using
  a generic server process (GenServer) implemented using this module is that it
  will have a standard set of interface functions and include functionality for
  tracing and error reporting. It will also fit into a supervision tree.

  ## Example

  The GenServer behaviour abstracts the common client-server interaction.
  Developers are only required to implement the callbacks and functionality they are
  interested in.

  Let's start with a code example and then explore the available callbacks.
  Imagine we want a GenServer that works like a stack, allowing us to push
  and pop items:

      defmodule Stack do
        use GenServer

        # Callbacks

        def handle_call(:pop, _from, [h | t]) do
          {:reply, h, t}
        end

        def handle_cast({:push, item}, state) do
          {:noreply, [item | state]}
        end
      end

      # Start the server
      {:ok, pid} = GenServer.start_link(Stack, [:hello])

      # This is the client
      GenServer.call(pid, :pop)
      #=> :hello

      GenServer.cast(pid, {:push, :world})
      #=> :ok

      GenServer.call(pid, :pop)
      #=> :world

  We start our `Stack` by calling `start_link/3`, passing the module
  with the server implementation and its initial argument (a list
  representing the stack containing the item `:hello`). We can primarily
  interact with the server by sending two types of messages. **call**
  messages expect a reply from the server (and are therefore synchronous)
  while **cast** messages do not.

  Every time you do a `GenServer.call/3`, the client will send a message
  that must be handled by the `c:handle_call/3` callback in the GenServer.
  A `cast/2` message must be handled by `c:handle_cast/2`.

  ## Callbacks

  There are 6 callbacks required to be implemented in a `GenServer`. By
  adding `use GenServer` to your module, Elixir will automatically define
  all 6 callbacks for you, leaving it up to you to implement the ones
  you want to customize.

  ## Name Registration

  Both `start_link/3` and `start/3` support the `GenServer` to register
  a name on start via the `:name` option. Registered names are also
  automatically cleaned up on termination. The supported values are:

    * an atom - the GenServer is registered locally with the given name
      using `Process.register/2`.

    * `{:global, term}`- the GenServer is registered globally with the given
      term using the functions in the [`:global` module](http://www.erlang.org/doc/man/global.html).

    * `{:via, module, term}` - the GenServer is registered with the given
      mechanism and name. The `:via` option expects a module that exports
      `register_name/2`, `unregister_name/1`, `whereis_name/1` and `send/2`.
      One such example is the [`:global` module](http://www.erlang.org/doc/man/global.html) which uses these functions
      for keeping the list of names of processes and their associated PIDs
      that are available globally for a network of Elixir nodes. Elixir also
      ships with a local, decentralized and scalable registry called `Registry`
      for locally storing names that are generated dynamically.

  For example, we could start and register our `Stack` server locally as follows:

      # Start the server and register it locally with name MyStack
      {:ok, _} = GenServer.start_link(Stack, [:hello], name: MyStack)

      # Now messages can be sent directly to MyStack
      GenServer.call(MyStack, :pop) #=> :hello

  Once the server is started, the remaining functions in this module (`call/3`,
  `cast/2`, and friends) will also accept an atom, or any `:global` or `:via`
  tuples. In general, the following formats are supported:

    * a `pid`
    * an `atom` if the server is locally registered
    * `{atom, node}` if the server is locally registered at another node
    * `{:global, term}` if the server is globally registered
    * `{:via, module, name}` if the server is registered through an alternative
      registry

  If there is an interest to register dynamic names locally, do not use
  atoms, as atoms are never garbage collected and therefore dynamically
  generated atoms won't be garbage collected. For such cases, you can
  set up your own local registry by using the `Registry` module.

  ## Client / Server APIs

  Although in the example above we have used `GenServer.start_link/3` and
  friends to directly start and communicate with the server, most of the
  time we don't call the `GenServer` functions directly. Instead, we wrap
  the calls in new functions representing the public API of the server.

  Here is a better implementation of our Stack module:

      defmodule Stack do
        use GenServer

        # Client

        def start_link(default) do
          GenServer.start_link(__MODULE__, default)
        end

        def push(pid, item) do
          GenServer.cast(pid, {:push, item})
        end

        def pop(pid) do
          GenServer.call(pid, :pop)
        end

        # Server (callbacks)

        def handle_call(:pop, _from, [h | t]) do
          {:reply, h, t}
        end

        def handle_call(request, from, state) do
          # Call the default implementation from GenServer
          super(request, from, state)
        end

        def handle_cast({:push, item}, state) do
          {:noreply, [item | state]}
        end

        def handle_cast(request, state) do
          super(request, state)
        end
      end

  In practice, it is common to have both server and client functions in
  the same module. If the server and/or client implementations are growing
  complex, you may want to have them in different modules.

  ## Receiving "regular" messages

  The goal of a `GenServer` is to abstract the "receive" loop for developers,
  automatically handling system messages, support code change, synchronous
  calls and more. Therefore, you should never call your own "receive" inside
  the GenServer callbacks as doing so will cause the GenServer to misbehave.

  Besides the synchronous and asynchronous communication provided by `call/3`
  and `cast/2`, "regular" messages sent by functions such `Kernel.send/2`,
  `Process.send_after/4` and similar, can be handled inside the `c:handle_info/2`
  callback.

  `c:handle_info/2` can be used in many situations, such as handling monitor
  DOWN messages sent by `Process.monitor/1`. Another use case for `c:handle_info/2`
  is to perform periodic work, with the help of `Process.send_after/4`:

      defmodule MyApp.Periodically do
        use GenServer

        def start_link do
          GenServer.start_link(__MODULE__, %{})
        end

        def init(state) do
          schedule_work() # Schedule work to be performed on start
          {:ok, state}
        end

        def handle_info(:work, state) do
          # Do the desired work here
          schedule_work() # Reschedule once more
          {:noreply, state}
        end

        defp schedule_work() do
          Process.send_after(self(), :work, 2 * 60 * 60 * 1000) # In 2 hours
        end
      end

  ## Debugging with the :sys module

  GenServers, as [special processes](http://erlang.org/doc/design_principles/spec_proc.html),
  can be debugged using the [`:sys` module](http://www.erlang.org/doc/man/sys.html). Through various hooks, this module
  allows developers to introspect the state of the process and trace
  system events that happen during its execution, such as received messages,
  sent replies and state changes.

  Let's explore the basic functions from the [`:sys` module](http://www.erlang.org/doc/man/sys.html) used for debugging:

    * [`:sys.get_state/2`](http://erlang.org/doc/man/sys.html#get_state-2) -
      allows retrieval of the state of the process. In the case of
      a GenServer process, it will be the callback module state, as
      passed into the callback functions as last argument.
    * [`:sys.get_status/2`](http://erlang.org/doc/man/sys.html#get_status-2) -
      allows retrieval of the status of the process. This status includes
      the process dictionary, if the process is running or is suspended,
      the parent PID, the debugger state, and the state of the behaviour module,
      which includes the callback module state (as returned by `:sys.get_state/2`).
      It's possible to change how this status is represented by defining
      the optional `c:GenServer.format_status/2` callback.
    * [`:sys.trace/3`](http://erlang.org/doc/man/sys.html#trace-3) -
      prints all the system events to `:stdio`.
    * [`:sys.statistics/3`](http://erlang.org/doc/man/sys.html#statistics-3) -
      manages collection of process statistics.
    * [`:sys.no_debug/2`](http://erlang.org/doc/man/sys.html#no_debug-2) -
      turns off all debug handlers for the given process. It is very important
      to switch off debugging once we're done. Excessive debug handlers or
      those that should be turned off, but weren't, can seriously damage
      the performance of the system.

  Let's see how we could use those functions for debugging the stack server
  we defined earlier.

      iex> {:ok, pid} = Stack.start_link([])
      iex> :sys.statistics(pid, true) # turn on collecting process statistics
      iex> :sys.trace(pid, true) # turn on event printing
      iex> Stack.push(pid, 1)
      *DBG* <0.122.0> got cast {push,1}
      *DBG* <0.122.0> new state [1]
      :ok
      iex> :sys.get_state(pid)
      [1]
      iex> Stack.pop(pid)
      *DBG* <0.122.0> got call pop from <0.80.0>
      *DBG* <0.122.0> sent 1 to <0.80.0>, new state []
      1
      iex> :sys.statistics(pid, :get)
      {:ok,
       [start_time: {{2016, 7, 16}, {12, 29, 41}},
        current_time: {{2016, 7, 16}, {12, 29, 50}},
        reductions: 117, messages_in: 2, messages_out: 0]}
      iex> :sys.no_debug(pid) # turn off all debug handlers
      :ok
      iex> :sys.get_status(pid)
      {:status, #PID<0.122.0>, {:module, :gen_server},
       [["$initial_call": {Stack, :init, 1},            # pdict
         "$ancestors": [#PID<0.80.0>, #PID<0.51.0>]],
        :running,                                       # :running | :suspended
        #PID<0.80.0>,                                   # parent
        [],                                             # debugger state
        [header: 'Status for generic server <0.122.0>', # module status
         data: [{'Status', :running}, {'Parent', #PID<0.80.0>},
           {'Logged events', []}], data: [{'State', [1]}]]]}

  ## Learn more

  If you wish to find out more about gen servers, the Elixir Getting Started
  guide provides a tutorial-like introduction. The documentation and links
  in Erlang can also provide extra insight.

    * [GenServer – Elixir's Getting Started Guide](http://elixir-lang.org/getting-started/mix-otp/genserver.html)
    * [`:gen_server` module documentation](http://www.erlang.org/doc/man/gen_server.html)
    * [gen_server Behaviour – OTP Design Principles](http://www.erlang.org/doc/design_principles/gen_server_concepts.html)
    * [Clients and Servers – Learn You Some Erlang for Great Good!](http://learnyousomeerlang.com/clients-and-servers)
  """

  @doc """
  Invoked when the server is started. `start_link/3` or `start/3` will
  block until it returns.

  `args` is the argument term (second argument) passed to `start_link/3`.

  Returning `{:ok, state}` will cause `start_link/3` to return
  `{:ok, pid}` and the process to enter its loop.

  Returning `{:ok, state, timeout}` is similar to `{:ok, state}`
  except `handle_info(:timeout, state)` will be called after `timeout`
  milliseconds if no messages are received within the timeout.

  Returning `{:ok, state, :hibernate}` is similar to
  `{:ok, state}` except the process is hibernated before entering the loop. See
  `c:handle_call/3` for more information on hibernation.

  Returning `:ignore` will cause `start_link/3` to return `:ignore` and the
  process will exit normally without entering the loop or calling `c:terminate/2`.
  If used when part of a supervision tree the parent supervisor will not fail
  to start nor immediately try to restart the `GenServer`. The remainder of the
  supervision tree will be (re)started and so the `GenServer` should not be
  required by other processes. It can be started later with
  `Supervisor.restart_child/2` as the child specification is saved in the parent
  supervisor. The main use cases for this are:

    * The `GenServer` is disabled by configuration but might be enabled later.
    * An error occurred and it will be handled by a different mechanism than the
     `Supervisor`. Likely this approach involves calling `Supervisor.restart_child/2`
      after a delay to attempt a restart.

  Returning `{:stop, reason}` will cause `start_link/3` to return
  `{:error, reason}` and the process to exit with reason `reason` without
  entering the loop or calling `c:terminate/2`.
  """
  @callback init(args :: term) ::
    {:ok, state} |
    {:ok, state, timeout | :hibernate} |
    :ignore |
    {:stop, reason :: any} when state: any

  @doc """
  Invoked to handle synchronous `call/3` messages. `call/3` will block until a
  reply is received (unless the call times out or nodes are disconnected).

  `request` is the request message sent by a `call/3`, `from` is a 2-tuple
  containing the caller's PID and a term that uniquely identifies the call, and
  `state` is the current state of the `GenServer`.

  Returning `{:reply, reply, new_state}` sends the response `reply` to the
  caller and continues the loop with new state `new_state`.

  Returning `{:reply, reply, new_state, timeout}` is similar to
  `{:reply, reply, new_state}` except `handle_info(:timeout, new_state)` will be
  called after `timeout` milliseconds if no messages are received.

  Returning `{:reply, reply, new_state, :hibernate}` is similar to
  `{:reply, reply, new_state}` except the process is hibernated and will
  continue the loop once a message is in its message queue. If a message is
  already in the message queue this will be immediately. Hibernating a
  `GenServer` causes garbage collection and leaves a continuous heap that
  minimises the memory used by the process.

  Hibernating should not be used aggressively as too much time could be spent
  garbage collecting. Normally it should only be used when a message is not
  expected soon and minimising the memory of the process is shown to be
  beneficial.

  Returning `{:noreply, new_state}` does not send a response to the caller and
  continues the loop with new state `new_state`. The response must be sent with
  `reply/2`.

  There are three main use cases for not replying using the return value:

    * To reply before returning from the callback because the response is known
      before calling a slow function.
    * To reply after returning from the callback because the response is not yet
      available.
    * To reply from another process, such as a task.

  When replying from another process the `GenServer` should exit if the other
  process exits without replying as the caller will be blocking awaiting a
  reply.

  Returning `{:noreply, new_state, timeout | :hibernate}` is similar to
  `{:noreply, new_state}` except a timeout or hibernation occurs as with a
  `:reply` tuple.

  Returning `{:stop, reason, reply, new_state}` stops the loop and `c:terminate/2`
  is called with reason `reason` and state `new_state`. Then the `reply` is sent
  as the response to call and the process exits with reason `reason`.

  Returning `{:stop, reason, new_state}` is similar to
  `{:stop, reason, reply, new_state}` except a reply is not sent.

  If this callback is not implemented, the default implementation by
  `use GenServer` will return `{:stop, {:bad_call, request}, state}`.
  """
  @callback handle_call(request :: term, from, state :: term) ::
    {:reply, reply, new_state} |
    {:reply, reply, new_state, timeout | :hibernate} |
    {:noreply, new_state} |
    {:noreply, new_state, timeout | :hibernate} |
    {:stop, reason, reply, new_state} |
    {:stop, reason, new_state} when reply: term, new_state: term, reason: term

  @doc """
  Invoked to handle asynchronous `cast/2` messages.

  `request` is the request message sent by a `cast/2` and `state` is the current
  state of the `GenServer`.

  Returning `{:noreply, new_state}` continues the loop with new state `new_state`.

  Returning `{:noreply, new_state, timeout}` is similar to
  `{:noreply, new_state}` except `handle_info(:timeout, new_state)` will be
  called after `timeout` milliseconds if no messages are received.

  Returning `{:noreply, new_state, :hibernate}` is similar to
  `{:noreply, new_state}` except the process is hibernated before continuing the
  loop. See `c:handle_call/3` for more information.

  Returning `{:stop, reason, new_state}` stops the loop and `c:terminate/2` is
  called with the reason `reason` and state `new_state`. The process exits with
  reason `reason`.

  If this callback is not implemented, the default implementation by
  `use GenServer` will return `{:stop, {:bad_cast, request}, state}`.
  """
  @callback handle_cast(request :: term, state :: term) ::
    {:noreply, new_state} |
    {:noreply, new_state, timeout | :hibernate} |
    {:stop, reason :: term, new_state} when new_state: term

  @doc """
  Invoked to handle all other messages.

  `msg` is the message and `state` is the current state of the `GenServer`. When
  a timeout occurs the message is `:timeout`.

  Return values are the same as `c:handle_cast/2`.

  If this callback is not implemented, the default implementation by
  `use GenServer` will return `{:noreply, state}`.
  """
  @callback handle_info(msg :: :timeout | term, state :: term) ::
    {:noreply, new_state} |
    {:noreply, new_state, timeout | :hibernate} |
    {:stop, reason :: term, new_state} when new_state: term

  @doc """
  Invoked when the server is about to exit. It should do any cleanup required.

  `reason` is exit reason and `state` is the current state of the `GenServer`.
  The return value is ignored.

  `c:terminate/2` is called if a callback (except `c:init/1`) does one of the
  following:

    * returns a `:stop` tuple
    * raises
    * calls `Kernel.exit/1`
    * returns an invalid value
    * the `GenServer` traps exits (using `Process.flag/2`) *and* the parent
      process sends an exit signal

  If part of a supervision tree, a `GenServer`'s `Supervisor` will send an exit
  signal when shutting it down. The exit signal is based on the shutdown
  strategy in the child's specification. If it is `:brutal_kill` the `GenServer`
  is killed and so `c:terminate/2` is not called. However if it is a timeout the
  `Supervisor` will send the exit signal `:shutdown` and the `GenServer` will
  have the duration of the timeout to call `c:terminate/2` - if the process is
  still alive after the timeout it is killed.

  If the `GenServer` receives an exit signal (that is not `:normal`) from any
  process when it is not trapping exits it will exit abruptly with the same
  reason and so not call `c:terminate/2`. Note that a process does *NOT* trap
  exits by default and an exit signal is sent when a linked process exits or its
  node is disconnected.

  Therefore it is not guaranteed that `c:terminate/2` is called when a `GenServer`
  exits. For such reasons, we usually recommend important clean-up rules to
  happen in separated processes either by use of monitoring or by links
  themselves. For example if the `GenServer` controls a `port` (e.g.
  `:gen_tcp.socket`) or `t:File.io_device/0`, they will be closed on receiving a
  `GenServer`'s exit signal and do not need to be closed in `c:terminate/2`.

  If `reason` is not `:normal`, `:shutdown`, nor `{:shutdown, term}` an error is
  logged.
  """
  @callback terminate(reason, state :: term) ::
    term when reason: :normal | :shutdown | {:shutdown, term} | term

  @doc """
  Invoked to change the state of the `GenServer` when a different version of a
  module is loaded (hot code swapping) and the state's term structure should be
  changed.

  `old_vsn` is the previous version of the module (defined by the `@vsn`
  attribute) when upgrading. When downgrading the previous version is wrapped in
  a 2-tuple with first element `:down`. `state` is the current state of the
  `GenServer` and `extra` is any extra data required to change the state.

  Returning `{:ok, new_state}` changes the state to `new_state` and the code
  change is successful.

  Returning `{:error, reason}` fails the code change with reason `reason` and
  the state remains as the previous state.

  If `c:code_change/3` raises the code change fails and the loop will continue
  with its previous state. Therefore this callback does not usually contain side effects.
  """
  @callback code_change(old_vsn, state :: term, extra :: term) ::
    {:ok, new_state :: term} |
    {:error, reason :: term} when old_vsn: term | {:down, term}

  @doc """
  Invoked in some cases to retrieve a formatted version of the `GenServer` status.

  This callback can be useful to control the *appearance* of the status of the
  `GenServer`. For example, it can be used to return a compact representation of
  the `GenServer`'s state to avoid having large state terms printed.

    * one of `:sys.get_status/1` or `:sys.get_status/2` is invoked to get the
      status of the `GenServer`; in such cases, `reason` is `:normal`

    * the `GenServer` terminates abnormally and logs an error; in such cases,
      `reason` is `:terminate`

  `pdict_and_state` is a two-elements list `[pdict, state]` where `pdict` is a
  list of `{key, value}` tuples representing the current process dictionary of
  the `GenServer` and `state` is the current state of the `GenServer`.
  """
  @callback format_status(reason, pdict_and_state :: list) ::
    term when reason: :normal | :terminate

  @optional_callbacks format_status: 2

  @typedoc "Return values of `start*` functions"
  @type on_start :: {:ok, pid} | :ignore | {:error, {:already_started, pid} | term}

  @typedoc "The GenServer name"
  @type name :: atom | {:global, term} | {:via, module, term}

  @typedoc "Options used by the `start*` functions"
  @type options :: [option]

  @typedoc "Option values used by the `start*` functions"
  @type option :: {:debug, debug} |
                  {:name, name} |
                  {:timeout, timeout} |
                  {:spawn_opt, Process.spawn_opt}

  @typedoc "Debug options supported by the `start*` functions"
  @type debug :: [:trace | :log | :statistics | {:log_to_file, Path.t}]

  @typedoc "The server reference"
  @type server :: pid | name | {atom, node}

  @typedoc """
  Tuple describing the client of a call request.

  `pid` is the PID of the caller and `tag` is a unique term used to identify the
  call.
  """
  @type from :: {pid, tag :: term}

  @doc false
  defmacro __using__(_) do
    quote location: :keep do
      @behaviour GenServer

      @doc false
      def init(args) do
        {:ok, args}
      end

      @doc false
      def handle_call(msg, _from, state) do
        proc =
          case Process.info(self(), :registered_name) do
            {_, []}   -> self()
            {_, name} -> name
          end

        # We do this to trick Dialyzer to not complain about non-local returns.
        case :erlang.phash2(1, 1) do
          0 -> raise "attempted to call GenServer #{inspect proc} but no handle_call/3 clause was provided"
          1 -> {:stop, {:bad_call, msg}, state}
        end
      end

      @doc false
      def handle_info(msg, state) do
        proc =
          case Process.info(self(), :registered_name) do
            {_, []}   -> self()
            {_, name} -> name
          end
        :error_logger.error_msg('~p ~p received unexpected message in handle_info/2: ~p~n',
                                [__MODULE__, proc, msg])
        {:noreply, state}
      end

      @doc false
      def handle_cast(msg, state) do
        proc =
          case Process.info(self(), :registered_name) do
            {_, []}   -> self()
            {_, name} -> name
          end

        # We do this to trick Dialyzer to not complain about non-local returns.
        case :erlang.phash2(1, 1) do
          0 -> raise "attempted to cast GenServer #{inspect proc} but no handle_cast/2 clause was provided"
          1 -> {:stop, {:bad_cast, msg}, state}
        end
      end

      @doc false
      def terminate(_reason, _state) do
        :ok
      end

      @doc false
      def code_change(_old, state, _extra) do
        {:ok, state}
      end

      defoverridable [init: 1, handle_call: 3, handle_info: 2,
                      handle_cast: 2, terminate: 2, code_change: 3]
    end
  end

  @doc """
  Starts a `GenServer` process linked to the current process.

  This is often used to start the `GenServer` as part of a supervision tree.

  Once the server is started, the `c:init/1` function of the given `module` is
  called with `args` as its arguments to initialize the server. To ensure a
  synchronized start-up procedure, this function does not return until `c:init/1`
  has returned.

  Note that a `GenServer` started with `start_link/3` is linked to the
  parent process and will exit in case of crashes from the parent. The GenServer
  will also exit due to the `:normal` reasons in case it is configured to trap
  exits in the `c:init/1` callback.

  ## Options

    * `:name` - used for name registration as described in the "Name
      registration" section of the module documentation

    * `:timeout` - if present, the server is allowed to spend the given amount of
      milliseconds initializing or it will be terminated and the start function
      will return `{:error, :timeout}`

    * `:debug` - if present, the corresponding function in the [`:sys` module](http://www.erlang.org/doc/man/sys.html) is invoked

    * `:spawn_opt` - if present, its value is passed as options to the
      underlying process as in `Process.spawn/4`

  ## Return values

  If the server is successfully created and initialized, this function returns
  `{:ok, pid}`, where `pid` is the PID of the server. If a process with the
  specified server name already exists, this function returns
  `{:error, {:already_started, pid}}` with the PID of that process.

  If the `c:init/1` callback fails with `reason`, this function returns
  `{:error, reason}`. Otherwise, if it returns `{:stop, reason}`
  or `:ignore`, the process is terminated and this function returns
  `{:error, reason}` or `:ignore`, respectively.
  """
  @spec start_link(module, any, options) :: on_start
  def start_link(module, args, options \\ []) when is_atom(module) and is_list(options) do
    do_start(:link, module, args, options)
  end

  @doc """
  Starts a `GenServer` process without links (outside of a supervision tree).

  See `start_link/3` for more information.
  """
  @spec start(module, any, options) :: on_start
  def start(module, args, options \\ []) when is_atom(module) and is_list(options) do
    do_start(:nolink, module, args, options)
  end

  defp do_start(link, module, args, options) do
    case Keyword.pop(options, :name) do
      {nil, opts} ->
        :gen.start(:gen_server, link, module, args, opts)
      {atom, opts} when is_atom(atom) ->
        :gen.start(:gen_server, link, {:local, atom}, module, args, opts)
      {{:global, _term} = tuple, opts} ->
        :gen.start(:gen_server, link, tuple, module, args, opts)
      {{:via, via_module, _term} = tuple, opts} when is_atom(via_module) ->
        :gen.start(:gen_server, link, tuple, module, args, opts)
      other ->
        raise ArgumentError, """
        expected :name option to be one of:

          * nil
          * atom
          * {:global, term}
          * {:via, module, term}

        Got: #{inspect(other)}
        """
    end
  end

  @doc """
  Synchronously stops the server with the given `reason`.

  The `c:terminate/2` callback of the given `server` will be invoked before
  exiting. This function returns `:ok` if the server terminates with the
  given reason; if it terminates with another reason, the call exits.

  This function keeps OTP semantics regarding error reporting.
  If the reason is any other than `:normal`, `:shutdown` or
  `{:shutdown, _}`, an error report is logged.
  """
  @spec stop(server, reason :: term, timeout) :: :ok
  def stop(server, reason \\ :normal, timeout \\ :infinity) do
    :gen.stop(server, reason, timeout)
  end

  @doc """
  Makes a synchronous call to the `server` and waits for its reply.

  The client sends the given `request` to the server and waits until a reply
  arrives or a timeout occurs. `c:handle_call/3` will be called on the server
  to handle the request.

  `server` can be any of the values described in the "Name registration"
  section of the documentation for this module.

  ## Timeouts

  `timeout` is an integer greater than zero which specifies how many
  milliseconds to wait for a reply, or the atom `:infinity` to wait
  indefinitely. The default value is `5000`. If no reply is received within
  the specified time, the function call fails and the caller exits. If the
  caller catches the failure and continues running, and the server is just late
  with the reply, it may arrive at any time later into the caller's message
  queue. The caller must in this case be prepared for this and discard any such
  garbage messages that are two-element tuples with a reference as the first
  element.
  """
  @spec call(server, term, timeout) :: term
  def call(server, request, timeout \\ 5000) do
    case whereis(server) do
      nil ->
        exit({:noproc, {__MODULE__, :call, [server, request, timeout]}})
      pid when pid == self() ->
        exit({:calling_self, {__MODULE__, :call, [server, request, timeout]}})
      pid ->
        try do
          :gen.call(pid, :"$gen_call", request, timeout)
        catch
          :exit, reason ->
            exit({reason, {__MODULE__, :call, [server, request, timeout]}})
        else
          {:ok, res} -> res
        end
    end
  end

  @doc """
  Sends an asynchronous request to the `server`.

  This function always returns `:ok` regardless of whether
  the destination `server` (or node) exists. Therefore it
  is unknown whether the destination `server` successfully
  handled the message.

  `c:handle_cast/2` will be called on the server to handle
  the request. In case the `server` is on a node which is
  not yet connected to the caller one, the call is going to
  block until a connection happens. This is different than
  the behaviour in OTP's `:gen_server` where the message
  is sent by another process in this case, which could cause
  messages to other nodes to arrive out of order.
  """
  @spec cast(server, term) :: :ok
  def cast(server, request)

  def cast({:global, name}, request) do
    try do
      :global.send(name, cast_msg(request))
      :ok
    catch
      _, _ -> :ok
    end
  end

  def cast({:via, mod, name}, request) do
    try do
      mod.send(name, cast_msg(request))
      :ok
    catch
      _, _ -> :ok
    end
  end

  def cast({name, node}, request) when is_atom(name) and is_atom(node),
    do: do_send({name, node}, cast_msg(request))

  def cast(dest, request) when is_atom(dest) or is_pid(dest),
    do: do_send(dest, cast_msg(request))

  @doc """
  Casts all servers locally registered as `name` at the specified nodes.

  This function returns immediately and ignores nodes that do not exist, or where the
  server name does not exist.

  See `multi_call/4` for more information.
  """
  @spec abcast([node], name :: atom, term) :: :abcast
  def abcast(nodes \\ [node() | Node.list()], name, request) when is_list(nodes) and is_atom(name) do
    msg = cast_msg(request)
    _   = for node <- nodes, do: do_send({name, node}, msg)
    :abcast
  end

  defp cast_msg(req) do
    {:"$gen_cast", req}
  end

  defp do_send(dest, msg) do
    try do
      send(dest, msg)
      :ok
    catch
      _, _ -> :ok
    end
  end

  @doc """
  Calls all servers locally registered as `name` at the specified `nodes`.

  First, the `request` is sent to every node in `nodes`; then, the caller waits
  for the replies. This function returns a two-element tuple `{replies,
  bad_nodes}` where:

    * `replies` - is a list of `{node, reply}` tuples where `node` is the node
      that replied and `reply` is its reply
    * `bad_nodes` - is a list of nodes that either did not exist or where a
      server with the given `name` did not exist or did not reply

  `nodes` is a list of node names to which the request is sent. The default
  value is the list of all known nodes (including this node).

  To avoid that late answers (after the timeout) pollute the caller's message
  queue, a middleman process is used to do the actual calls. Late answers will
  then be discarded when they arrive to a terminated process.

  ## Examples

  Assuming the `Stack` GenServer mentioned in the docs for the `GenServer`
  module is registered as `Stack` in the `:"foo@my-machine"` and
  `:"bar@my-machine"` nodes:

      GenServer.multi_call(Stack, :pop)
      #=> {[{:"foo@my-machine", :hello}, {:"bar@my-machine", :world}], []}

  """
  @spec multi_call([node], name :: atom, term, timeout) ::
                  {replies :: [{node, term}], bad_nodes :: [node]}
  def multi_call(nodes \\ [node() | Node.list()], name, request, timeout \\ :infinity) do
    :gen_server.multi_call(nodes, name, request, timeout)
  end

  @doc """
  Replies to a client.

  This function can be used to explicitly send a reply to a client that called
  `call/3` or `multi_call/4` when the reply cannot be specified in the return
  value of `c:handle_call/3`.

  `client` must be the `from` argument (the second argument) accepted by
  `c:handle_call/3` callbacks. `reply` is an arbitrary term which will be given
  back to the client as the return value of the call. The `from` argument is a tuple 
  consisting of a caller's PID and a reference, eg. `{#PID<0.72.0>, #Reference<0.0.4.992>}`.

  Note that `reply/2` can be called from any process, not just the GenServer
  that originally received the call (as long as that GenServer communicated the
  `from` argument somehow).

  This function always returns `:ok`.

  ## Examples

      def handle_call(:reply_in_one_second, from, state) do
        Process.send_after(self(), {:reply, from}, 1_000)
        {:noreply, state}
      end

      def handle_info({:reply, from}, state) do
        GenServer.reply(from, :one_second_has_passed)
        {:noreply, state}
      end

  """
  @spec reply(from, term) :: :ok
  def reply(client, reply)

  def reply({to, tag}, reply) when is_pid(to) do
    try do
      send(to, {tag, reply})
      :ok
    catch
      _, _ -> :ok
    end
  end

  @doc """
  Returns the `pid` or `{name, node}` of a GenServer process, or `nil` if
  no process is associated with the given name.

  ## Examples

  For example, to lookup a server process, monitor it and send a cast to it:

      process = GenServer.whereis(server)
      monitor = Process.monitor(process)
      GenServer.cast(process, :hello)

  """
  @spec whereis(server) :: pid | {atom, node} | nil
  def whereis(pid) when is_pid(pid), do: pid
  def whereis(name) when is_atom(name) do
    Process.whereis(name)
  end
  def whereis({:global, name}) do
    case :global.whereis_name(name) do
      pid when is_pid(pid) -> pid
      :undefined           -> nil
    end
  end
  def whereis({:via, mod, name}) do
    case apply(mod, :whereis_name, [name]) do
      pid when is_pid(pid) -> pid
      :undefined           -> nil
    end
  end
  def whereis({name, local}) when is_atom(name) and local == node() do
    Process.whereis(name)
  end
  def whereis({name, node} = server) when is_atom(name) and is_atom(node) do
    server
  end
end
