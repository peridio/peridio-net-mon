defmodule Peridio.NetMon.Persistence.Null do
  @moduledoc """
  Don't save or load configuration at all.
  """
  @behaviour Peridio.NetMon.Persistence

  @impl Peridio.NetMon.Persistence
  def save(_ifname, _config) do
    :ok
  end

  @impl Peridio.NetMon.Persistence
  def load(_ifname) do
    {:error, :enotsupported}
  end

  @impl Peridio.NetMon.Persistence
  def clear(_ifname) do
    :ok
  end

  @impl Peridio.NetMon.Persistence
  def enumerate() do
    []
  end
end
