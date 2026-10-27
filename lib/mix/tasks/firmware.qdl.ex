defmodule Mix.Tasks.Firmware.Qdl do
  @shortdoc "Provision an Arduino UNO Q over USB using Qualcomm EDL mode"

  @moduledoc """
  Provisions an Arduino UNO Q with your Nerves firmware over USB.

  Use this the first time you install Nerves on a board, or to recover one.
  It works whatever is on the eMMC, because it uses the QRB2210's Emergency
  Download (EDL) mode, which is built into the chip. After that, update the
  board as usual with `mix upload`.

  It rewrites the eMMC with:

    * Qualcomm's boot firmware, from Arduino's eMMC bootloader bundle
    * a partition table with the Nerves partitions
    * your firmware, as `fwup -t complete` would write it

  Anything in the application data partition is lost.

      mix firmware.qdl

  ## Requirements

    * `fwup` on your `PATH`
    * access to USB device `05c6:9008`. On Linux, add a udev rule such as
      this, which also keeps ModemManager away from the board:

          SUBSYSTEMS=="usb", ATTRS{idVendor}=="05c6", ATTRS{idProduct}=="9008", MODE="0660", GROUP="plugdev", ENV{ID_MM_DEVICE_IGNORE}="1"

  It uses [`qdl`](https://github.com/linux-msm/qdl) to talk to the board. If
  `qdl` isn't on your `PATH`, it downloads Arduino's prebuilt `qdl` for your
  computer.

  ## Options

    * `--firmware PATH` - the `.fw` file to install. Defaults to the one
      `mix firmware` builds.
    * `--dry-run` - prepare everything and run `qdl --dry-run` without a board
  """

  use Mix.Task

  alias NervesSystemArduinoUnoQ.QDL

  @bundle "unoq-bootloader-emmc-linux-251020"
  @bundle_url "https://downloads.arduino.cc/debian-im/#{@bundle}.zip"
  @bundle_sha256 "c606e95d0107f8c58d0dd9494e00624d1db7c4361cca20513bc78ef02ca28dd1"

  @qdl_version "v2.5-30"
  @qdl_url "https://github.com/arduino/qdl-packing/releases/download/#{@qdl_version}"
  @qdl_builds %{
    {:linux, "x86_64"} =>
      {"Linux_64bit", "b8d3f1efbba801b0bb90c5d2960d5f41c7c30bfe5f10293848f93760de621863"},
    {:linux, "aarch64"} =>
      {"Linux_ARM64", "d26f91a00f5c58e3b995d05439b6c0fc11c00902ee1d2cc6864dbb57c2f0949c"},
    {:linux, "arm"} =>
      {"Linux_ARMv6", "388907f058692e275de90671501f8547e1a7c37074e3f81b4c3ec4bbb4e68709"},
    {:linux, "i686"} =>
      {"Linux_32bit", "0f5dd5ecee1ea14d94a084daa89a51714a717806c43d287af89b8e4a0e5497db"},
    {:darwin, "x86_64"} =>
      {"macOS_64bit", "3ddf854057f30c137d4d06fd4b43af882475e2014322f118c51d4995da6b53b5"},
    {:darwin, "aarch64"} =>
      {"macOS_arm64", "bf73fa12b124c568286b220f8b7e5826993160575e9f12b084f10f4b56f35b1a"},
    {:windows, :any} =>
      {"Windows_32bit", "8433e43ea1ae38179dd400a2502ca639ddb63b0883d649850c706fc908f7b33e"}
  }

  @edl_vendor "05c6"
  @edl_product "9008"
  @edl_wait_ms 300_000

  @switches [firmware: :string, dry_run: :boolean]

  @impl Mix.Task
  def run(args) do
    {opts, _} = OptionParser.parse!(args, strict: @switches)
    dry_run? = Keyword.get(opts, :dry_run, false)
    firmware = Keyword.get_lazy(opts, :firmware, &default_firmware/0)

    File.regular?(firmware) ||
      Mix.raise("Firmware not found at #{firmware}. Run `mix firmware` first.")

    fwup = find_executable!("fwup", "https://github.com/fwup-home/fwup#installing")
    qdl = System.find_executable("qdl") || prebuilt_qdl()

    bundle_dir = bootloader_bundle()
    work_dir = Path.join(System.tmp_dir!(), "nerves_qdl_#{System.unique_integer([:positive])}")

    try do
      flash_dir = prepare(fwup, firmware, bundle_dir, work_dir)

      if dry_run? do
        qdl!(qdl, flash_dir, ["--dry-run"])
        Mix.shell().info([:green, "Dry run succeeded.", :reset])
      else
        wait_for_edl()
        qdl!(qdl, flash_dir, [])
        finished()
      end
    after
      File.rm_rf!(work_dir)
    end
  end

  defp default_firmware do
    app = Mix.Project.config()[:app]
    Path.join([Mix.Project.build_path(), "nerves", "images", "#{app}.fw"])
  end

  defp find_executable!(name, url) do
    System.find_executable(name) || Mix.raise("Can't find `#{name}`. See #{url} to install it.")
  end

  defp prepare(fwup, firmware, bundle_dir, work_dir) do
    Mix.shell().info("Preparing #{Path.relative_to_cwd(firmware)}...")
    File.mkdir_p!(work_dir)
    image = Path.join(work_dir, "nerves.img")

    {output, status} =
      System.cmd(fwup, ["-a", "-q", "-d", image, "-i", firmware, "-t", "complete"],
        stderr_to_stdout: true
      )

    status == 0 || Mix.raise("fwup failed:\n#{output}")

    flash_dir = Path.join(work_dir, "flash")
    QDL.write_flash_dir(bundle_dir, image, flash_dir)
    File.rm!(image)
    flash_dir
  end

  defp dl_dir, do: System.get_env("NERVES_DL_DIR", Path.expand("~/.nerves/dl"))

  defp bootloader_bundle do
    bundle_dir = Path.join(dl_dir(), @bundle)

    unless File.dir?(bundle_dir) do
      zip = fetch!("Arduino's eMMC bootloader bundle", @bundle_url, @bundle_sha256)
      {:ok, _} = :zip.unzip(String.to_charlist(zip), cwd: String.to_charlist(dl_dir()))
    end

    bundle_dir
  end

  defp prebuilt_qdl do
    {build, sha256} = qdl_build!()
    exe = if match?({:win32, _}, :os.type()), do: "qdl.exe", else: "qdl"
    dir = Path.join(dl_dir(), "qdl_#{@qdl_version}_#{build}")
    path = Path.join(dir, exe)

    unless File.regular?(path) do
      tarball = fetch!("qdl", "#{@qdl_url}/qdl_#{@qdl_version}_#{build}.tar.gz", sha256)

      :ok =
        :erl_tar.extract(String.to_charlist(tarball), [
          :compressed,
          cwd: String.to_charlist(dir),
          files: [String.to_charlist(exe)]
        ])

      File.chmod!(path, 0o755)
    end

    path
  end

  defp qdl_build! do
    [arch | _] = :erlang.system_info(:system_architecture) |> to_string() |> String.split("-")

    platform =
      case {:os.type(), arch} do
        {{:win32, _}, _} -> {:windows, :any}
        {{:unix, os}, arch} when arch in ~w(i386 i486 i586 i686) -> {os, "i686"}
        {{:unix, os}, "arm" <> _} -> {os, "arm"}
        {{:unix, os}, arch} -> {os, arch}
      end

    Map.get(@qdl_builds, platform) ||
      Mix.raise("""
      There's no prebuilt qdl for this computer (#{arch}).
      Install qdl from https://github.com/linux-msm/qdl and make sure it's on your PATH.
      """)
  end

  # Downloads url to the Nerves download directory unless a copy with the
  # expected SHA-256 is already there.
  defp fetch!(description, url, sha256) do
    path = Path.join(dl_dir(), url |> URI.parse() |> Map.fetch!(:path) |> Path.basename())

    unless File.regular?(path) and sha256(path) == sha256 do
      download!(description, url, path)
    end

    sha256(path) == sha256 ||
      Mix.raise("#{path} doesn't match its expected SHA-256. Delete it and try again.")

    path
  end

  defp download!(description, url, path) do
    Mix.shell().info("Downloading #{description} from #{url}...")
    {:ok, _} = Application.ensure_all_started([:inets, :ssl])
    File.mkdir_p!(Path.dirname(path))

    ssl = [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      depth: 4,
      # GitHub redirects release downloads to a host with a wildcard certificate
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
    ]

    case :httpc.request(:get, {String.to_charlist(url), []}, [ssl: ssl],
           stream: String.to_charlist(path)
         ) do
      {:ok, :saved_to_file} -> :ok
      other -> Mix.raise("Download of #{url} failed: #{inspect(other)}")
    end
  end

  defp sha256(path) do
    path
    |> File.stream!(65_536)
    |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  end

  defp wait_for_edl do
    Mix.shell().info("""

    Put the UNO Q into Emergency Download (EDL) mode:

      1. Unplug the UNO Q's USB-C cable.
      2. Connect the GND and USB_BOOT pins in the rightmost column of the
         JCTL header with a jumper or a wire.
      3. Plug the USB-C cable back in, directly into this computer rather
         than through a hub.
    """)

    if File.dir?("/sys/bus/usb/devices") do
      Mix.shell().info(
        "Waiting for the UNO Q in EDL mode (USB #{@edl_vendor}:#{@edl_product})..."
      )

      await_edl(System.monotonic_time(:millisecond) + @edl_wait_ms)
    else
      Mix.shell().prompt("Press Enter when it's connected.")
    end
  end

  defp await_edl(deadline) do
    cond do
      edl_connected?() ->
        Mix.shell().info("Found it.")

      System.monotonic_time(:millisecond) > deadline ->
        Mix.raise(
          "No UNO Q in EDL mode showed up. Check the jumper and the cable, then try again."
        )

      true ->
        Process.sleep(500)
        await_edl(deadline)
    end
  end

  defp edl_connected? do
    Path.wildcard("/sys/bus/usb/devices/*/idVendor")
    |> Enum.any?(fn vendor_file ->
      dir = Path.dirname(vendor_file)

      File.read(vendor_file) == {:ok, @edl_vendor <> "\n"} and
        File.read(Path.join(dir, "idProduct")) == {:ok, @edl_product <> "\n"}
    end)
  end

  defp qdl!(qdl, flash_dir, extra_args) do
    args =
      extra_args ++
        ["--storage", "emmc", "prog_firehose_ddr.elf", "rawprogram0.xml", "patch0.xml"]

    case System.cmd(qdl, args, cd: flash_dir, into: IO.stream(), stderr_to_stdout: true) do
      {_, 0} ->
        :ok

      {_, status} ->
        Mix.raise("""
        qdl failed (exit status #{status}).

        If it couldn't open the device, check that you can access USB device
        #{@edl_vendor}:#{@edl_product} (see `mix help firmware.qdl`). If it failed partway through,
        try another cable or USB port; hubs and docks often cause trouble.
        """)
    end
  end

  defp finished do
    Mix.shell().info([
      :green,
      """

      The UNO Q is provisioned.

        1. Unplug the USB-C cable.
        2. Remove the GND to USB_BOOT jumper.
        3. Plug the USB-C cable back in. The board boots Nerves.

      From now on you can update it with `mix upload`.
      """,
      :reset
    ])
  end
end
