defmodule Peridio.NetMon.Supervisor do
  use Supervisor

  def start_link(args \\ nil) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(args) do
    args = args || Application.get_all_env(:peridio_net_mon)

    children = [
      {PropertyTable, name: Peridio.NetMon, tuple_events: true},
      Peridio.NetMon.InterfacesMonitor,
      {Peridio.NetMon.RouteManager, args},
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
