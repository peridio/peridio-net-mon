defmodule Peridio.NetMon.RouteManager do
  @moduledoc """
  This module manages the default route.

  Devices with more than one network interface may have more than one
  way of reaching the Internet. The routing table decides which interface
  an IP packet should use by looking at the "default route" entries.
  One interface is chosen.

  Since not all interfaces are equal, we'd like Linux to pick the
  fastest and lowest latency one. for example, one could
  prefer wired Ethernet over WiFi and prefer WiFi over a cellular
  connection. This module lets you specify an ordering for interfaces
  and sets up the routes based on this ordering.

  This module also handles networking failures. One failure that
  Linux can't figure out on its own is whether an interface can
  reach the Internet. Internet reachability is handled elsewhere
  like in the `ConnectivityChecker` module. This module should be
  told reachability status so that it can properly order default
  routes so that the best reachable interface is used.

  IMPORTANT: This module uses priority-based routing. Make sure the
  following kernel options are enabled:

  ```text
  CONFIG_IP_ADVANCED_ROUTER=y
  CONFIG_IP_MULTIPLE_TABLES=y
  ```
  """
  use GenServer

  alias Peridio.NetMon.Interface.NameUtilities
  alias Peridio.NetMon.Route
  alias Peridio.NetMon.Route.{Calculator, DefaultMetric, InterfaceInfo, Properties}
  require Logger

  @typedoc false
  @type state() :: %{
          interfaces: %{Peridio.NetMon.ifname() => InterfaceInfo.t()},
          route_state: Calculator.table_indices(),
          routes: Route.entries(),
          route_metric_fun: Route.route_metric_fun()
        }

  @doc """
  Start the route manager

  Options:

  * `:route_metric_fun` - a 2-arity function that takes a ifname and `Peridio.NetMon.Route.InterfaceInfo`
    and returns `Peridio.NetMon.Route.metric()`
  """
  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @doc """
  Stop the route manager.
  """
  @spec stop() :: :ok
  def stop() do
    GenServer.stop(__MODULE__)
  end

  @doc """
  Set the connection status on an interface.

  Changing the connection status can re-prioritize routing. The
  specified interface doesn't need to have a default route.
  """
  @spec set_connection_status(
          Peridio.NetMon.ifname(),
          Peridio.NetMon.connection_status(),
          String.t() | nil
        ) ::
          :ok
  def set_connection_status(ifname, status, why \\ nil) do
    why = why || caller()
    GenServer.call(__MODULE__, {:set_connection_status, ifname, status, why})
  end

  defp caller() do
    {:current_stacktrace, [_info, _caller_fun, _peridio_net_mon_fun, {m, f, a, loc} | _rest]} =
      Process.info(self(), :current_stacktrace)

    "#{m}.#{f}/#{a}(#{inspect(loc)})"
  end

  ## GenServer

  @impl GenServer
  def init(args) do
    route_metric_fun = args[:route_metric_fun] |> check_compute_metric()

    state =
      %{
        interfaces: %{},
        route_state: Calculator.init(),
        route_metric_fun: route_metric_fun,
        routes: []
      }
      |> update_route_tables()

    {:ok, state}
  end

  defp check_compute_metric(fun) when is_function(fun, 2), do: fun

  defp check_compute_metric(_other) do
    Logger.error("RouteManager: Expecting :route_metric_fun to be a 2-arity function")
    &DefaultMetric.compute_metric/2
  end

  @impl GenServer
  def handle_call({:set_connection_status, ifname, status, why}, _from, state) do
    new_state =
      state
      |> update_connection_status(ifname, status, why)

    {:reply, :ok, new_state}
  end

  defp new_interface_info(ifname, ip_subnets, default_gateway, status) do
    # The weight parameter prioritizes interfaces of the same type and connectivity.
    # All weights for interfaces of the same type must be different. I.e., we don't
    # leave it to chance which one is used. Also, bandwidth sharing of interfaces
    # can't be accomplished by giving interfaces the same low level priority with
    # how things are set up anyway.
    #
    # It will likely be necessary to expose this to users who have more than one
    # of the same interface type available. For now, lower numbered interfaces
    # have priority. For example, eth0 is used over eth1, etc. The 10 is hardcoded
    # to correspond to the calculation in default_metric.ex.
    weight = rem(NameUtilities.get_instance(ifname), 10)

    %InterfaceInfo{
      interface_type: NameUtilities.to_type(ifname),
      weight: weight,
      ip_subnets: ip_subnets,
      default_gateway: default_gateway,
      status: status
    }
  end

  # Only process routes if the status changes
  defp update_connection_status(state, ifname, new_status, why) do
    case state.interfaces[ifname] do
      nil ->
        Logger.warning(
          "RouteManager: new set_connection_status #{ifname} -> #{inspect(new_status)} (#{why})"
        )

        ifentry = new_interface_info(ifname, [], nil, new_status)

        put_in(state.interfaces[ifname], ifentry)
        |> update_route_tables()

      ifentry ->
        if ifentry.status != new_status do
          Logger.info(
            "RouteManager: set_connection_status #{ifname} -> #{inspect(new_status)} (#{why})"
          )

          put_in(state.interfaces[ifname].status, new_status)
          |> update_route_tables()
        else
          state
        end
    end
  end

  defp update_route_tables(state) do
    # See what changed and then run it.
    {new_route_state, new_routes} =
      Calculator.compute(state.route_state, state.interfaces, state.route_metric_fun)

    # Update the global routing properties in the property table
    # NOTE: These next three calls can update zero or more entries
    #       in the property table. There's no notion of atomicity,
    #       so it's possible for listeners to detect inconsistencies.
    #       All orderings are problematic in some scenario. However,
    #       in practice, a user is mostly listening either to the
    #       overall state (which interfaces are available on the device
    #       or whether the device can reach the internet in any way) or
    #       it's specifically interested in one interface.
    Properties.update_available_interfaces(new_routes)
    Properties.update_best_connection(state.interfaces)
    Properties.update_connection_status(state.interfaces)

    %{state | route_state: new_route_state, routes: new_routes}
  end
end
