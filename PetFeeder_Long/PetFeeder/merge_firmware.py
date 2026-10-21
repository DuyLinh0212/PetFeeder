# Produce a complete ESP32 image with the same partition table as PlatformIO.
Import("env")
def merge(source, target, env):
    environment = env
    import subprocess
    from pathlib import Path
    build = Path(environment.subst("$BUILD_DIR"))
    tool = Path(environment.PioPlatform().get_package_dir("tool-esptoolpy")) / "esptool.py"
    framework = Path(environment.PioPlatform().get_package_dir("framework-arduinoespressif32"))
    subprocess.check_call([environment.subst("$PYTHONEXE"), str(tool), "--chip", "esp32", "merge_bin", "-o",
        str(build / "firmware.merged.bin"), "--flash_mode", "dio", "--flash_freq", "40m", "--flash_size", "4MB",
        "0x1000", str(build / "bootloader.bin"), "0x8000", str(build / "partitions.bin"),
        "0xe000", str(framework / "tools/partitions/boot_app0.bin"), "0x10000", str(build / "firmware.bin")])
env.AddPostAction("$BUILD_DIR/${PROGNAME}.bin", merge)
