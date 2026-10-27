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

    * `fwup` and [`qdl`](https://github.com/linux-msm/qdl) on your `PATH`
    * access to USB device `05c6:9008`. On Linux, add a udev rule such as:

          SUBSYSTEMS=="usb", ATTRS{idVendor}=="05c6", ATTRS{idProduct}=="9008", MODE="0660", GROUP="plugdev"

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
    qdl = find_executable!("qdl", "https://github.com/linux-msm/qdl")

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

  defp bootloader_bundle do
    dl_dir = System.get_env("NERVES_DL_DIR", Path.expand("~/.nerves/dl"))
    zip = Path.join(dl_dir, "#{@bundle}.zip")
    bundle_dir = Path.join(dl_dir, @bundle)

    unless File.dir?(bundle_dir) do
      unless File.regular?(zip) and sha256(zip) == @bundle_sha256 do
        download!(@bundle_url, zip)
      end

      sha256(zip) == @bundle_sha256 ||
        Mix.raise("#{zip} doesn't match its expected SHA-256. Delete it and try again.")

      {:ok, _} = :zip.unzip(String.to_charlist(zip), cwd: String.to_charlist(dl_dir))
    end

    bundle_dir
  end

  defp download!(url, path) do
    Mix.shell().info("Downloading Arduino's eMMC bootloader bundle from #{url}...")
    {:ok, _} = Application.ensure_all_started([:inets, :ssl])
    File.mkdir_p!(Path.dirname(path))

    ssl = [verify: :verify_peer, cacerts: :public_key.cacerts_get(), depth: 4]

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
