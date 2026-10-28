defmodule NervesSystemArduinoUnoQ.QDL do
  @moduledoc """
  Builds a Qualcomm EDL (QDL) flash directory that provisions an Arduino UNO Q
  with Nerves.

  It starts from Arduino's eMMC bootloader bundle, keeps Qualcomm's partitions
  1 to 66 and their boot firmware, replaces the last partitions of the GPT with
  the Nerves layout and writes the Nerves firmware into them.

  The Nerves firmware is written as regions cut from a disk image produced by
  `fwup -t complete`, so fwup stays the only thing that knows how to lay out a
  firmware update.
  """

  import Bitwise

  @sector_size 512

  # GPT entries are 128 bytes from LBA 2. Arduino's GPT has room for 72.
  @gpt_entry_size 128
  @gpt_entries_lba 2
  @gpt_entry_count 72

  # Partition attribute bit 60 is set on every partition in Arduino's GPT.
  @gpt_attributes 0x1000000000000000

  # ABL keeps its A/B slot state in the attributes of the first `boot_a` and
  # `boot_b` entries, which hold U-Boot. It counts down the active slot's
  # retries on every boot until the OS marks it successful, then gives up
  # and stops in fastboot. Nothing on Nerves marks it, and both slots hold
  # the same U-Boot, so both start out successful with slot A active.
  @abl_priority_shift 48
  @abl_active 1 <<< 50
  @abl_max_retries 7 <<< 51
  @abl_successful 1 <<< 54
  @abl_slots [
    {"boot_a",
     @gpt_attributes ||| 3 <<< @abl_priority_shift ||| @abl_active ||| @abl_max_retries |||
       @abl_successful},
    {"boot_b",
     @gpt_attributes ||| 2 <<< @abl_priority_shift ||| @abl_max_retries ||| @abl_successful}
  ]
  @linux_type "0FC63DAF-8483-4772-8E79-3D69D8477DE4"
  @basic_data_type "EBD0A0A2-B9E5-4433-87C0-68B6B72699C7"

  # These must match fwup_include/fwup-common.conf.
  @abl_boot_a 166_400
  @abl_boot_b 174_592
  @abl_boot_count 8192
  @uboot_env 8192
  @uboot_env_count 256
  @boot_a 987_136
  @boot_count 262_144
  @rootfs_count 1_048_576
  @boot_b @boot_a + @boot_count
  @rootfs_a @boot_b + @boot_count
  @rootfs_b @rootfs_a + @rootfs_count
  @data @rootfs_b + @rootfs_count

  # The data partition grows to the end of the eMMC. Its size is patched in
  # when flashing, as Arduino does for userdata.
  @partitions [
    {67, "boot_a", @basic_data_type, @boot_a, @boot_count},
    {68, "boot_b", @basic_data_type, @boot_b, @boot_count},
    {69, "rootfs_a", @linux_type, @rootfs_a, @rootfs_count},
    {70, "rootfs_b", @linux_type, @rootfs_b, @rootfs_count},
    {71, "data", @linux_type, @data, :rest}
  ]

  # Regions of the `fwup -t complete` image to write, as {start, count}.
  # B and data only need their first sectors, which fwup invalidates.
  @image_slices [
    {"uboot-env", @uboot_env, @uboot_env_count},
    {"abl_boot_a", @abl_boot_a, @abl_boot_count},
    {"abl_boot_b", @abl_boot_b, @abl_boot_count},
    {"boot_a", @boot_a, @boot_count},
    {"boot_b", @boot_b, 256},
    {"rootfs_a", @rootfs_a, @rootfs_count},
    {"rootfs_b", @rootfs_b, 256},
    {"data", @data, 256}
  ]

  @first_nerves_partition 67
  @last_partition 71

  @typedoc "The Nerves partitions as `{number, name, type GUID, first LBA, size}`"
  @type partition ::
          {pos_integer(), String.t(), String.t(), non_neg_integer(), pos_integer() | :rest}

  @doc "The Nerves partitions at the end of the GPT."
  @spec partitions() :: [partition()]
  def partitions, do: @partitions

  @doc "The regions of the fwup image that get written to the eMMC."
  @spec image_slices() :: [{String.t(), non_neg_integer(), pos_integer()}]
  def image_slices, do: @image_slices

  @doc """
  Writes a QDL flash directory to `out_dir`.

  `bootloader_dir` is the extracted Arduino bootloader bundle and `image` is the
  disk image from `fwup -t complete`.
  """
  @spec write_flash_dir(Path.t(), Path.t(), Path.t()) :: :ok
  def write_flash_dir(bootloader_dir, image, out_dir) do
    File.mkdir_p!(out_dir)

    for file <- qualcomm_files(bootloader_dir) do
      File.cp!(Path.join(bootloader_dir, file), Path.join(out_dir, file))
    end

    {main, backup} =
      gpt(
        File.read!(Path.join(bootloader_dir, "gpt_main0.bin")),
        File.read!(Path.join(bootloader_dir, "gpt_backup0.bin"))
      )

    File.write!(Path.join(out_dir, "gpt_main0.bin"), main)
    File.write!(Path.join(out_dir, "gpt_backup0.bin"), backup)
    write_image_slices(image, out_dir)

    File.write!(
      Path.join(out_dir, "rawprogram0.xml"),
      rawprogram(File.read!(Path.join(bootloader_dir, "rawprogram0.xml")))
    )

    File.write!(
      Path.join(out_dir, "patch0.xml"),
      patch(File.read!(Path.join(bootloader_dir, "patch0.xml")))
    )
  end

  @doc """
  Replaces Arduino's last partitions in its primary and backup GPT images with
  the Nerves partitions, and marks both of ABL's boot slots successful. Header
  and partition array CRCs are fixed up by `patch0.xml` while flashing, once
  the eMMC size is known.
  """
  @spec gpt(binary(), binary()) :: {binary(), binary()}
  def gpt(main, backup) do
    array_bytes = @gpt_entry_count * @gpt_entry_size
    array_offset = @gpt_entries_lba * @sector_size

    <<main_head::binary-size(^array_offset), array::binary-size(^array_bytes), main_tail::binary>> =
      main

    <<_backup_array::binary-size(^array_bytes), backup_tail::binary>> = backup

    keep = (@first_nerves_partition - 1) * @gpt_entry_size
    <<arduino_qualcomm::binary-size(^keep), _::binary>> = array

    qualcomm =
      for <<entry::binary-size(@gpt_entry_size) <- arduino_qualcomm>>,
        into: <<>>,
        do: abl_slot_entry(entry)

    nerves = Enum.map_join(@partitions, &gpt_entry/1)
    padding = :binary.copy(<<0>>, array_bytes - keep - byte_size(nerves))
    new_array = qualcomm <> nerves <> padding

    {main_head <> new_array <> main_tail, new_array <> backup_tail}
  end

  @doc """
  Generates `rawprogram0.xml` from Arduino's: Qualcomm's boot firmware and the
  GPT as before, then the Nerves image slices instead of Arduino's U-Boot,
  `efi`, `rootfs` and `userdata`.
  """
  @spec rawprogram(String.t()) :: String.t()
  def rawprogram(arduino_xml) do
    replaced = ~w(boot_a boot_b efi rootfs userdata)

    qualcomm =
      Regex.scan(~r/<program [^>]*\/>/, arduino_xml)
      |> List.flatten()
      |> Enum.reject(fn program -> attribute(program, "label") in replaced end)

    nerves = Enum.map(@image_slices, &image_program/1)

    """
    <?xml version="1.0" ?>
    <data>
    #{Enum.map_join(qualcomm ++ nerves, "\n", &("  " <> &1))}
    </data>
    """
  end

  @doc """
  Generates `patch0.xml` from Arduino's, pointing its "last partition" fix-ups
  at the Nerves data partition instead of `userdata`.
  """
  @spec patch(String.t()) :: String.t()
  def patch(arduino_xml) do
    {_sector, offset} = entry_position(@last_partition)

    Regex.replace(~r/<patch [^>]*Update last partition[^>]*\/>/, arduino_xml, fn line ->
      line
      |> String.replace(~r/byte_offset="\d+"/, ~s(byte_offset="#{offset + 40}"))
      |> String.replace(~r/partition \d+ '\w+'/, "partition #{@last_partition} 'data'")
    end)
  end

  @doc "The sector within the partition array and byte offset of a partition's entry."
  @spec entry_position(pos_integer()) :: {non_neg_integer(), non_neg_integer()}
  def entry_position(partition) do
    byte = (partition - 1) * @gpt_entry_size
    {div(byte, @sector_size), rem(byte, @sector_size)}
  end

  defp qualcomm_files(bootloader_dir) do
    bootloader_dir
    |> Path.join("rawprogram0.xml")
    |> File.read!()
    |> then(&Regex.scan(~r/filename="([^"]+)"/, &1, capture: :all_but_first))
    |> List.flatten()
    |> Enum.reject(
      &(&1 in ["", "boot.img", "gpt_main0.bin", "gpt_backup0.bin"] or
          String.starts_with?(&1, ".."))
    )
    |> Enum.concat(["prog_firehose_ddr.elf"])
    |> Enum.uniq()
  end

  defp attribute(element, name) do
    case Regex.run(~r/\s#{name}="([^"]*)"/, element, capture: :all_but_first) do
      [value] -> value
      nil -> nil
    end
  end

  # Each region gets its own file so qdl doesn't warn that the whole image is
  # bigger than the partition. Runs of zeros are left as holes.
  defp write_image_slices(image, out_dir) do
    chunk = 1024 * 1024
    {:ok, source} = :file.open(image, [:read, :raw, :binary])

    try do
      for {label, start, count} <- @image_slices do
        size = count * @sector_size
        {:ok, slice} = :file.open(Path.join(out_dir, slice_file(label)), [:write, :raw, :binary])

        for offset <- 0..(size - 1)//chunk do
          case :file.pread(source, start * @sector_size + offset, min(chunk, size - offset)) do
            {:ok, data} ->
              if data != <<0::size(byte_size(data) * 8)>>,
                do: :ok = :file.pwrite(slice, offset, data)

            :eof ->
              :ok
          end
        end

        {:ok, _} = :file.position(slice, size)
        :ok = :file.truncate(slice)
        :ok = :file.close(slice)
      end
    after
      :file.close(source)
    end
  end

  defp slice_file(label), do: "nerves-#{label}.bin"

  defp image_program({label, start, count}) do
    ~s(<program SECTOR_SIZE_IN_BYTES="#{@sector_size}" file_sector_offset="0" ) <>
      ~s(filename="#{slice_file(label)}" label="#{label}" num_partition_sectors="#{count}" ) <>
      ~s(partofsingleimage="false" physical_partition_number="0" readbackverify="false" ) <>
      ~s(size_in_KB="#{div(count * @sector_size, 1024)}.0" sparse="false" ) <>
      ~s(start_byte_hex="0x#{Integer.to_string(start * @sector_size, 16)}" start_sector="#{start}"/>)
  end

  defp abl_slot_entry(<<head::binary-48, _attributes::binary-8, name::binary-72>> = entry) do
    case Enum.find(@abl_slots, fn {slot, _} -> name_field(slot) == name end) do
      {_slot, attributes} -> head <> <<attributes::little-64>> <> name
      nil -> entry
    end
  end

  defp gpt_entry({_number, name, type, first, count}) do
    last = if count == :rest, do: first - 1, else: first + count - 1

    guid_bytes(type) <>
      :crypto.strong_rand_bytes(16) <>
      <<first::little-64, last::little-64, @gpt_attributes::little-64>> <>
      name_field(name)
  end

  defp name_field(name) do
    name_utf16 = :unicode.characters_to_binary(name, :utf8, {:utf16, :little})
    name_utf16 <> :binary.copy(<<0>>, 72 - byte_size(name_utf16))
  end

  # GPT stores the first three GUID fields little-endian.
  defp guid_bytes(guid) do
    [a, b, c, d, e] = String.split(guid, "-")
    <<a::32, b::16, c::16>> = Base.decode16!(a <> b <> c, case: :mixed)
    <<a::little-32, b::little-16, c::little-16>> <> Base.decode16!(d <> e, case: :mixed)
  end
end
