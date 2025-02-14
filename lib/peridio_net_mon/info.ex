defmodule Peridio.NetMon.Info do
  @moduledoc false

  @doc """
  Print the current network status
  """
  @spec info(Peridio.NetMon.info_options()) :: :ok
  def info(opts \\ []) do
    info_as_ansidata(opts)
    |> IO.ANSI.format()
    |> IO.puts()
  end

  @doc """
  Format the information as ANSI data
  """
  @spec info_as_ansidata(Peridio.NetMon.info_options()) :: IO.ANSI.ansidata()
  def info_as_ansidata(opts \\ []) do
    case peridio_net_mon_app_info() do
      {:ok, text} ->
        ifnames = interfaces_to_show()
        [text, format_header(), format_interfaces(ifnames, opts)]

      {:error, text} ->
        text
    end
  end

  defp format_header() do
    """


    All interfaces:       #{inspect(Peridio.NetMon.all_interfaces())}
    Available interfaces: #{inspect(Peridio.NetMon.get(["available_interfaces"]))}

    """
  end

  defp format_interfaces([], _opts) do
    "No interfaces\n\n"
  end

  defp format_interfaces(ifnames, opts) do
    Enum.map(ifnames, &format_interface(&1, opts))
  end

  defp interfaces_to_show() do
    type = Peridio.NetMon.match(["interface", :_, "type"])

    for {[_interface, ifname, _type], _value} <- type do
      ifname
    end
  end

  defp format_interface(ifname, _opts) do
    if Peridio.NetMon.get(["interface", ifname, "present"]) do
      [
        "Interface ",
        ifname,
        "\n",
        format_if_attribute(ifname, "type", "Type"),
        format_if_attribute(ifname, "present", "Present"),
        format_if_attribute(ifname, "state", "State", true),
        format_if_attribute(ifname, "connection", "Connection", true),
        format_addresses(ifname),
        format_if_attribute(ifname, "mac_address", "MAC Address"),
        "\n"
      ]
    else
      [
        "Interface ",
        ifname,
        "\n",
        format_if_attribute(ifname, "type", "Type"),
        "  Present: false\n",
        "\n"
      ]
    end
  end

  defp loaded?(app) do
    Application.loaded_applications()
    |> List.keyfind(app, 0)
    |> case do
      {^app, _description, _version} -> true
      _ -> false
    end
  end

  defp started?(app) do
    Application.started_applications()
    |> List.keyfind(app, 0)
    |> case do
      {^app, _description, _version} -> true
      _ -> false
    end
  end

  defp peridio_net_mon_app_info() do
    cond do
      not loaded?(:peridio_net_mon) ->
        {:error, "Peridio.NetMon hasn't been loaded. If the system just booted, try again shortly."}

      not started?(:peridio_net_mon) ->
        {:error,
         "Peridio.NetMon loaded, but not started. Check the log to see if an error stopped the :peridio_net_mon application."}

      true ->
        {:ok, "Peridio.NetMon #{Application.spec(:peridio_net_mon)[:vsn]}"}
    end
  end

  defp format_if_attribute(ifname, name, print_name, print_since? \\ false) do
    case PropertyTable.fetch_with_timestamp(Peridio.NetMon, ["interface", ifname, name]) do
      {:ok, value, timestamp} ->
        [
          "  ",
          print_name,
          ": ",
          inspect(value),
          if(print_since?,
            do: [
              " (",
              friendly_time(System.monotonic_time() - timestamp),
              ")\n"
            ],
            else: "\n"
          )
        ]

      :error ->
        # Mirror previous behavior (i.e., print nil for unset attributes)
        ["  ", print_name, ": nil\n"]
    end
  end

  defp format_addresses(ifname) do
    case Peridio.NetMon.get(["interface", ifname, "addresses"]) do
      nil -> []
      [] -> []
      addresses -> ["  Addresses: ", pretty_addresses(addresses), "\n"]
    end
  end

  defp pretty_addresses(addresses) do
    addresses
    |> Enum.map(&pretty_address/1)
    |> Enum.intersperse(", ")
  end

  defp pretty_address(%{address: address, prefix_length: bits}) do
    Peridio.NetMon.IP.cidr_to_string(address, bits)
  end

  defp pretty_address(other) do
    inspect(other)
  end

  @spec friendly_time(integer()) :: iodata()
  def friendly_time(delta_ns) when is_integer(delta_ns) do
    cond do
      delta_ns < 1000 -> "#{delta_ns} ns"
      delta_ns < 1_000_000 -> :io_lib.format(~c"~.1f μs", [delta_ns / 1000])
      delta_ns < 1_000_000_000 -> :io_lib.format(~c"~.1f ms", [delta_ns / 1_000_000])
      delta_ns < 60_000_000_000 -> :io_lib.format(~c"~.1f s", [delta_ns / 1_000_000_000])
      true -> format_seconds(div(delta_ns, 1_000_000_000))
    end
  end

  defp format_seconds(seconds) do
    days = seconds |> div(86400)
    h = seconds |> div(3600) |> rem(24)
    m = seconds |> div(60) |> rem(60)
    s = seconds |> rem(60)

    [
      if(days > 0, do: [Integer.to_string(days), " days, "], else: []),
      Integer.to_string(h),
      ":",
      zero_pad(m),
      ":",
      zero_pad(s)
    ]
  end

  defp zero_pad(x), do: String.pad_leading(Integer.to_string(x), 2, "0")
end
