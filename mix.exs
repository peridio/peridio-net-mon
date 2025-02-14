defmodule Peridio.NetMon.MixProject do
  use Mix.Project

  def project do
    [
      app: :peridio_net_mon,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      compilers: [:elixir_make | Mix.compilers()],
      make_targets: ["all"],
      make_clean: ["mix_clean"],
      make_error_message: "",
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      env: [
        config: [],
        max_interface_count: 50,
        tmpdir: "/tmp/peridio-netmon",
        persistence: Peridio.NetMon.Persistence.FlatFile,
        persistence_dir: "/var/lib/peridio-netmon",
        persistence_secret: "obfuscate_things",
        # List of reliable hosts used to check Internet connectivity
        # Use IP addresses and port numbers here rather than names.
        internet_host_list: [
          # Cloudflare DNS over TCP
          {{1, 1, 1, 1}, 53},
          # Google public DNS over TCP
          {{8, 8, 8, 8}, 53},
          # OpenDNS
          {{208, 67, 222, 222}, 53},
          # Quad9
          {{9, 9, 9, 9}, 53},
          # Neustar
          {{156, 154, 70, 5}, 53}
        ],
        route_metric_fun: &Peridio.NetMon.Route.DefaultMetric.compute_metric/2
      ],
      extra_applications: [:logger, :crypto]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:property_table, "~> 0.2.0 or ~> 0.3.0"},
      {:elixir_make, "~> 0.6", runtime: false},
    ]
  end
end
