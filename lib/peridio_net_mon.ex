defmodule Peridio.NetMon do
  @moduledoc """
  * Simple subscription to network status change events
  * Internet connection monitoring and failure detection (currently slow and
    simplistic)
  """

  alias Peridio.NetMon.Info

  @typedoc """
  A name for the network interface

  Names depend on the device drivers and any software that may rename them.
  Typical names on Nerves are:

  * "eth0", "eth1", etc. for wired Ethernet interfaces
  * "wlan0", etc. for WiFi interfaces
  * "ppp0" for cellular modems
  * "usb0" for gadget USB virtual Ethernet interfaces
  """
  @type ifname :: String.t()

  @typedoc """
  IP addresses in Peridio.NetMon can be specified as strings or tuples

  While Peridio.NetMon uses IP addresses in tuple form internally, it can be
  cumbersome to always convert to tuple form in practice. The general rule is
  that Peridio.NetMon is flexible in how it accepts IP addresses, but if you get an
  address from a Peridio.NetMon API, it will be in tuple form.
  """
  @type any_ip_address :: String.t() | :inet.ip_address()

  @typedoc """
  The number of IP address bits for the subnet
  """
  @type prefix_length :: ipv4_prefix_length() | ipv6_prefix_length()

  @typedoc """
  The number of bits to use for an IPv4 subnet

  For example, if you have a subnet mask of 255.255.255.0, then the prefix
  length would be 24.
  """
  @type ipv4_prefix_length :: 0..32

  @typedoc """
  The number of bits to use for an IPv6 subnet
  """
  @type ipv6_prefix_length :: 0..128

  @typedoc """
  Interface connection status

  * `:disconnected` - The interface doesn't exist or it's not connected
  * `:lan` - The interface is connected to the LAN, but may not be able
    reach the Internet
  * `:internet` - Packets going through the interface should be able to
    reach the Internet
  """
  @type connection_status :: :lan | :internet | :disconnected

  @typedoc """
  Valid options for `Peridio.NetMon.info/1`

  * `:redact` - Whether to hide passwords and similar information from the output (defaults to `true`)
  """
  @type info_options :: [redact: boolean()]

  @typedoc """
  A Peridio.NetMon property

  Peridio.NetMon uses lists of strings to name networking configuration and status
  items.
  """
  @type property :: [String.t()]

  @typedoc """
  A pattern for matching against Peridio.NetMon properties

  Patterns are used when subscribing for network property changes or getting a
  set of properties and their values.

  Since properties are organized hierarchically, the default way of matching patterns is to match on prefixes. It's also
  possible to use the `:_` wildcard to match anything at a position.
  """
  @type pattern :: [String.t() | :_ | :"$"]

  @typedoc """
  A property's value

  See the `README.md` for documentation on available properties.
  """
  @type value :: any()

  @doc """
  Return a list of all interfaces on the system
  """
  @spec all_interfaces() :: [ifname()]
  def all_interfaces() do
    present = Peridio.NetMon.match(["interface", :_, "present"])

    for {[_interface, ifname, _present], true} <- present do
      ifname
    end
  end

  @doc """
  Return the maximum number of interfaces controlled by Peridio.NetMon

  Internal constraints mean that Peridio.NetMon can't manage an arbitrary number of
  interfaces and knowing the max can reduce some processing. The limit is set
  by the application config. Unless you need over 100 network interfaces,
  Peridio.NetMon's use of the Linux networking API is not likely to be an issue,
  though.
  """
  @spec max_interface_count() :: 1..100
  def max_interface_count() do
    Application.get_env(:peridio_net_mon, :max_interface_count)
  end

  @doc """
  Get the current value of a network property

  See `get_by_prefix/1` for exact prefix matches (i.e., get all properties for one
  interface) and `match/1` to run wildcard matches (i.e., get a specific
  property for all interfaces).
  """
  @spec get(property(), value()) :: value()
  def get(name, default \\ nil) do
    PropertyTable.get(Peridio.NetMon, name, default)
  end

  @doc """
  Get a list of all properties matching a pattern

  Patterns are list of strings that optionally specify `:_` at
  a position in the list to match any value.
  """
  @spec match(pattern()) :: [{property(), value()}]
  def match(pattern) do
    PropertyTable.match(Peridio.NetMon, pattern ++ [:"$"]) |> Enum.sort()
  end

  @doc """
  Get a list of all properties matching the specified prefix

  To get a list of all known properties and their values, call
  `Peridio.NetMon.get_by_prefix([])`
  """
  @spec get_by_prefix(property()) :: [{property(), value()}]
  def get_by_prefix(pattern) do
    PropertyTable.match(Peridio.NetMon, pattern) |> Enum.sort()
  end

    @doc """
  Subscribe to property change messages

  Messages have the form:

  ```
  {Peridio.NetMon, property_name, old_value, new_value, metadata}
  ```

  Subscriptions are prefix matches. For example, to get notified whenever a property
  changes on "wlan0", run this:

  ```
  Peridio.NetMon.subscribe(["interface", "wlan0"])
  ```

  It's also possible to match with wildcards using `:_`. For example, to
  get notified whenever an IP address in the system changes, do this:

  ```
  Peridio.NetMon.subscribe(["interface", :_, "addresses"])
  ```
  """
  @spec subscribe(pattern()) :: :ok
  def subscribe(name) do
    PropertyTable.subscribe(Peridio.NetMon, name)
  end

  @doc """
  Stop subscribing to property change messages
  """
  @spec unsubscribe(pattern()) :: :ok
  def unsubscribe(name) do
    PropertyTable.unsubscribe(Peridio.NetMon, name)
  end

    @doc """
  Print the current network status
  """
  @spec info(info_options()) :: :ok
  defdelegate info(options \\ []), to: Info
end
