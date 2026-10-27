defmodule NervesSystemArduinoUnoQ.QDLTest do
  use ExUnit.Case, async: true

  alias NervesSystemArduinoUnoQ.QDL

  # Arduino's GPT: 72 entries of 128 bytes from LBA 2, with the 69th last.
  @entries 72 * 128

  defp arduino_gpt do
    entry = fn n -> <<n::little-128>> <> :binary.copy(<<n>>, 112) end
    array = Enum.map_join(1..69, entry) <> :binary.copy(<<0>>, (72 - 69) * 128)
    main = :binary.copy(<<0xAA>>, 1024) <> array <> :binary.copy(<<0>>, 17_408 - 1024 - @entries)
    backup = array <> :binary.copy(<<0xBB>>, 512)
    {main, backup}
  end

  test "keeps Qualcomm's partitions and headers and adds the Nerves partitions" do
    {main, backup} = arduino_gpt()
    {new_main, new_backup} = QDL.gpt(main, backup)

    assert byte_size(new_main) == byte_size(main)
    assert byte_size(new_backup) == byte_size(backup)
    assert binary_part(new_main, 0, 1024) == binary_part(main, 0, 1024)
    assert binary_part(new_main, 1024, 66 * 128) == binary_part(main, 1024, 66 * 128)
    assert binary_part(new_backup, 0, @entries) == binary_part(new_main, 1024, @entries)
    assert binary_part(new_backup, @entries, 512) == binary_part(backup, @entries, 512)

    for {number, name, _type, first, count} <- QDL.partitions() do
      <<_type_guid::binary-16, _guid::binary-16, entry_first::little-64, entry_last::little-64,
        _attrs::little-64, raw_name::binary-72>> =
        binary_part(new_main, 1024 + (number - 1) * 128, 128)

      assert entry_first == first
      assert entry_last == if(count == :rest, do: first - 1, else: first + count - 1)

      assert raw_name
             |> :unicode.characters_to_binary({:utf16, :little})
             |> String.trim_trailing(<<0>>) == name
    end

    assert binary_part(new_main, 1024 + 71 * 128, 128) == :binary.copy(<<0>>, 128)
  end

  test "points the last-partition patches at the data partition" do
    arduino = """
    <patches>
      <patch start_sector="19" byte_offset="40" size_in_bytes="8" value="NUM_DISK_SECTORS-34." filename="DISK" what="Update last partition 69 'userdata' with actual size in Primary Header."/>
      <patch start_sector="1" byte_offset="48" size_in_bytes="8" value="NUM_DISK_SECTORS-34." filename="DISK" what="Update Primary Header with LastUseableLBA."/>
    </patches>
    """

    patched = QDL.patch(arduino)
    assert patched =~ ~s(start_sector="19" byte_offset="296")
    assert patched =~ "partition 71 'data'"
    assert patched =~ ~s(start_sector="1" byte_offset="48")
    assert QDL.entry_position(71) == {17, 256}
  end

  test "replaces Arduino's U-Boot and Linux partitions with the Nerves image regions" do
    arduino = """
    <data>
      <program filename="xbl.elf" label="xbl_a" start_sector="131072"/>
      <program filename="boot.img" label="boot_a" start_sector="166400"/>
      <program filename="../disk-sdcard.img.root" label="rootfs" start_sector="2033984"/>
    </data>
    """

    xml = QDL.rawprogram(arduino)
    assert xml =~ ~s(label="xbl_a")
    refute xml =~ "boot.img"
    refute xml =~ "disk-sdcard"
    assert length(Regex.scan(~r/filename="nerves-/, xml)) == length(QDL.image_slices())
  end

  test "matches the layout in fwup-common.conf" do
    defines = fwup_defines("fwup_include/fwup-common.conf")

    expected = %{
      "boot_a" => {defines["BOOT_A_PART_OFFSET"], defines["BOOT_A_PART_COUNT"]},
      "boot_b" => {defines["BOOT_B_PART_OFFSET"], defines["BOOT_B_PART_COUNT"]},
      "rootfs_a" => {defines["ROOTFS_A_PART_OFFSET"], defines["ROOTFS_A_PART_COUNT"]},
      "rootfs_b" => {defines["ROOTFS_B_PART_OFFSET"], defines["ROOTFS_B_PART_COUNT"]},
      "data" => {defines["APP_PART_OFFSET"], :rest}
    }

    for {_number, name, _type, first, count} <- QDL.partitions() do
      assert {first, count} == expected[name], name
    end

    slices = Map.new(QDL.image_slices(), fn {label, start, _} -> {label, start} end)
    assert slices["uboot-env"] == defines["UBOOT_ENV_OFFSET"]
    assert slices["abl_boot_a"] == defines["ABL_BOOT_A_PART_OFFSET"]
    assert slices["abl_boot_b"] == defines["ABL_BOOT_B_PART_OFFSET"]
  end

  # Evaluates fwup's define() and define-eval() for plain sums, which is all
  # fwup-common.conf uses for the layout.
  defp fwup_defines(path) do
    ~r/^define(?:-eval)?\((\w+), "?([^")]+)"?\)/m
    |> Regex.scan(File.read!(path), capture: :all_but_first)
    |> Enum.reduce(%{}, fn [name, value], defines ->
      expanded = Regex.replace(~r/\$\{(\w+)\}/, value, fn _, ref -> to_string(defines[ref]) end)

      case sum(expanded) do
        {:ok, number} -> Map.put(defines, name, number)
        :error -> defines
      end
    end)
  end

  defp sum(expression) do
    terms = expression |> String.split("+") |> Enum.map(&Integer.parse(String.trim(&1)))

    if Enum.all?(terms, &match?({_, ""}, &1)),
      do: {:ok, terms |> Enum.map(&elem(&1, 0)) |> Enum.sum()},
      else: :error
  end
end
