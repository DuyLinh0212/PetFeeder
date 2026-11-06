# Produce a complete ESP32 image using the same application offset as partitions.csv.
Import("env")
def merge(source, target, env):
    import csv
    import subprocess
    from pathlib import Path

    environment = env
    project = Path(environment.subst("$PROJECT_DIR"))
    build = Path(environment.subst("$BUILD_DIR"))
    tool = Path(environment.PioPlatform().get_package_dir("tool-esptoolpy")) / "esptool.py"
    framework = Path(environment.PioPlatform().get_package_dir("framework-arduinoespressif32"))
    partition_table = project / "partitions.csv"

    app_offset = None
    with partition_table.open(encoding="utf-8", newline="") as csv_file:
        for row in csv.reader(csv_file):
            if len(row) >= 5 and row[0].strip() and not row[0].lstrip().startswith("#"):
                if row[1].strip() == "app" and row[2].strip() in ("factory", "ota_0"):
                    app_offset = row[3].strip()
                    break
    if not app_offset:
        raise RuntimeError(f"No factory or ota_0 app partition found in {partition_table}")

    subprocess.check_call([
        environment.subst("$PYTHONEXE"), str(tool), "--chip", "esp32", "merge_bin", "-o",
        str(build / "firmware.merged.bin"), "--flash_mode", "dio", "--flash_freq", "40m", "--flash_size", "4MB",
        "0x1000", str(build / "bootloader.bin"), "0x8000", str(build / "partitions.bin"),
        "0xe000", str(framework / "tools/partitions/boot_app0.bin"), app_offset, str(build / "firmware.bin")
    ])
env.AddPostAction("$BUILD_DIR/${PROGNAME}.bin", merge)