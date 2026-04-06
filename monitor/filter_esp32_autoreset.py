import time

from platformio.device.monitor.filters.base import DeviceMonitorFilterBase


class ESP32AutoReset(DeviceMonitorFilterBase):
    NAME = "esp32_autoreset"

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._did_pulse = False

    def set_running_terminal(self, terminal):
        super().set_running_terminal(terminal)
        if self._did_pulse:
            return
        self._did_pulse = True

        ser = terminal.serial
        # Keep IO0 high (normal boot), then pulse EN via RTS (esptool HardReset).
        try:
            ser.setDTR(False)
        except Exception:
            pass
        try:
            ser.setRTS(True)   # EN=LOW (reset asserted)
            time.sleep(0.10)
            ser.setRTS(False)  # EN=HIGH (run)
            time.sleep(0.05)
        except Exception:
            pass

    def rx(self, text):
        return text

    def tx(self, text):
        return text
